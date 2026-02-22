import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

if (admin.apps.length === 0) admin.initializeApp();
const db = admin.firestore();

const COLLECTION_BOOKS = "audiobooks";
const COLLECTION_USERS = "users";

const TOP_K_DEFAULT = 20;
const MAX_SEEDS = 12;

// Behavior weights (tune later)
const W_COMPLETED = 3.0;
const W_LISTENED = 2.0;
const W_LISTEN_NOW = 1.8;
const W_WANT = 1.4;

// Firestore "in" query limit
function chunk<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

function unique(arr: string[]): string[] {
  return Array.from(new Set(arr.filter(Boolean)));
}

// Library doc schema (based on your screenshots)
type LibraryItem = {
  bookId?: string;
  type?: "book" | "podcast";
  status?: string; // "listen_now" | "want" | "listened" | ...
  isCompleted?: boolean;
  lastOpenedAt?: admin.firestore.Timestamp;
  lastListenedAt?: admin.firestore.Timestamp;
  completedAt?: admin.firestore.Timestamp;
  updatedAt?: admin.firestore.Timestamp;
};

type BookOut = {
  id: string;
  title?: string;
  author?: string;
  category?: any;
  coverUrl?: string;
  description?: string;
  score: number;
};

function scoreForLibraryItem(it: LibraryItem): number {
  const status = (it.status || "").toLowerCase();

  // Highest signal
  if (it.isCompleted === true || status === "completed") return W_COMPLETED;

  // Common completion-like signals you use
  if (status === "listened") return W_LISTENED;

  // Strong intent
  if (status === "listen_now") return W_LISTEN_NOW;

  // Weak intent
  if (status === "want") return W_WANT;

  // Default small weight if it exists but unknown status
  return 0.8;
}

export const getPersonalizedRecommendations = onCall(
  { region: "europe-west1" },
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Login required.");

    const limit = Math.min(Number(req.data?.limit ?? TOP_K_DEFAULT), 50);

    // 1) Read latest user interactions from users/{uid}/library
    const libRef = db.collection(COLLECTION_USERS).doc(uid).collection("library");

    // We prefer the most recent interactions
    const libSnap = await libRef
      .orderBy("updatedAt", "desc")
      .limit(60)
      .get();

    if (libSnap.empty) {
      // Cold start: fallback recent books
      const q = await db.collection(COLLECTION_BOOKS).orderBy("createdAt", "desc").limit(limit).get();
      const out: BookOut[] = q.docs.map((d) => ({
        id: d.id,
        ...(d.data() as any),
        score: 0,
      }));
      return { items: out };
    }

    // 2) Build weighted seeds (only type=book)
    const seedWeights = new Map<string, number>();
    const exclude = new Set<string>(); // books user already interacted with

    for (const d of libSnap.docs) {
      const it = (d.data() || {}) as LibraryItem;

      // Only recommend audiobooks (skip podcasts)
      if ((it.type || "book") !== "book") continue;

      const bookId = (it.bookId || d.id || "").trim();
      if (!bookId) continue;

      exclude.add(bookId);

      const w = scoreForLibraryItem(it);
      seedWeights.set(bookId, Math.max(seedWeights.get(bookId) ?? 0, w));
    }

    const seeds = Array.from(seedWeights.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, MAX_SEEDS);

    if (seeds.length === 0) {
      // No book interactions (maybe all podcasts)
      const q = await db.collection(COLLECTION_BOOKS).orderBy("createdAt", "desc").limit(limit).get();
      const out: BookOut[] = q.docs.map((d) => ({ id: d.id, ...(d.data() as any), score: 0 }));
      return { items: out };
    }

    const seedIds = seeds.map(([id]) => id);

    // 3) Fetch seed book documents
    const seedDocs: admin.firestore.QueryDocumentSnapshot[] = [];
    for (const part of chunk(seedIds, 10)) {
      const q = await db
        .collection(COLLECTION_BOOKS)
        .where(admin.firestore.FieldPath.documentId(), "in", part)
        .get();
      seedDocs.push(...q.docs);
    }

    // 4) Aggregate candidates via similarBookIds
    const candidateScores = new Map<string, number>();

    for (const [seedId, w] of seeds) {
      const seed = seedDocs.find((x) => x.id === seedId);
      if (!seed) continue;

      const data = seed.data() as any;
      const similars: string[] = Array.isArray(data?.similarBookIds) ? data.similarBookIds : [];

      for (const candId of similars) {
        if (!candId) continue;
        if (exclude.has(candId)) continue;

        candidateScores.set(candId, (candidateScores.get(candId) ?? 0) + w);
      }
    }

    if (candidateScores.size === 0) {
      logger.info("No candidates found for uid:", uid);
      return { items: [] as BookOut[] };
    }

    // 5) Fetch candidate docs
    const sorted = Array.from(candidateScores.entries()).sort((a, b) => b[1] - a[1]);

    const fetchIds = unique(
      sorted.slice(0, Math.min(sorted.length, limit * 3)).map(([id]) => id)
    );

    const candDocs: admin.firestore.QueryDocumentSnapshot[] = [];
    for (const part of chunk(fetchIds, 10)) {
      const q = await db
        .collection(COLLECTION_BOOKS)
        .where(admin.firestore.FieldPath.documentId(), "in", part)
        .get();
      candDocs.push(...q.docs);
    }

    const docMap = new Map<string, admin.firestore.QueryDocumentSnapshot>();
    for (const d of candDocs) docMap.set(d.id, d);

    // 6) Build output
    const items: BookOut[] = [];
    for (const [id, score] of sorted) {
      const d = docMap.get(id);
      if (!d) continue;
      const b = d.data() as any;

      items.push({
        id: d.id,
        title: b.title,
        author: b.author,
        category: b.category,
        coverUrl: b.coverUrl ?? b.coverUrl ?? b.cover ?? b.imageUrl,
        description: b.description,
        score,
      });

      if (items.length >= limit) break;
    }

    return { items };
  }
);