import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";
import OpenAI from "openai";
import * as os from "os";
import * as path from "path";
import * as fs from "fs";

if (!admin.apps.length) {
  admin.initializeApp();
}

const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");
const MODEL = "gpt-4.1";

function getOpenAI(): OpenAI {
  const key = OPENAI_API_KEY.value();
  if (!key) throw new HttpsError("failed-precondition", "Missing OpenAI API key secret.");
  return new OpenAI({ apiKey: key });
}

function norm(s: string): string {
  return (s || "")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function isGreeting(msg: string): boolean {
  const m = norm(msg);
  const greetings = ["اهلا", "أهلا", "هلا", "هلا والله", "السلام عليكم", "سلام عليكم", "مرحبا", "هاي", "hello", "hi"];
  return greetings.some((g) => m.includes(norm(g)));
}

function isThanks(msg: string): boolean {
  const m = norm(msg);
  const thanks = ["شكرا", "شكرًا", "شكراً", "يعطيك العافيه", "يعطيك العافية", "مشكور", "مشكوره", "thx", "thanks", "thank you"];
  return thanks.some((t) => m.includes(norm(t)));
}

function extractMeaningTerm(message: string): string | null {
  const m = message.trim();
  const patterns: RegExp[] = [
    /ما\s*معنى\s*(.+)\s*\??$/i,
    /وش\s*معنى\s*(.+)\s*\??$/i,
    /يعني\s*ايش\s*(.+)\s*\??$/i,
    /what\s*does\s*(.+)\s*mean\??$/i,
  ];

  for (const p of patterns) {
    const match = m.match(p);
    if (match && match[1]) {
      let term = match[1].trim();
      term = term.replace(/^["'“”]+|["'“”]+$/g, "").trim();
      term = term.replace(/\s+/g, " ");
      if (term.length > 0 && term.length <= 80) return term;
    }
  }
  return null;
}

async function ensureBookExists(bookId: string) {
  const ref = admin.firestore().collection("audiobooks").doc(bookId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Book not found.");
  return { ref, data: (snap.data() || {}) as Record<string, any> };
}

async function downloadBookTxt(bookId: string): Promise<string> {
  const bucket = admin.storage().bucket();
  const filePath = `audiobooks/${bookId}/book.txt`;
  const tmpPath = path.join(os.tmpdir(), `${bookId}-book.txt`);
  try {
    await bucket.file(filePath).download({ destination: tmpPath });
    return tmpPath;
  } catch {
    throw new HttpsError(
      "failed-precondition",
      "book.txt is missing for this book. Please run OCR first and ensure book.txt exists in Storage."
    );
  }
}

async function pollVectorStoreReady(openai: OpenAI, vectorStoreId: string, timeoutMs = 180000) {
  const start = Date.now();
  while (true) {
    const vs = await openai.vectorStores.retrieve(vectorStoreId);
    if ((vs as any).status === "completed") return;
    if (Date.now() - start > timeoutMs) {
      throw new HttpsError("deadline-exceeded", "Vector store indexing timed out.");
    }
    await new Promise((r) => setTimeout(r, 2000));
  }
}

function safeJsonParse(s: string): any | null {
  try {
    return JSON.parse(s);
  } catch {
    return null;
  }
}

function normalizeQuotes(quotes: any): string[] {
  if (!Array.isArray(quotes)) return [];
  return quotes
    .map((q) => String(q ?? "").replace(/\s+/g, " ").trim())
    .filter((q) => q.length > 0)
    .slice(0, 3);
}

export const prepareBookChat = onCall(
  { secrets: [OPENAI_API_KEY], timeoutSeconds: 300, region: "us-central1" },
  async (req) => {
    logger.info("prepareBookChat started");

    const openai = getOpenAI();
    const bookId = String(req.data?.bookId || "").trim();
    if (!bookId) throw new HttpsError("invalid-argument", "bookId is required.");

    const { ref, data } = await ensureBookExists(bookId);
    const existing = String(data.openaiVectorStoreId || "").trim();
    if (existing) return { ok: true, vectorStoreId: existing, alreadyPrepared: true };

    const tmpTxtPath = await downloadBookTxt(bookId);

    try {
      const uploaded = await openai.files.create({
        file: fs.createReadStream(tmpTxtPath),
        purpose: "assistants",
      });

      const vs = await openai.vectorStores.create({
        name: `qabas-book-${bookId}`,
        metadata: { bookId },
      });

      await openai.vectorStores.files.create(vs.id, { file_id: uploaded.id });
      await pollVectorStoreReady(openai, vs.id);

      await ref.set(
        {
          openaiVectorStoreId: vs.id,
          openaiFileId: uploaded.id,
          openaiPreparedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      return { ok: true, vectorStoreId: vs.id, alreadyPrepared: false };
    } catch (e: any) {
      const msg = String(e?.message || e || "Unknown error");
      throw new HttpsError("internal", `prepareBookChat failed: ${msg}`);
    } finally {
      try {
        fs.unlinkSync(tmpTxtPath);
      } catch {}
    }
  }
);

export const askBookChat = onCall(
  { secrets: [OPENAI_API_KEY], timeoutSeconds: 120, region: "us-central1" },
  async (req) => {
    const openai = getOpenAI();

    const bookId = String(req.data?.bookId || "").trim();
    const message = String(req.data?.message || "").trim();

    if (!bookId) throw new HttpsError("invalid-argument", "bookId is required.");
    if (!message) throw new HttpsError("invalid-argument", "message is required.");

    if (isGreeting(message)) return { answer: "اهلا بك. اسأل عن هذا الكتاب وساجيب حسب النص.", quotes: [] };
    if (isThanks(message)) return { answer: "العفو. اذا عندك سؤال عن هذا الكتاب ارسله.", quotes: [] };

    const { data } = await ensureBookExists(bookId);
    const vectorStoreId = String(data.openaiVectorStoreId || "").trim();
    if (!vectorStoreId) {
      throw new HttpsError("failed-precondition", "Vector store is not prepared. Call prepareBookChat first.");
    }

    // History from client: only the current in-page chat (not older sessions).
    const historyRaw = Array.isArray(req.data?.history) ? req.data.history : [];
    const history = historyRaw
      .map((x: any) => ({
        role: x?.role === "assistant" ? "assistant" : "user",
        content: String(x?.text || "").trim(),
      }))
      .filter((x: any) => x.content.length > 0)
      .slice(-8);

    const term = extractMeaningTerm(message);

    // System prompt that forces structured output (answer + quotes).
    // This is the most reliable way to always get quotes like your old version.
    const systemBookOnly = [
      "You are Qabas Book Assistant.",
      "You must answer in Arabic.",
      "Do not use emojis.",
      "Do not use feminine addressing.",
      "Use the provided file_search tool to search the book content.",
      "If the user asks to shorten or make the answer more concise, shorten your previous answer directly without asking clarification.",
      "If the answer cannot be supported by the book, reply with this JSON exactly: {\"answer\":\"غير مذكور في هذا الكتاب.\",\"quotes\":[]}",
      "Return JSON ONLY with this shape: {\"answer\":\"...\",\"quotes\":[\"...\",\"...\",\"...\"]}.",
      "Quotes must be short exact excerpts from the retrieved book text (max 20 words each).",
      "At most 3 quotes.",
    ].join("\n");

    // Meaning mode: quotes usually not needed; still return JSON for consistency.
    const systemMeaningHybrid = [
      "You are Qabas Book Assistant.",
      "You must answer in Arabic.",
      "Do not use emojis.",
      "Do not use feminine addressing.",
      "First, use file_search to see if the book defines or explains the term.",
      "If the book defines it, answer using the book's definition.",
      "If the book does not define it, provide a short general dictionary-style meaning in Arabic.",
      "If you provide a general meaning, start the answer with exactly: معنى عام:",
      "Return JSON ONLY with this shape: {\"answer\":\"...\",\"quotes\":[]}.",
    ].join("\n");

    const system = term ? systemMeaningHybrid : systemBookOnly;

    try {
      const response = await openai.responses.create({
        model: MODEL,
        input: [
          { role: "system", content: system },
          ...history,
          { role: "user", content: message },
        ],
        tools: [
          {
            type: "file_search",
            vector_store_ids: [vectorStoreId],
            max_num_results: 6,
          },
        ],
      });

      const rawText = String((response as any).output_text ?? "").trim();

      // Parse the JSON that the model returns.
      const parsed = safeJsonParse(rawText);

      if (!parsed || typeof parsed !== "object") {
        logger.warn("askBookChat: model did not return valid JSON", {
          rawTextPreview: rawText.slice(0, 300),
        });

        // Fallback: return plain text as answer, no quotes.
        const fallbackAnswer = rawText.length ? rawText : "غير مذكور في هذا الكتاب.";
        return { answer: fallbackAnswer, quotes: [] };
      }

      const answer = String(parsed.answer ?? "").trim() || "غير مذكور في هذا الكتاب.";
      const quotes = normalizeQuotes(parsed.quotes);

      logger.info("askBookChat: parsed output", { quotesCount: quotes.length });

      return { answer, quotes };
    } catch (e: any) {
      const msg = String(e?.message || e || "Unknown error");
      throw new HttpsError("internal", `askBookChat failed: ${msg}`);
    }
  }
);
