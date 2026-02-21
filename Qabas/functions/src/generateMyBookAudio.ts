import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import axios from "axios";
import * as fs from "fs";
import * as path from "path";
import { defineSecret } from "firebase-functions/params";
import { v4 as uuidv4 } from "uuid";
import ffmpeg from "fluent-ffmpeg";
import ffmpegPath from "ffmpeg-static";
import * as pdfParseModule from "pdf-parse";

try {
  if (ffmpegPath) ffmpeg.setFfmpegPath(ffmpegPath as string);
  else logger.warn("ffmpeg-static returned null. Audio merge may fail at runtime.");
} catch (e) {
  logger.error("Failed to set ffmpeg path", e);
}

const ELEVENLABS_API_KEY = defineSecret("ELEVENLABS_API_KEY");
const ELEVENLABS_VOICE_ID = defineSecret("ELEVENLABS_VOICE_ID");

if (!admin.apps.length) admin.initializeApp();

// ===================== CONFIG =====================
const MAX_CHARS_PER_CHUNK = 3500;
const ELEVEN_MODEL_ID = "eleven_multilingual_v2";
// ==================================================

function normalizeText(t: string): string {
  return (t || "")
    .replace(/\r/g, "")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function chunkArabicText(text: string): string[] {
  const cleaned = normalizeText(text);
  if (!cleaned) return [];

  const paras = cleaned
    .split(/\n{2,}/)
    .map((p) => p.trim())
    .filter(Boolean);

  const chunks: string[] = [];
  for (const p of paras) {
    if (p.length <= MAX_CHARS_PER_CHUNK) chunks.push(p);
    else {
      for (let i = 0; i < p.length; i += MAX_CHARS_PER_CHUNK) {
        chunks.push(p.slice(i, i + MAX_CHARS_PER_CHUNK));
      }
    }
  }
  return chunks;
}

function safeDelete(p: string) {
  try {
    if (fs.existsSync(p)) fs.unlinkSync(p);
  } catch {}
}

async function uploadWithToken(bucket: any, destPath: string): Promise<string> {
  const token = uuidv4();
  await bucket.file(destPath).setMetadata({
    metadata: { firebaseStorageDownloadTokens: token },
    cacheControl: "no-cache",
  });

  return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(
    destPath
  )}?alt=media&token=${token}`;
}

function mergeMp3s(inputs: string[], output: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const cmd = ffmpeg();
    inputs.forEach((f) => cmd.input(f));
    cmd
      .on("end", () => resolve())
      .on("error", (err) => reject(err))
      .mergeToFile(output, "/tmp");
  });
}

function getMp3DurationMs(filePath: string): Promise<number> {
  return new Promise((resolve, reject) => {
    ffmpeg.ffprobe(filePath, (err, metadata) => {
      if (err) return reject(err);
      const seconds = (metadata?.format?.duration ?? 0) as number;
      resolve(Math.round(seconds * 1000));
    });
  });
}

// pdf-parse getter
function getPdfParseFn(): (buf: Buffer) => Promise<{ text?: string }> {
  const anyMod = pdfParseModule as any;
  const fn = anyMod?.default ?? anyMod;
  return fn as (buf: Buffer) => Promise<{ text?: string }>;
}

// ✅ يجيب النص: يفضّل book.txt ثم fallback للـ PDF
async function loadBookTextFromStorage(bucket: any, uid: string, bookId: string): Promise<{ text: string; source: string }> {
  const txtPath = `users/${uid}/mybooks/${bookId}/book.txt`;
  const pdfPath = `users/${uid}/mybooks/${bookId}/book.pdf`;

  const txtFile = bucket.file(txtPath);
  const [txtExists] = await txtFile.exists();
  if (txtExists) {
    const tmpTxt = path.join("/tmp", `${uid}-${bookId}.txt`);
    await txtFile.download({ destination: tmpTxt });
    const text = fs.readFileSync(tmpTxt, "utf8");
    safeDelete(tmpTxt);
    return { text, source: "book.txt" };
  }

  const pdfFile = bucket.file(pdfPath);
  const [pdfExists] = await pdfFile.exists();
  if (!pdfExists) throw new HttpsError("not-found", "book.txt and book.pdf not found");

  const tmpPdf = path.join("/tmp", `${uid}-${bookId}.pdf`);
  await pdfFile.download({ destination: tmpPdf });

  try {
    const buf = fs.readFileSync(tmpPdf);
    const pdfParse = getPdfParseFn();
    const parsed = await pdfParse(buf);
    const text = parsed?.text || "";
    safeDelete(tmpPdf);
    return { text, source: "pdf-parse" };
  } catch (e) {
    safeDelete(tmpPdf);
    throw new HttpsError("internal", "PDF parsing failed");
  }
}

export const generateMyBookAudio = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "1GiB",
    secrets: [ELEVENLABS_API_KEY, ELEVENLABS_VOICE_ID],
    enforceAppCheck: false,

    // ✅✅ هذا اللي يحل 401 (IAM)
    invoker: "public",
  },
  async (request) => {
    logger.info("generateMyBookAudio HIT", {
      hasAuth: !!request.auth,
      uidFromAuth: request.auth?.uid ?? null,
      uidFromData: request.data?.uid ?? null,
    });

    const uid = (request.data?.uid || "").toString().trim();
    const bookId = (request.data?.bookId || "").toString().trim();

    if (!uid) throw new HttpsError("invalid-argument", "uid required");
    if (!bookId) throw new HttpsError("invalid-argument", "bookId required");

    const db = admin.firestore();
    const bucket = admin.storage().bucket();

    const myBookRef = db.collection("users").doc(uid).collection("mybooks").doc(bookId);
    const snap = await myBookRef.get();
    if (!snap.exists) throw new HttpsError("not-found", "MyBook not found");

    const existing = snap.data() || {};

    if (existing?.audioStatus === "completed" && existing?.audioUrl) {
      return { success: true, audioUrl: existing.audioUrl };
    }

    await myBookRef.set(
      { audioStatus: "processing", updatedAt: admin.firestore.FieldValue.serverTimestamp(), errorMessage: admin.firestore.FieldValue.delete() },
      { merge: true }
    );

    // ✅ load text (txt preferred)
    let text = "";
    let source = "";
    try {
      const loaded = await loadBookTextFromStorage(bucket, uid, bookId);
      text = loaded.text;
      source = loaded.source;
    } catch (e: any) {
      logger.error("Text load failed", e);
      await myBookRef.set({ audioStatus: "failed", errorMessage: e?.message ?? "Text load failed" }, { merge: true });
      throw e;
    }

    const chunks = chunkArabicText(text);
    if (!chunks.length) {
      await myBookRef.set({ audioStatus: "failed", errorMessage: "Empty text" }, { merge: true });
      throw new HttpsError("failed-precondition", "Empty text extracted");
    }

    const apiKey = ELEVENLABS_API_KEY.value();
    const voiceId = ELEVENLABS_VOICE_ID.value();
    if (!apiKey || !voiceId) {
      await myBookRef.set({ audioStatus: "failed", errorMessage: "Missing ElevenLabs secrets" }, { merge: true });
      throw new HttpsError("failed-precondition", "Missing ElevenLabs secrets");
    }

    const mp3Parts: string[] = [];
    let finalMp3 = "";

    try {
      for (let i = 0; i < chunks.length; i++) {
        // (اختياري) تقدّم
        if (i % 3 === 0) {
          await myBookRef.set({ audioProgress: { current: i, total: chunks.length } }, { merge: true });
        }

        const res = await axios.post(
          `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
          {
            text: chunks[i],
            model_id: ELEVEN_MODEL_ID,
            voice_settings: { stability: 0.45, similarity_boost: 0.75 },
          },
          {
            headers: {
              "xi-api-key": apiKey,
              "Content-Type": "application/json",
              Accept: "audio/mpeg",
            },
            responseType: "arraybuffer",
            timeout: 150000,
          }
        );

        const partPath = path.join("/tmp", `${uid}-${bookId}-part-${i}.mp3`);
        fs.writeFileSync(partPath, Buffer.from(res.data));
        mp3Parts.push(partPath);
      }

      finalMp3 = path.join("/tmp", `${uid}-${bookId}-full.mp3`);
      await mergeMp3s(mp3Parts, finalMp3);

      const totalMs = await getMp3DurationMs(finalMp3);

      const destPath = `users/${uid}/mybooks/${bookId}/audio/full.mp3`;
      await bucket.upload(finalMp3, { destination: destPath, contentType: "audio/mpeg" });

      const url = await uploadWithToken(bucket, destPath);

      await myBookRef.set(
        {
          audioStatus: "completed",
          audioUrl: url,
          audioTotalMs: totalMs,
          audioParts: [url],
          audioMeta: { merged: true, totalChunks: chunks.length, source },
          audioProgress: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      return { success: true, audioUrl: url };
    } catch (err: any) {
      logger.error("Audio generation failed", err);
      await myBookRef.set({ audioStatus: "failed", errorMessage: err?.message ?? "Audio generation failed" }, { merge: true });
      throw new HttpsError("internal", "Audio generation failed");
    } finally {
      mp3Parts.forEach(safeDelete);
      if (finalMp3) safeDelete(finalMp3);
    }
  }
);