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

ffmpeg.setFfmpegPath(ffmpegPath as string);

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

  const paras = cleaned.split(/\n{2,}/).map(p => p.trim()).filter(Boolean);
  const chunks: string[] = [];

  for (const p of paras) {
    if (p.length <= MAX_CHARS_PER_CHUNK) {
      chunks.push(p);
    } else {
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
    inputs.forEach(f => cmd.input(f));

    cmd
      .on("end", () => resolve())
      .on("error", err => reject(err))
      .mergeToFile(output, "/tmp");
  });
}

// ✅ جديد: حساب مدة mp3 بالمللي ثانية (ffprobe)
function getMp3DurationMs(filePath: string): Promise<number> {
  return new Promise((resolve, reject) => {
    ffmpeg.ffprobe(filePath, (err, metadata) => {
      if (err) return reject(err);
      const seconds = (metadata?.format?.duration ?? 0) as number;
      resolve(Math.round(seconds * 1000));
    });
  });
}

export const generateBookAudio = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "1GiB",
    secrets: [ELEVENLABS_API_KEY, ELEVENLABS_VOICE_ID],
    enforceAppCheck: false,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login required");
    }

    const bookId = request.data?.bookId;
    if (!bookId) {
      throw new HttpsError("invalid-argument", "bookId required");
    }

    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const bookRef = db.collection("audiobooks").doc(bookId);

    const snap = await bookRef.get();
    const existing = snap.exists ? snap.data() : {};

    // ✅ لو الملف النهائي موجود
    if (existing?.audioStatus === "completed" && existing?.audioUrl) {
      return { success: true, audioUrl: existing.audioUrl };
    }

    await bookRef.set(
      { audioStatus: "processing", updatedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );

    const textFile = bucket.file(`audiobooks/${bookId}/book.txt`);
    const [exists] = await textFile.exists();
    if (!exists) throw new HttpsError("not-found", "book.txt not found");

    const tmpText = path.join("/tmp", `${bookId}.txt`);
    await textFile.download({ destination: tmpText });

    const text = fs.readFileSync(tmpText, "utf8");
    const chunks = chunkArabicText(text);
    if (!chunks.length) throw new HttpsError("failed-precondition", "Empty text");

    const apiKey = ELEVENLABS_API_KEY.value();
    const voiceId = ELEVENLABS_VOICE_ID.value();
    if (!apiKey || !voiceId) {
      throw new HttpsError("failed-precondition", "Missing ElevenLabs secrets");
    }

    const mp3Parts: string[] = [];

    try {
      // 🎙️ توليد أجزاء
      for (let i = 0; i < chunks.length; i++) {
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

        const partPath = path.join("/tmp", `part-${i}.mp3`);
        fs.writeFileSync(partPath, Buffer.from(res.data));
        mp3Parts.push(partPath);
      }

      // 🔗 دمج إلى ملف واحد
      const finalMp3 = path.join("/tmp", `${bookId}-full.mp3`);
      await mergeMp3s(mp3Parts, finalMp3);

      // ✅ جديد: احسبي مدة الكتاب كاملة قبل الرفع
      const totalMs = await getMp3DurationMs(finalMp3);

      // ☁️ رفع ملف واحد فقط
      const destPath = `audiobooks/${bookId}/audio/full.mp3`;
      await bucket.upload(finalMp3, {
        destination: destPath,
        contentType: "audio/mpeg",
      });

      const url = await uploadWithToken(bucket, destPath);

      await bookRef.set(
        {
          audioStatus: "completed",
          audioUrl: url,

          // ✅ جديد: عشان Flutter يجيب المدة فورًا بدون انتظار
          audioTotalMs: totalMs,

          // ✅ اختياري لكن مهم إذا كود Flutter يعتمد على audioParts
          audioParts: [url],

          audioMeta: {
            merged: true,
            totalChunks: chunks.length,
          },
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      return { success: true, audioUrl: url };
    } catch (err) {
      logger.error(err);
      await bookRef.set({ audioStatus: "failed" }, { merge: true });
      throw new HttpsError("internal", "Audio generation failed");
    } finally {
      safeDelete(tmpText);
      mp3Parts.forEach(safeDelete);

      // ✅ (تنظيف إضافي بسيط) لو تبين:
      // safeDelete(path.join("/tmp", `${bookId}-full.mp3`));
    }
  }
);
