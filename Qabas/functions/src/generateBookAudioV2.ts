import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import axios from "axios";
import * as fs from "fs";
import * as path from "path";
import { defineSecret } from "firebase-functions/params";
import { v4 as uuidv4 } from "uuid";

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
  },
  async (request) => {
    logger.info("generateBookAudioV2 HIT", {
      hasAuth: !!request.auth,
      data: request.data,
    });

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
      throw new HttpsError("not-found", `book.txt not found at ${txtPath}`);
    }

    const tmpTxt = path.join("/tmp", `${bookId}.txt`);
    const wavPath = path.join("/tmp", `${bookId}.wav`);
    const destPath = `audiobooks/${bookId}/audio/full.wav`;

    try {
      await bookRef.set(
        {
          audioStatus: "processing",
          voiceId: voiceId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      await textFile.download({ destination: tmpTxt });

      const rawText = fs.readFileSync(tmpTxt, "utf8");
      const text = rawText.replace(/\s+/g, " ").trim().slice(0, 500);

      if (!text) {
        throw new HttpsError(
          "failed-precondition",
          "book.txt is empty after cleanup"
        );
      }

      const token = TTS_API_TOKEN.value();
      if (!token) {
        throw new HttpsError("failed-precondition", "Missing TTS_API_TOKEN");
      }

      logger.info("Sending request to TTS API", {
        textLength: text.length,
        voiceId,
        endpoint: "http://188.248.250.168:1205/v1/tts",
      });

      const res = await axios.post(
        "http://188.248.250.168:1205/v1/tts",
        {
          text,
          chunk_length: 200,
          format: "wav",
          references: [],
          reference_id: voiceId,
          seed: null,
          use_memory_cache: "off",
          normalize: true,
          streaming: false,
          max_new_tokens: 1024,
          top_p: 0.8,
          repetition_penalty: 1.1,
          temperature: 0.8,
        },
        {
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          responseType: "arraybuffer",
          timeout: 300000,
          maxBodyLength: Infinity,
          maxContentLength: Infinity,
          validateStatus: () => true,
        }
      );

      logger.info("TTS API response", {
        status: res.status,
        contentType: res.headers["content-type"] || null,
        bytes: res.data ? Buffer.byteLength(res.data) : 0,
      });

      if (res.status < 200 || res.status >= 300) {
        const preview = Buffer.from(res.data).toString("utf8").slice(0, 2000);

        await bookRef.set(
          {
            audioStatus: "failed",
            audioError: `TTS failed: status=${res.status} body=${preview}`,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        throw new HttpsError(
          "internal",
          `TTS failed: status=${res.status} body=${preview}`
        );
      }

      fs.writeFileSync(wavPath, Buffer.from(res.data));

      const stats = fs.statSync(wavPath);
      logger.info("Saved WAV locally", {
        wavPath,
        size: stats.size,
      });

      if (!stats.size || stats.size === 0) {
        await bookRef.set(
          {
            audioStatus: "failed",
            audioError: "Generated WAV file is empty",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        throw new HttpsError("internal", "Generated WAV file is empty");
      }

      await bucket.upload(wavPath, {
        destination: destPath,
        contentType: "audio/wav",
      });

      const url = await uploadWithToken(bucket, destPath);

      await bookRef.set(
        {
          audioUrl: url,
          audioParts: [url],
          audioStatus: "completed",
          voiceId: voiceId,
          audioFormat: "wav",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      return {
        success: true,
        audioUrl: url,
        audioParts: [url],
        format: "wav",
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

      logger.error("generateBookAudioV2 FAILED", {
        message: err?.message ?? null,
        code: err?.code ?? null,
        status: err?.response?.status ?? null,
        statusText: err?.response?.statusText ?? null,
        responsePreview,
        stack: err?.stack ?? null,
      });

      if (err instanceof HttpsError) {
        await bookRef.set(
          {
            audioStatus: "failed",
            audioError: err.message || "HttpsError",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        throw err;
      }

      const finalError =
        `message=${err?.message ?? "unknown"} | ` +
        `code=${err?.code ?? "none"} | ` +
        `status=${err?.response?.status ?? "none"} | ` +
        `statusText=${err?.response?.statusText ?? "none"} | ` +
        `body=${responsePreview ?? "no body"}`;

      await bookRef.set(
        {
          audioStatus: "failed",
          audioError: finalError,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      throw new HttpsError("internal", finalError);
    } finally {
      safeDelete(tmpTxt);
      safeDelete(wavPath);
    }
  }
);