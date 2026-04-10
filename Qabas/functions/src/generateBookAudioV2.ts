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

function splitTextIntoChunks(text: string, maxLength = 3000): string[] {
  const clean = text.replace(/\s+/g, " ").trim();
  if (!clean) return [];

  const chunks: string[] = [];
  let start = 0;

  while (start < clean.length) {
    let end = Math.min(start + maxLength, clean.length);

    if (end < clean.length) {
      const lastSpace = clean.lastIndexOf(" ", end);
      if (lastSpace > start + 500) {
        end = lastSpace;
      }
    }

    const chunk = clean.slice(start, end).trim();
    if (chunk) chunks.push(chunk);

    start = end;
  }

  return chunks;
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
      const textParts = splitTextIntoChunks(rawText, 3000);

      if (!textParts.length) {
        throw new HttpsError(
          "failed-precondition",
          "book.txt is empty after cleanup"
        );
      }

      const token = TTS_API_TOKEN.value();
      if (!token) {
        throw new HttpsError("failed-precondition", "Missing TTS_API_TOKEN");
      }

      logger.info("Sending chunked requests to TTS API", {
        partsCount: textParts.length,
        voiceId,
        endpoint: "http://8.213.24.61:1205/v1/tts",
      });

      const audioUrls: string[] = [];

      for (let i = 0; i < textParts.length; i++) {
        const text = textParts[i];
        const wavPath = path.join("/tmp", `${bookId}_part_${i}.wav`);
        const destPath = `audiobooks/${bookId}/audio/part_${i}.wav`;

        logger.info("Sending request to TTS API for part", {
          partIndex: i,
          totalParts: textParts.length,
          textLength: text.length,
          endpoint: "http://8.213.24.61:1205/v1/tts",
        });

        const res = await axios.post(
          "http://8.213.24.61:1205/v1/tts",
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
          partIndex: i,
          status: res.status,
          contentType: res.headers["content-type"] || null,
          bytes: res.data ? Buffer.byteLength(res.data) : 0,
        });

        if (res.status < 200 || res.status >= 300) {
          const preview = Buffer.from(res.data).toString("utf8").slice(0, 2000);

          await bookRef.set(
            {
              audioStatus: "failed",
              audioError: `TTS failed at part ${i}: status=${res.status} body=${preview}`,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );

          throw new HttpsError(
            "internal",
            `TTS failed at part ${i}: status=${res.status} body=${preview}`
          );
        }

        fs.writeFileSync(wavPath, Buffer.from(res.data));

        const stats = fs.statSync(wavPath);
        logger.info("Saved WAV locally", {
          partIndex: i,
          wavPath,
          size: stats.size,
        });

        if (!stats.size || stats.size === 0) {
          await bookRef.set(
            {
              audioStatus: "failed",
              audioError: `Generated WAV file is empty at part ${i}`,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );

          throw new HttpsError(
            "internal",
            `Generated WAV file is empty at part ${i}`
          );
        }

        await bucket.upload(wavPath, {
          destination: destPath,
          contentType: "audio/wav",
        });

        const url = await uploadWithToken(bucket, destPath);
        audioUrls.push(url);

        safeDelete(wavPath);
      }

      await bookRef.set(
        {
          audioParts: audioUrls,
          audioUrl: audioUrls[0] || null,
          audioStatus: "completed",
          voiceId: voiceId,
          audioFormat: "wav",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      return {
        success: true,
        audioUrl: audioUrls[0] || null,
        audioParts: audioUrls,
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
    }
  }
);