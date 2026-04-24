import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentDeleted,
} from "firebase-functions/v2/firestore";

if (admin.apps.length === 0) admin.initializeApp();
const db = admin.firestore();

// ===== Collections =====
const COLLECTION_BOOKS = "audiobooks";
const COLLECTION_PODCASTS = "podcasts";
const COLLECTION_USERS = "users";

// ===== Config =====
const TOP_K_DEFAULT = 20;
const MAX_SEEDS = 12;

// Cold start: top rated books count
const COLD_START_TOP_RATED_BOOKS = 10;

// ✅ Cross-type fill ratio
const CROSS_TYPE_FILL_MULTIPLIER = 4; // fetch extra candidates = missing * this
const CROSS_TYPE_SCORE_MULTIPLIER = 0.55; // base cross weight

// ===== Behavior weights  =====
const W_COMPLETED = 3.0;
const W_LISTENED = 2.0;
const W_LISTEN_NOW = 1.8;
const W_WANT = 1.4;

// If no status, infer from lastAction
const W_ACTION_LISTEN = 1.6; // press_listen
const W_ACTION_SUMMARY = 1.1; // press_summary
const W_ACTION_OPEN = 0.9; // open_details
const W_ACTION_WANT = 1.3; // add_to_list_want

// Review weight (used as base when status is empty)
const W_ACTION_REVIEW = 1.7; // add_review

// ===== Helpers =====

// Recency boost (newer interactions weigh more)
function recencyMultiplier(ts?: admin.firestore.Timestamp): number {
  if (!ts) return 1.0;

  const nowMs = Date.now();
  const thenMs = ts.toDate().getTime();
  const ageHours = Math.max(0, (nowMs - thenMs) / (1000 * 60 * 60));

  if (ageHours <= 24) return 1.25;
  if (ageHours <= 72) return 1.15;
  if (ageHours <= 24 * 14) return 1.0;
  return 0.85;
}

function chunk<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

function unique(arr: string[]): string[] {
  return Array.from(new Set(arr.filter(Boolean)));
}

function normalizeType(x: any): "book" | "podcast" {
  const s = (x ?? "book").toString().toLowerCase().trim();
  return s === "podcast" ? "podcast" : "book";
}

function isIndexRequiredError(e: any): boolean {
  const msg = (e?.message ?? "").toString().toLowerCase();
  const code = (e?.code ?? "").toString().toLowerCase();
  return (
    msg.includes("requires an index") ||
    msg.includes("the query requires an index") ||
    msg.includes("failed_precondition") ||
    msg.includes("failed-precondition") ||
    code.includes("failed-precondition")
  );
}

// ✅ category is STRING in your schema
function normalizeCategory(c: any): string {
  return (c ?? "").toString().trim();
}
function toCategoryList(category: any): string[] {
  const c = normalizeCategory(category);
  return c ? [c] : [];
}

// ===== lightweight description similarity (no external libs) =====
function tokenize(text: any): string[] {
  const s = (text ?? "").toString().toLowerCase();
  // keep Arabic/English letters & numbers, split on others
  const tokens = s
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .split(/\s+/)
    .map((t) => t.trim())
    .filter(Boolean);

  // remove very short tokens (noise)
  return tokens.filter((t) => t.length >= 3).slice(0, 120);
}

function jaccard(aTokens: string[], bTokens: string[]): number {
  if (!aTokens.length || !bTokens.length) return 0;
  const A = new Set(aTokens);
  const B = new Set(bTokens);
  let inter = 0;
  for (const x of A) if (B.has(x)) inter++;
  const union = A.size + B.size - inter;
  return union <= 0 ? 0 : inter / union; // 0..1
}

// ===== Types =====
type LibraryItem = {
  bookId?: string;
  type?: "book" | "podcast";
  status?: string;
  isCompleted?: boolean;

  lastOpenedAt?: admin.firestore.Timestamp;
  lastListenedAt?: admin.firestore.Timestamp;
  completedAt?: admin.firestore.Timestamp;
  updatedAt?: admin.firestore.Timestamp;

  lastAction?: string;
  lastActionAt?: admin.firestore.Timestamp;
  lastSeenAt?: admin.firestore.Timestamp;

  // review rating signal (1..5)
  reviewRating?: number;
};

type ItemOut = {
  id: string;
  title?: string;
  author?: string;
  category?: any;
  coverUrl?: string;
  description?: string;
  score: number;
  type: "book" | "podcast";
};

// ✅ Cold-start helpers
async function coldStartBooks(topN: number): Promise<ItemOut[]> {
  try {
    const q = await db
      .collection(COLLECTION_BOOKS)
      .orderBy("ratingAvg", "desc")
      .orderBy("ratingCount", "desc")
      .limit(topN)
      .get();

    if (!q.empty) {
      return q.docs.map((d) => {
        const b = d.data() as any;
        return {
          id: d.id,
          title: b.title,
          author: b.author,
          category: b.category,
          coverUrl: b.coverUrl ?? b.cover ?? b.imageUrl ?? "",
          description: b.description,
          score: Number(b.ratingAvg ?? 0),
          type: "book",
        };
      });
    }
  } catch (e: any) {
    if (isIndexRequiredError(e)) {
      logger.warn("Cold-start top-rated books query requires index; fallback newest.", e);
    } else {
      logger.warn("Cold-start top-rated books query failed; fallback newest.", e);
    }
  }

  try {
    const q2 = await db
      .collection(COLLECTION_BOOKS)
      .orderBy("createdAt", "desc")
      .limit(topN)
      .get();

    return q2.docs.map((d) => {
      const b = d.data() as any;
      return {
        id: d.id,
        title: b.title,
        author: b.author,
        category: b.category,
        coverUrl: b.coverUrl ?? b.cover ?? b.imageUrl ?? "",
        description: b.description,
        score: 0,
        type: "book",
      };
    });
  } catch (e: any) {
    logger.warn("Cold-start newest books query failed; returning empty.", e);
    return [];
  }
}

async function coldStartPodcasts(limit: number): Promise<ItemOut[]> {
  try {
    const q = await db
      .collection(COLLECTION_PODCASTS)
      .orderBy("createdAt", "desc")
      .limit(limit)
      .get();

    return q.docs.map((d) => {
      const b = d.data() as any;
      return {
        id: d.id,
        title: b.title,
        author: b.author,
        category: b.category,
        coverUrl: b.coverUrl ?? b.cover ?? b.imageUrl ?? "",
        description: b.description,
        score: 0,
        type: "podcast",
      };
    });
  } catch (e: any) {
    logger.warn("Cold-start newest podcasts query failed; returning empty.", e);
    return [];
  }
}

/**
 * ✅ SCORING
 */
function scoreForLibraryItem(it: LibraryItem): number {
  const status = (it.status || "").toLowerCase().trim();
  const action = (it.lastAction || "").toLowerCase().trim();

  let base = 0.8;

  if (it.isCompleted === true || status === "completed") base = W_COMPLETED;
  else if (status === "listened") base = W_LISTENED;
  else if (status === "listen_now") base = W_LISTEN_NOW;
  else if (status === "want") base = W_WANT;
  else {
    if (action === "press_listen") base = W_ACTION_LISTEN;
    else if (action === "press_summary") base = W_ACTION_SUMMARY;
    else if (action === "open_details") base = W_ACTION_OPEN;
    else if (action === "add_to_list_want") base = W_ACTION_WANT;
    else if (action === "add_review") base = W_ACTION_REVIEW;
  }

  const r0 = it.reviewRating as any;
  const r =
    typeof r0 === "number"
      ? Math.max(1, Math.min(5, Math.round(r0)))
      : null;

  if (r != null) {
    if (r >= 4) base *= 1.25;
    else if (r === 3) base *= 1.0;
    else base *= 0.55;
  }

  return base;
}

function isStrongInteraction(it: LibraryItem): boolean {
  const status = (it.status ?? "").toLowerCase().trim();
  const action = (it.lastAction ?? "").toLowerCase().trim();

  if (
    status === "listen_now" ||
    status === "listened" ||
    status === "completed" ||
    status === "want"
  ) return true;

  if (action === "press_listen" || action === "add_review") return true;

  return false;
}

// ===== 1) Callable: Personalized Recommendations =====
export const getPersonalizedRecommendations = onCall(
  { region: "us-central1" },
  async (req) => {
    try {
      const uid = req.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Login required.");

      const limit = Math.min(Number(req.data?.limit ?? TOP_K_DEFAULT), 50);
      const wantedType = normalizeType(req.data?.type);

      const targetCollection =
        wantedType === "podcast" ? COLLECTION_PODCASTS : COLLECTION_BOOKS;

      const similarField =
        wantedType === "podcast" ? "similarPodcastIds" : "similarBookIds";

      const otherType: "book" | "podcast" =
        wantedType === "podcast" ? "book" : "podcast";

      const otherCollection =
        otherType === "podcast" ? COLLECTION_PODCASTS : COLLECTION_BOOKS;

      // 1) Read latest user interactions from users/{uid}/library
      const libRef = db
        .collection(COLLECTION_USERS)
        .doc(uid)
        .collection("library");

      const libSnap = await libRef.orderBy("updatedAt", "desc").limit(60).get();

      // Cold start ONLY if no interactions at all
      if (libSnap.empty) {
        if (wantedType === "book") {
          const topN = Math.min(limit, COLD_START_TOP_RATED_BOOKS);
          return { items: await coldStartBooks(topN) };
        }
        return { items: await coldStartPodcasts(limit) };
      }

      // 2) Build weighted seeds (same-type + other-type)
      const seedWeights = new Map<string, number>();
      const otherSeedWeights = new Map<string, number>();
      const hardExclude = new Set<string>();

      for (const d of libSnap.docs) {
        const it = (d.data() || {}) as LibraryItem;
        const itType = normalizeType(it.type);

        const itemId = (it.bookId || d.id || "").trim();
        if (!itemId) continue;

        if (isStrongInteraction(it)) hardExclude.add(itemId);

        let w = scoreForLibraryItem(it);
        const bestTs =
          it.lastActionAt || it.updatedAt || it.lastSeenAt || it.lastOpenedAt;
        w *= recencyMultiplier(bestTs);

        if (itType === wantedType) {
          seedWeights.set(itemId, Math.max(seedWeights.get(itemId) ?? 0, w));
        } else if (itType === otherType) {
          otherSeedWeights.set(
            itemId,
            Math.max(otherSeedWeights.get(itemId) ?? 0, w)
          );
        }
      }

      const seeds = Array.from(seedWeights.entries())
        .sort((a, b) => b[1] - a[1])
        .slice(0, MAX_SEEDS);

      const otherSeeds = Array.from(otherSeedWeights.entries())
        .sort((a, b) => b[1] - a[1])
        .slice(0, MAX_SEEDS);

      if (seeds.length === 0 && otherSeeds.length === 0) {
        // just in case (should be rare)
        if (wantedType === "book") {
          const topN = Math.min(limit, COLD_START_TOP_RATED_BOOKS);
          return { items: await coldStartBooks(topN) };
        }
        return { items: await coldStartPodcasts(limit) };
      }

      // 3) Fetch same-type seed docs
      const seedIds = seeds.map(([id]) => id);
      const seedDocs: admin.firestore.QueryDocumentSnapshot[] = [];

      if (seedIds.length > 0) {
        for (const part of chunk(seedIds, 10)) {
          const q = await db
            .collection(targetCollection)
            .where(admin.firestore.FieldPath.documentId(), "in", part)
            .get();
          seedDocs.push(...q.docs);
        }
      }

      // 4) Aggregate candidates via similarity field (same-type)
      const candidateScores = new Map<string, number>();

      for (const [seedId, w] of seeds) {
        const seed = seedDocs.find((x) => x.id === seedId);
        if (!seed) continue;

        const data = seed.data() as any;
        const similars: string[] = Array.isArray(data?.[similarField])
          ? data[similarField]
          : [];

        for (const candId of similars) {
          if (!candId) continue;
          if (candId === seedId) continue;
          if (hardExclude.has(candId)) continue;

          candidateScores.set(candId, (candidateScores.get(candId) ?? 0) + w);
        }
      }

      // 5) Fetch candidate docs (same-type)
      const sorted = Array.from(candidateScores.entries()).sort(
        (a, b) => b[1] - a[1]
      );

      const fetchIds = unique(
        sorted.slice(0, Math.min(sorted.length, limit * 3)).map(([id]) => id)
      );

      const candDocs: admin.firestore.QueryDocumentSnapshot[] = [];
      if (fetchIds.length > 0) {
        for (const part of chunk(fetchIds, 10)) {
          const q = await db
            .collection(targetCollection)
            .where(admin.firestore.FieldPath.documentId(), "in", part)
            .get();
          candDocs.push(...q.docs);
        }
      }

      const docMap = new Map<string, admin.firestore.QueryDocumentSnapshot>();
      for (const d of candDocs) docMap.set(d.id, d);

      // 6) Build output (same-type first)
      const items: ItemOut[] = [];
      const already = new Set<string>();

      for (const [id, score] of sorted) {
        if (items.length >= limit) break;
        const d = docMap.get(id);
        if (!d) continue;

        const b = d.data() as any;
        items.push({
          id: d.id,
          title: b.title,
          author: b.author,
          category: b.category,
          coverUrl: b.coverUrl ?? b.cover ?? b.imageUrl ?? "",
          description: b.description,
          score,
          type: wantedType,
        });
        already.add(d.id);
      }

      // ✅ 7) Cross-type bridge fill (STRING category + description similarity)
      const missing = limit - items.length;

      if ((missing > 0 || items.length === 0) && otherSeeds.length > 0) {
        // a) fetch other seed docs to extract categories + descriptions
        const otherSeedIds = otherSeeds.map(([id]) => id);
        const otherDocs: admin.firestore.QueryDocumentSnapshot[] = [];

        for (const part of chunk(otherSeedIds, 10)) {
          const q = await db
            .collection(otherCollection)
            .where(admin.firestore.FieldPath.documentId(), "in", part)
            .get();
          otherDocs.push(...q.docs);
        }

        // b) categories (max 10 for 'in')
        const catSet = new Set<string>();
        for (const d of otherDocs) {
          const data = d.data() as any;
          for (const c of toCategoryList(data?.category)) catSet.add(c);
          if (catSet.size >= 10) break;
        }
        const cats = Array.from(catSet).slice(0, 10);

        // c) make seed description tokens (weighted)
        const otherW = new Map<string, number>(otherSeeds);
        const seedDescTokens: Array<{ sid: string; w: number; tokens: string[] }> = [];

        for (const s of otherDocs) {
          const sid = s.id;
          const sw = otherW.get(sid) ?? 0.8;
          const desc = (s.data() as any)?.description ?? "";
          seedDescTokens.push({ sid, w: sw, tokens: tokenize(desc) });
        }

        if (cats.length > 0) {
          // ✅ category is STRING -> use "in"
          const q = await db
            .collection(targetCollection)
            .where("category", "in", cats)
            .limit(
              Math.min(
                80,
                Math.max(20, (missing > 0 ? missing : limit) * CROSS_TYPE_FILL_MULTIPLIER)
              )
            )
            .get();

          // d) score by:
          //    base = bestSeedWeight * CROSS_TYPE_SCORE_MULTIPLIER
          //    + description jaccard boost
          const crossScored: Array<{ id: string; score: number; doc: any }> = [];

          for (const d of q.docs) {
            const id = d.id;
            if (already.has(id)) continue;
            if (hardExclude.has(id)) continue;

            const b = d.data() as any;

            // category exact match already happened via query
            const candDescTok = tokenize(b?.description);

            let best = 0;

            for (const s of seedDescTokens) {
              const base = s.w * CROSS_TYPE_SCORE_MULTIPLIER;

              // description similarity 0..1
              const sim = jaccard(candDescTok, s.tokens);

              // boost: up to +60% if description is close
              const score = base * (1.0 + Math.min(0.6, sim * 1.5));

              if (score > best) best = score;
            }

            if (best <= 0) continue;
            crossScored.push({ id, score: best, doc: b });
          }

          crossScored.sort((a, b) => b.score - a.score);

          for (const c of crossScored) {
            if (items.length >= limit) break;
            items.push({
              id: c.id,
              title: c.doc?.title,
              author: c.doc?.author,
              category: c.doc?.category,
              coverUrl: c.doc?.coverUrl ?? c.doc?.cover ?? c.doc?.imageUrl ?? "",
              description: c.doc?.description,
              score: c.score,
              type: wantedType,
            });
            already.add(c.id);
          }
        }
      }

      // ✅ 8) Final fallback (better UX)
      if (items.length === 0) {
        logger.info(`Empty result. uid=${uid}, wantedType=${wantedType}`);
        if (wantedType === "book") {
          const topN = Math.min(limit, COLD_START_TOP_RATED_BOOKS);
          return { items: await coldStartBooks(topN) };
        }
        return { items: await coldStartPodcasts(limit) };
      }

      return { items };
    } catch (e: any) {
      logger.error("getPersonalizedRecommendations error", e);
      if (e?.code && e?.message) throw e;
      throw new HttpsError("internal", e?.message ?? "Unknown error");
    }
  }
);

// ===== 2) Triggers: Maintain ratingAvg/ratingSum/ratingCount per book =====
function normalizeRating(x: any): number | null {
  const n = typeof x === "number" ? x : Number(x);
  if (!Number.isFinite(n)) return null;
  const r = Math.max(1, Math.min(5, n));
  return r;
}

async function applyRatingDelta(bookId: string, deltaSum: number, deltaCount: number) {
  const bookRef = db.collection(COLLECTION_BOOKS).doc(bookId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(bookRef);
    const cur = snap.exists ? (snap.data() as any) : {};

    const sum0 = Number(cur.ratingSum ?? 0);
    const count0 = Number(cur.ratingCount ?? 0);

    const sum1 = sum0 + deltaSum;
    const count1 = Math.max(0, count0 + deltaCount);

    const avg1 = count1 > 0 ? sum1 / count1 : 0;

    tx.set(
      bookRef,
      {
        ratingSum: sum1,
        ratingCount: count1,
        ratingAvg: avg1,
        ratingUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });
}

export const onAudiobookReviewCreated = onDocumentCreated(
  { region: "us-central1", document: "audiobooks/{bookId}/reviews/{reviewId}" },
  async (event) => {
    try {
      const bookId = event.params.bookId;
      const data = event.data?.data() as any;
      const r = normalizeRating(data?.rating);
      if (r == null) return;

      await applyRatingDelta(bookId, r, 1);
    } catch (e) {
      logger.error("onAudiobookReviewCreated error", e);
    }
  }
);

export const onAudiobookReviewUpdated = onDocumentUpdated(
  { region: "us-central1", document: "audiobooks/{bookId}/reviews/{reviewId}" },
  async (event) => {
    try {
      const bookId = event.params.bookId;

      const before = event.data?.before.data() as any;
      const after = event.data?.after.data() as any;

      const rBefore = normalizeRating(before?.rating);
      const rAfter = normalizeRating(after?.rating);

      if (rBefore == null && rAfter == null) return;

      if (rBefore == null && rAfter != null) {
        await applyRatingDelta(bookId, rAfter, 1);
        return;
      }
      if (rBefore != null && rAfter == null) {
        await applyRatingDelta(bookId, -rBefore, -1);
        return;
      }
      if (rBefore != null && rAfter != null && rBefore !== rAfter) {
        await applyRatingDelta(bookId, rAfter - rBefore, 0);
      }
    } catch (e) {
      logger.error("onAudiobookReviewUpdated error", e);
    }
  }
);

export const onAudiobookReviewDeleted = onDocumentDeleted(
  { region: "us-central1", document: "audiobooks/{bookId}/reviews/{reviewId}" },
  async (event) => {
    try {
      const bookId = event.params.bookId;
      const data = event.data?.data() as any;
      const r = normalizeRating(data?.rating);
      if (r == null) return;

      await applyRatingDelta(bookId, -r, -1);
    } catch (e) {
      logger.error("onAudiobookReviewDeleted error", e);
    }
  }
);