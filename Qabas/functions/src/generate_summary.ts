import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";
import OpenAI from "openai";

if (!admin.apps.length) {
  admin.initializeApp();
}

const OPENAI_API_KEY_SUMMARY = defineSecret("OPENAI_API_KEY_SUMMARY");
const MODEL = "gpt-4.1";

// ===================== Helpers =====================
function clamp(n: number, min: number, max: number) {
  return Math.max(min, Math.min(max, n));
}

function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}

async function withRetry<T>(
  fn: () => Promise<T>,
  label: string,
  retries = 2,
  baseDelayMs = 600
): Promise<T> {
  let lastErr: any = null;
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      return await fn();
    } catch (e: any) {
      lastErr = e;
      const msg = e?.message ?? String(e);
      logger.warn(`[retry] ${label} failed (attempt ${attempt + 1}/${retries + 1}): ${msg}`);
      if (attempt < retries) {
        await sleep(baseDelayMs * (attempt + 1));
        continue;
      }
    }
  }
  throw lastErr;
}

function chooseTargetWordsByChars(textLen: number) {
  if (textLen < 3000) return { min: 120, max: 180 };
  if (textLen < 12000) return { min: 200, max: 320 };
  if (textLen < 40000) return { min: 300, max: 450 };
  return { min: 450, max: 600 };
}

/**
 * نختار chunkSize حسب حجم الكتاب لتقليل عدد الشانكات
 * - كتب صغيرة: 9k
 * - متوسطة: 12k
 * - كبيرة: 16k
 * - ضخمة: 20k
 */
function chooseChunking(textLen: number) {
  if (textLen <= 12000) return { chunkSize: 12000, overlap: 600 };
  if (textLen <= 60000) return { chunkSize: 14000, overlap: 700 };
  if (textLen <= 140000) return { chunkSize: 17000, overlap: 800 };
  return { chunkSize: 20000, overlap: 900 };
}

function chunkText(text: string, chunkSize: number, overlap: number): string[] {
  const chunks: string[] = [];
  let i = 0;

  while (i < text.length) {
    const end = Math.min(i + chunkSize, text.length);
    const chunk = text.slice(i, end).trim();
    if (chunk) chunks.push(chunk);
    if (end >= text.length) break;

    i = end - overlap;
    if (i < 0) i = 0;
  }

  return chunks;
}

function buildPartialPrompt(partIndex: number, totalParts: number) {
  return `
أنت تلخّص جزءًا من كتاب باللغة العربية.

مهم جدًا:
- لا تضف أي معلومات غير موجودة في النص.
- لا تكرر الجمل أو تعيد نفس الفكرة بصيغ كثيرة.
- ركّز على الأفكار الأساسية، الرسائل، النقاط المحورية، وأي استنتاجات مهمة.

اكتب ملخصًا جزئيًا مركزًا وواضحًا لهذا الجزء (حوالي 90–140 كلمة).
اكتب بالعربية الفصحى وبفقرات قصيرة.

(الجزء ${partIndex} من ${totalParts})
`.trim();
}

function buildMergePrompt(targetMin: number, targetMax: number, isIntermediate: boolean) {
  const minW = clamp(targetMin, 80, 600);
  const maxW = clamp(targetMax, 120, 600);

  // دمج وسيط يكون أقصر عادةً
  const iMin = clamp(Math.floor(minW * 0.55), 80, 450);
  const iMax = clamp(Math.floor(maxW * 0.65), 120, 450);

  const useMin = isIntermediate ? iMin : minW;
  const useMax = isIntermediate ? iMax : maxW;

  return `
ادمج النصوص التالية في ملخص ${isIntermediate ? "وسيـط" : "نهائي"} قوي ومتماسك للكتاب باللغة العربية الفصحى.

الشروط:
- الطول المطلوب: بين ${useMin} و ${useMax} كلمة (لا تتجاوز ${useMax} كلمة).
- الملخص واضح ومتسلسل ويغطي الأفكار الرئيسية بدون حشو.
- لا تضف معلومات غير موجودة في النص.
- لا تذكر أنك نموذج ذكاء اصطناعي ولا تذكر تعليمات.

اكتب الملخص في 2 إلى 6 فقرات قصيرة.
`.trim();
}

async function ensureAdmin(request: any) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }

  const db = admin.firestore();
  const userDoc = await db.collection("users").doc(uid).get();
  const role = (userDoc.data()?.role ?? "").toString().toLowerCase();

  if (role !== "admin") {
    throw new HttpsError("permission-denied", "Admin only.");
  }
}

async function readStorageText(path: string): Promise<string> {
  const bucket = admin.storage().bucket();
  const file = bucket.file(path);

  const [exists] = await file.exists();
  if (!exists) {
    throw new HttpsError("failed-precondition", `Missing required file: ${path}`);
  }

  const [buf] = await file.download();
  return buf.toString("utf8").trim();
}

async function writeStorageText(path: string, content: string) {
  const bucket = admin.storage().bucket();
  const file = bucket.file(path);

  await file.save(content, {
    contentType: "text/plain; charset=utf-8",
    resumable: false,
    metadata: { cacheControl: "private, max-age=0, no-transform" },
  });
}

function groupArray<T>(arr: T[], groupSize: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += groupSize) {
    out.push(arr.slice(i, i + groupSize));
  }
  return out;
}

// ===================== Main Function =====================
export const generateBookSummary = onCall(
  {
    secrets: [OPENAI_API_KEY_SUMMARY],
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (request) => {
    await ensureAdmin(request);

    const bookId = (request.data?.bookId ?? "").toString().trim();
    if (!bookId) {
      throw new HttpsError("invalid-argument", "bookId is required.");
    }

    const bookTxtPath = `audiobooks/${bookId}/book.txt`;
    const summaryPath = `audiobooks/${bookId}/summary.txt`;

    const bucket = admin.storage().bucket();
    const summaryFile = bucket.file(summaryPath);
    const [summaryExists] = await summaryFile.exists();

    if (summaryExists) {
      logger.info(`Summary already exists. Skipping generation: ${summaryPath}`);
      return {
        ok: true,
        bookId,
        summaryPath,
        alreadyExists: true,
        message: "Summary already exists. No action taken.",
      };
    }

    const fullText = await readStorageText(bookTxtPath);

    if (fullText.length < 200) {
      throw new HttpsError("failed-precondition", "book.txt content is too short to summarize.");
    }

    const target = chooseTargetWordsByChars(fullText.length);

    if (fullText.length < 1200) {
      target.min = 80;
      target.max = 140;
    }

    target.min = clamp(target.min, 80, 600);
    target.max = clamp(target.max, 120, 600);

    const apiKey = OPENAI_API_KEY_SUMMARY.value();
    const openai = new OpenAI({ apiKey });

    // ===== Chunking =====
    const { chunkSize, overlap } = chooseChunking(fullText.length);
    const chunks =
      fullText.length <= 12000 ? [fullText] : chunkText(fullText, chunkSize, overlap);

    logger.info(
      `Generating summary for bookId=${bookId}, textLen=${fullText.length}, chunkSize=${chunkSize}, overlap=${overlap}, chunks=${chunks.length}, targetWords=${target.min}-${target.max}`
    );

    // حماية إضافية: لو طلع chunks كثير جدًا، نكبر chunkSize مرة ثانية
    // (يصير نادر، لكن يفيد لو النص فيه فواصل/مسافات كثيرة)
    if (chunks.length > 28) {
      logger.warn(`Too many chunks (${chunks.length}). Re-chunking with larger size...`);
      const bigger = chunkText(fullText, Math.min(chunkSize + 6000, 26000), overlap);
      logger.info(`Re-chunked: oldChunks=${chunks.length}, newChunks=${bigger.length}`);
      chunks.splice(0, chunks.length, ...bigger);
    }

    // ===== Step 1: partial summaries =====
    const partialSummaries: string[] = [];

    for (let i = 0; i < chunks.length; i++) {
      const chunk = chunks[i];
      logger.info(`Summarizing chunk ${i + 1}/${chunks.length} (len=${chunk.length})...`);

      const resp = await withRetry(
        () =>
          openai.chat.completions.create({
            model: MODEL,
            temperature: 0.2,
            // تحديد max_tokens يسرّع ويقلل احتمالية بطء/تكلفة
            max_tokens: 420,
            messages: [
              {
                role: "system",
                content:
                  "أنت مساعد متخصص في تلخيص الكتب. تلخص بدقة وتجنب الهلوسة والحشو.",
              },
              { role: "user", content: buildPartialPrompt(i + 1, chunks.length) },
              { role: "user", content: chunk },
            ],
          }),
        `partial chunk ${i + 1}/${chunks.length}`,
        2
      );

      const text = (resp.choices?.[0]?.message?.content ?? "").trim();
      if (text) {
        partialSummaries.push(text);
      } else {
        logger.warn(`Empty partial summary for chunk ${i + 1}/${chunks.length}`);
      }
    }

    if (!partialSummaries.length) {
      throw new HttpsError("internal", "Failed to generate partial summaries.");
    }

    logger.info(`Partial summaries generated: count=${partialSummaries.length}`);

    // ===== Step 2: Hierarchical merge (دفعات) =====
    // لو الجزئيات كثيرة، ندمجها على مجموعات (مثلاً 4) عشان الدمج النهائي ما يكون ضخم
    const groupSize = partialSummaries.length <= 8 ? 0 : 4; // لو قليلة نروح للنهائي مباشرة
    let midSummaries: string[] = partialSummaries;

    if (groupSize > 0) {
      const groups = groupArray(partialSummaries, groupSize);
      logger.info(`Intermediate merge: groups=${groups.length}, groupSize=${groupSize}`);

      const inter: string[] = [];
      for (let g = 0; g < groups.length; g++) {
        const items = groups[g];
        const mergeInput = items
          .map((s, idx) => `ملخص جزئي ${g * groupSize + idx + 1}:\n${s}`)
          .join("\n\n");

        logger.info(`Merging group ${g + 1}/${groups.length} (items=${items.length})...`);

        const mergeResp = await withRetry(
          () =>
            openai.chat.completions.create({
              model: MODEL,
              temperature: 0.2,
              max_tokens: 520,
              messages: [
                {
                  role: "system",
                  content:
                    "أنت مساعد متخصص في دمج ملخصات عربية بدقة وبدون اختلاق.",
                },
                { role: "user", content: buildMergePrompt(target.min, target.max, true) },
                { role: "user", content: mergeInput },
              ],
            }),
          `intermediate merge group ${g + 1}/${groups.length}`,
          2
        );

        const merged = (mergeResp.choices?.[0]?.message?.content ?? "").trim();
        if (merged) inter.push(merged);
        else logger.warn(`Empty intermediate merge for group ${g + 1}/${groups.length}`);
      }

      if (!inter.length) {
        throw new HttpsError("internal", "Failed to generate intermediate merges.");
      }

      midSummaries = inter;
      logger.info(`Intermediate summaries ready: count=${midSummaries.length}`);
    }

    // ===== Step 3: Final merge =====
    const finalInput = midSummaries
      .map((s, idx) => `ملخص ${midSummaries.length === partialSummaries.length ? "جزئي" : "وسيـط"} ${idx + 1}:\n${s}`)
      .join("\n\n");

    logger.info(
      `Final merge starting... inputs=${midSummaries.length}, totalInputChars=${finalInput.length}`
    );

    const finalResp = await withRetry(
      () =>
        openai.chat.completions.create({
          model: MODEL,
          temperature: 0.2,
          max_tokens: 900,
          messages: [
            {
              role: "system",
              content:
                "أنت مساعد متخصص في إنتاج ملخص نهائي عالي الجودة من ملخصات جزئية/وسيطة، بدقة وبدون اختلاق.",
            },
            { role: "user", content: buildMergePrompt(target.min, target.max, false) },
            { role: "user", content: finalInput },
          ],
        }),
      "final merge",
      2
    );

    let finalSummary = (finalResp.choices?.[0]?.message?.content ?? "").trim();
    if (!finalSummary) {
      throw new HttpsError("internal", "Failed to generate final summary.");
    }

    finalSummary = finalSummary.replace(/\n{3,}/g, "\n\n").trim();

    await writeStorageText(summaryPath, finalSummary);

    logger.info(
      `Summary saved: bookId=${bookId}, path=${summaryPath}, chunks=${chunks.length}, partials=${partialSummaries.length}, mids=${midSummaries.length}`
    );

    return {
      ok: true,
      bookId,
      summaryPath,
      alreadyExists: false,
      message: "Summary generated successfully.",
      targetWords: `${target.min}-${target.max}`,
      chunks: chunks.length,
      partials: partialSummaries.length,
      intermediates: midSummaries.length,
      chunking: { chunkSize, overlap },
    };
  }
);
