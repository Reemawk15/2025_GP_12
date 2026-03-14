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

try {
  if (ffmpegPath) {
    ffmpeg.setFfmpegPath(ffmpegPath as string);
  }
} catch {}

const TTS_API_TOKEN = defineSecret("TTS_API_TOKEN");

if (!admin.apps.length) admin.initializeApp();

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

export const generateBookAudioV2 = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "1GiB",
    secrets: [TTS_API_TOKEN],
    enforceAppCheck: false,
    invoker: "public",
  },
  async (request) => {
    logger.info("generateBookAudioV2 TEST HIT");

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login required");
    }

    const bookId = (request.data?.bookId || "").toString().trim();
    const voiceId = (request.data?.voiceId || "").toString().trim();

    if (!bookId) {
      throw new HttpsError("invalid-argument", "bookId required");
    }

    if (!voiceId) {
      throw new HttpsError("invalid-argument", "voiceId required");
    }

    const bucket = admin.storage().bucket();
    const bookRef = admin.firestore().collection("audiobooks").doc(bookId);

    const txtPath = `audiobooks/${bookId}/book.txt`;
    const textFile = bucket.file(txtPath);

    const [exists] = await textFile.exists();
    if (!exists) {
      throw new HttpsError("not-found", "book.txt not found");
    }

    const tmpTxt = path.join("/tmp", `${bookId}.txt`);
    await textFile.download({ destination: tmpTxt });

    const text = fs.readFileSync(tmpTxt, "utf8").slice(0, 150);
    const token = TTS_API_TOKEN.value();

    if (!token) {
      throw new HttpsError("failed-precondition", "Missing TTS_API_TOKEN");
    }

    const wavPath = path.join("/tmp", `${bookId}.wav`);
    const mp3Path = path.join("/tmp", `${bookId}.mp3`);
    const destPath = `audiobooks/${bookId}/audio/test.mp3`;

    try {
      logger.info("Testing TTS API", {
        textLength: text.length,
        voiceId,
      });

      const res = await axios({
        method: "POST",
        url: "http://188.248.250.168:1205/v1/tts",
        data: {
          text,
          reference_id: voiceId,
          format: "wav",
          normalize: true,
        },
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        responseType: "arraybuffer",
        timeout: 300000,
        maxBodyLength: Infinity,
        maxContentLength: Infinity,
      });

      fs.writeFileSync(wavPath, Buffer.from(res.data));

      await new Promise<void>((resolve, reject) => {
        ffmpeg(wavPath)
          .toFormat("mp3")
          .on("end", () => resolve())
          .on("error", (err) => reject(err))
          .save(mp3Path);
      });

      await bucket.upload(mp3Path, {
        destination: destPath,
        contentType: "audio/mpeg",
      });

      const url = await uploadWithToken(bucket, destPath);

      await bookRef.set(
        {
          testAudioUrl: url,
          testVoiceId: voiceId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      return {
        success: true,
        audioUrl: url,
      };
    } catch (err: any) {
      let responsePreview: string | null = null;

      try {
        const raw = err?.response?.data;
        if (Buffer.isBuffer(raw)) {
          responsePreview = raw.toString("utf8").slice(0, 2000);
        } else if (typeof raw === "string") {
          responsePreview = raw.slice(0, 2000);
        } else if (raw) {
          responsePreview = JSON.stringify(raw).slice(0, 2000);
        }
      } catch {}

      logger.error("TTS TEST FAILED", {
        message: err?.message,
        status: err?.response?.status ?? null,
        responsePreview,
      });

      throw new HttpsError(
        "internal",
        `status=${err?.response?.status ?? "unknown"} | ${responsePreview || err?.message || "TTS test failed"}`
      );
    } finally {
      safeDelete(tmpTxt);
      safeDelete(wavPath);
      safeDelete(mp3Path);
    }
  }
);