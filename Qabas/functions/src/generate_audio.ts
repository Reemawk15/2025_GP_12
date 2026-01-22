// generate_audio.ts
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import axios from "axios";
import * as fs from "fs";
import * as path from "path";
import { defineSecret } from "firebase-functions/params";
import { v4 as uuidv4 } from "uuid";
import type { Bucket } from "@google-cloud/storage";

const ELEVENLABS_API_KEY = defineSecret("ELEVENLABS_API_KEY");
const ELEVENLABS_VOICE_ID = defineSecret("ELEVENLABS_VOICE_ID");

if (!admin.apps.length) {
  admin.initializeApp();
}

// ===================== CONFIG =====================
const MAX_CHARS_PER_CHUNK = 3500;
const MIN_CHARS_PER_CHUNK = 1200;
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

  const segments: string[] = [];
  for (const p of paras) {
    if (p.length <= MAX_CHARS_PER_CHUNK) {
      segments.push(p);
      continue;
    }

    const parts = p
      .split(/(?<=[\.\!\؟\؛\…])\s+/)
      .map((s) => s.trim())
      .filter(Boolean);

    if (!parts.length) {
      for (let i = 0; i < p.length; i += MAX_CHARS_PER_CHUNK) {
        segments.push(p.slice(i, i + MAX_CHARS_PER_CHUNK).trim());
      }
      continue;
    }

    let buf = "";
    for (const s of parts) {
      if (!buf) buf = s;
      else if (buf.length + 1 + s.length <= MAX_CHARS_PER_CHUNK) buf = buf + " " + s;
      else {
        segments.push(buf.trim());
        buf = s;
      }
    }
    if (buf.trim()) segments.push(buf.trim());
  }

  const chunks: string[] = [];
  let current = "";

  const pushCurrent = () => {
    const c = current.trim();
    if (c) chunks.push(c);
    current = "";
  };

  for (const seg of segments) {
    if (!current) {
      current = seg;
      continue;
    }
    if (current.length + 2 + seg.length <= MAX_CHARS_PER_CHUNK) current = current + "\n\n" + seg;
    else {
      pushCurrent();
      current = seg;
    }
  }
  pushCurrent();

  if (chunks.length >= 2) {
    const last = chunks[chunks.length - 1];
    if (last.length < MIN_CHARS_PER_CHUNK) {
      const prev = chunks[chunks.length - 2];
      if (prev.length + 2 + last.length <= MAX_CHARS_PER_CHUNK) {
        chunks.splice(chunks.length - 2, 2, (prev + "\n\n" + last).trim());
      }
    }
  }

  return chunks;
}

function pad3(n: number): string {
  return String(n).padStart(3, "0");
}

async function writeDownloadTokenAndGetUrl(bucket: Bucket, destPath: string): Promise<string> {
  const token = uuidv4();

  await bucket.file(destPath).setMetadata({
    cacheControl: "no-cache",
    metadata: {
      firebaseStorageDownloadTokens: token,
    },
  });

  return (
    `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/` +
    `${encodeURIComponent(destPath)}?alt=media&token=${token}`
  );
}

function safeTmpDelete(p: string) {
  try {
    if (fs.existsSync(p)) fs.unlinkSync(p);
  } catch (_) {}
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
    // 🔐 لازم مستخدم مسجل
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login required");
    }

    const bookId = request.data?.bookId;
    if (!bookId || typeof bookId !== "string") {
      throw new HttpsError("invalid-argument", "bookId required");
    }

    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const bookRef = db.collection("audiobooks").doc(bookId);

    // ✅ لو جاهز مسبقًا لا تعيد توليد
    const existing = await bookRef.get();
    if (existing.exists) {
      const d = existing.data() || {};
      const status = d.audioStatus;
      const parts = d.audioParts;

      if (status === "completed" && Array.isArray(parts) && parts.length) {
        return { success: true, audioParts: parts };
      }
      if (status === "processing") {
        return { success: true, audioStatus: "processing" };
      }
    }

    // 📄 اقرأ book.txt
    const textFile = bucket.file(`audiobooks/${bookId}/book.txt`);
    const [exists] = await textFile.exists();
    if (!exists) {
      throw new HttpsError("not-found", "book.txt not found");
    }

    const tempTextPath = path.join("/tmp", `${bookId}.txt`);
    await textFile.download({ destination: tempTextPath });

    const bookText = fs.readFileSync(tempTextPath, "utf8");
    const chunks = chunkArabicText(bookText);

    if (!chunks.length) {
      safeTmpDelete(tempTextPath);
      throw new HttpsError("failed-precondition", "Empty book text after cleaning");
    }

    // 🟡 الحالة: processing + تصفير audioParts
    await bookRef.set(
      {
        audioStatus: "processing",
        audioParts: [],
        audioMeta: {
          totalParts: chunks.length,
          doneParts: 0,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      },
      { merge: true }
    );

    const apiKey = ELEVENLABS_API_KEY.value();
    const voiceId = ELEVENLABS_VOICE_ID.value();

    if (!apiKey || !voiceId) {
      safeTmpDelete(tempTextPath);
      await bookRef.set({ audioStatus: "failed" }, { merge: true });
      throw new HttpsError("failed-precondition", "Missing ElevenLabs secrets");
    }

    const audioParts: string[] = [];
    const tmpMp3Files: string[] = [];

    try {
      for (let i = 0; i < chunks.length; i++) {
        const partNumber = i + 1;
        const partText = chunks[i];

        const response = await axios.post(
          `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
          { text: partText, model_id: ELEVEN_MODEL_ID },
          {
            responseType: "arraybuffer",
            headers: {
              "xi-api-key": apiKey,
              "Content-Type": "application/json",
              Accept: "audio/mpeg",
            },
            timeout: 240000,
          }
        );

        const tmpMp3 = path.join("/tmp", `${bookId}-part-${pad3(partNumber)}.mp3`);
        fs.writeFileSync(tmpMp3, response.data);
        tmpMp3Files.push(tmpMp3);

        const destPath = `audiobooks/${bookId}/audio/part-${pad3(partNumber)}.mp3`;
        await bucket.upload(tmpMp3, {
          destination: destPath,
          contentType: "audio/mpeg",
          metadata: { cacheControl: "no-cache" },
        });

        const url = await writeDownloadTokenAndGetUrl(bucket as unknown as Bucket, destPath);
        audioParts.push(url);

        await bookRef.set(
          {
            audioStatus: "processing",
            audioParts,
            audioMeta: {
              totalParts: chunks.length,
              doneParts: audioParts.length,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
          },
          { merge: true }
        );

        safeTmpDelete(tmpMp3);
      }

      await bookRef.set(
        {
          audioStatus: "completed",
          audioParts,
          audioMeta: {
            totalParts: chunks.length,
            doneParts: audioParts.length,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );

      return { success: true, audioParts };
    } catch (err: any) {
      await bookRef.set(
        {
          audioStatus: "failed",
          audioMeta: {
            totalParts: chunks.length,
            doneParts: audioParts.length,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );

      // ✅ ElevenLabs sometimes returns error as arraybuffer
      const raw = err?.response?.data;
      const details =
        Buffer.isBuffer(raw) ? raw.toString("utf8") : (raw ? String(raw) : (err?.message || "Audio generation failed"));

      throw new HttpsError("internal", `Audio generation failed: ${details}`);
    } finally {
      safeTmpDelete(tempTextPath);
      for (const f of tmpMp3Files) safeTmpDelete(f);
    }
  }
);