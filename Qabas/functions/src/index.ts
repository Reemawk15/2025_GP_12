import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { DocumentProcessorServiceClient } from "@google-cloud/documentai";
import * as path from "path";
import * as os from "os";
import * as fs from "fs";
import { v4 as uuidv4 } from "uuid";

admin.initializeApp();

// ===== إعدادات مشروعك =====
const PROJECT_ID   = "qabas-95e06";
const LOCATION     = "us"; // نفس منطقة المعالج
const PROCESSOR_ID = "63d2df301e9805cd";

// ملفات الـPDF تُرفع هنا (Firebase Storage)
const FIREBASE_BUCKET = "qabas-95e06.firebasestorage.app";

// مخرجات Batch OCR (GCS bucket في us)
const DOCAI_OUTPUT_BUCKET = "qabas-95e06-docai-us-1";

const docai = new DocumentProcessorServiceClient();

// المعالجة المشتركة
async function handleOcr(object: functions.storage.ObjectMetadata) {
  const filePath    = object.name || "";
  const contentType = object.contentType || "";
  const bucketName  = object.bucket || "";

  functions.logger.info("OCR trigger", { bucketName, filePath, contentType });

  // نتعامل فقط مع PDF داخل audiobooks/{bookId}
  const isPdf = (contentType === "application/pdf") || filePath.toLowerCase().endsWith(".pdf");
  if (!isPdf) {
    functions.logger.info("Skip: not a PDF", { filePath, contentType });
    return;
  }

  const m = filePath.match(/^audiobooks\/([^/]+)\/.*\.pdf$/i);
  if (!m) {
    functions.logger.info("Skip: path not under audiobooks/{bookId}", { filePath });
    return;
  }
  const bookId = m[1];

  const db = admin.firestore();
  const audioRef = db.collection("audiobooks").doc(bookId);

  // حدّث الحالة إلى processing
  await audioRef.set({ ocrStatus: "processing" }, { merge: true });

  // نزّل الـPDF مؤقتًا لمحاولة الأونلاين أولاً
  const bucket = admin.storage().bucket(bucketName);
  const tempLocalPath = path.join(os.tmpdir(), `${uuidv4()}_${path.basename(filePath)}`);
  await bucket.file(filePath).download({ destination: tempLocalPath });
  functions.logger.info("Downloaded PDF to tmp", { tempLocalPath });

  const processorName = docai.processorPath(PROJECT_ID, LOCATION, PROCESSOR_ID);

  try {
    // (1) محاولة Online OCR (حد 30 صفحة)
    const content = fs.readFileSync(tempLocalPath);
    const [result] = await docai.processDocument({
      name: processorName,
      rawDocument: { content, mimeType: "application/pdf" },
    });

    const text = result.document?.text ?? "";

    // خزّن ocr.json بجانب الـPDF في Firebase Storage
    const baseDir = path.posix.dirname(filePath); // audiobooks/{bookId}
    const ocrJsonPath = `${baseDir}/ocr.json`;
    await bucket.file(ocrJsonPath).save(JSON.stringify(result, null, 2), {
      contentType: "application/json",
    });

    await audioRef.set({
      ocrStatus: "done",
      ocrTextPreview: text.slice(0, 2000),
      ocrChars: text.length,
      ocrJsonPath,
      ocrUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    functions.logger.info("OCR done (online)", { bookId, chars: text.length, ocrJsonPath });

  } catch (err: any) {
    // فشل الأونلاين → نفحص هل بسبب حد الصفحات ونحوّل للباتش
    const code = (err?.code ?? err?.details ?? "") as number | string;
    const msg  = String(err?.message || err);
    functions.logger.error("Online OCR failed", { code, message: msg });

    const exceeds =
      Number(code) === 3 ||
      /exceed/i.test(msg) ||
      /pages?\s+exceed/i.test(msg) ||
      /limit.*30/i.test(msg);

    if (!exceeds) {
      await audioRef.set({
        ocrStatus: "error",
        ocrErrorMessage: msg,
        ocrUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      throw err;
    }

    // (2) Batch OCR للملفات الكبيرة
    try {
      const gcsInputUri  = `gs://${bucketName}/${filePath}`;
      const gcsOutputUri = `gs://${DOCAI_OUTPUT_BUCKET}/audiobooks/${bookId}/ocr/`;

      functions.logger.info("Starting Batch OCR", { gcsInputUri, gcsOutputUri });

      const [operation] = await docai.batchProcessDocuments({
        name: processorName,
        inputDocuments: {
          gcsDocuments: {
            documents: [{ gcsUri: gcsInputUri, mimeType: "application/pdf" }],
          },
        },
        documentOutputConfig: {
          gcsOutputConfig: { gcsUri: gcsOutputUri },
        },
      });

      // ننتظر انتهاء العملية
      await operation.promise();

      // حدّث Firestore بمكان النتائج
      await audioRef.set({
        ocrStatus: "done",
        ocrBatchOutputGcs: gcsOutputUri,
        ocrTextPreview: "(batch) النتائج محفوظة كملفات JSON في GCS (شاهدي ocrBatchOutputGcs).",
        ocrChars: null,
        ocrJsonPath: null,
        ocrUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      functions.logger.info("OCR done (batch)", { bookId, gcsOutputUri });

    } catch (batchErr: any) {
      const batchMsg = String(batchErr?.message || batchErr);
      functions.logger.error("Batch OCR failed", { message: batchMsg });

      await audioRef.set({
        ocrStatus: "error",
        ocrErrorMessage: batchMsg,
        ocrUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      throw batchErr;
    }
  } finally {
    try { fs.unlinkSync(tempLocalPath); } catch {}
  }
}

// ✅ تريغر واحد مربوط على باكت Firebase الصحيح
export const ocrOnPdfUpload = functions
  .region("us-central1")
  .runWith({ memory: "1GB", timeoutSeconds: 540 })
  .storage
  .bucket(FIREBASE_BUCKET)
  .object()
  .onFinalize(handleOcr);
