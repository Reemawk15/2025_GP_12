import { onObjectFinalized } from "firebase-functions/v2/storage";
import { logger } from "firebase-functions";
import { Storage } from "@google-cloud/storage";
import { DocumentProcessorServiceClient } from "@google-cloud/documentai";
import { v4 as uuidv4 } from "uuid";
import { PDFDocument } from "pdf-lib"; // Used to split large PDFs


// ================== CONFIGURATION ==================
const APP_BUCKET = "qabas-95e06.firebasestorage.app";   // Firebase Storage bucket
const DOC_OUTPUT_BUCKET = "qabas-95e06-docai-us-1";     // Document AI output bucket
const LOCATION = "us";                                  // Processor location
const PROCESSOR_ID = "63d2df301e9805cd";                // Processor ID;

// Maximum pages per part when splitting a large PDF
const MAX_PAGES_PER_PART = 100;

// Maximum number of OCR parts to process in parallel for a single book
// This keeps some parallelism (faster than pure sequential) while staying under quota limits.
const MAX_OCR_PART_CONCURRENCY = 2;

const storage = new Storage();
const docai = new DocumentProcessorServiceClient();

// ================== Path parsing for admin & user uploads ==================

type UploadContext =
  | {
      kind: "admin";
      bookId: string;
      basePrefix: string; // e.g. audiobooks/{bookId}
    }
  | {
      kind: "user";
      userId: string;
      docId: string;
      basePrefix: string; // e.g. users/{uid}/mybooks/{docId}
    };

/**
 * Determine whether the uploaded PDF belongs to:
 *  - admin audiobooks: audiobooks/{bookId}/...
 *  - user private library: users/{uid}/mybooks/{docId}/book.pdf
 * and return a unified context describing where to store OCR output.
 */
function getUploadContext(filePath: string): UploadContext | null {
  const parts = filePath.split("/");

  // Admin public audiobooks: audiobooks/{bookId}/...
  if (parts.length >= 2 && parts[0] === "audiobooks") {
    const bookId = parts[1];
    return {
      kind: "admin",
      bookId,
      basePrefix: `audiobooks/${bookId}`,
    };
  }

  // User private books: users/{uid}/mybooks/{docId}/book.pdf
  if (parts.length >= 4 && parts[0] === "users" && parts[2] === "mybooks") {
    const userId = parts[1];
    const docId = parts[3];
    return {
      kind: "user",
      userId,
      docId,
      basePrefix: `users/${userId}/mybooks/${docId}`,
    };
  }

  return null;
}

async function runBatchOCR(gcsInputUri: string, outPrefix: string) {
  const projectId = await docai.getProjectId();
  const name = `projects/${projectId}/locations/${LOCATION}/processors/${PROCESSOR_ID}`;

  const request = {
    name,
    inputDocuments: {
      gcsDocuments: {
        documents: [{ gcsUri: gcsInputUri, mimeType: "application/pdf" }],
      },
    },
    documentOutputConfig: {
      gcsOutputConfig: { gcsUri: `gs://${DOC_OUTPUT_BUCKET}/${outPrefix}` },
    },
  } as any;

  const [operation] = await docai.batchProcessDocuments(request);
  logger.info("Started Batch OCR", { gcsInputUri, outPrefix });
  await operation.promise();
  logger.info("Batch OCR completed", { outPrefix });
}

/**
 * For large PDFs, split into multiple parts stored in APP_BUCKET (under temp-split),
 * so we can run OCR on each chunk separately and then merge the text.
 * For smaller PDFs, just use the original file as-is.
 */
async function preparePdfParts(
  sourceBucketName: string,
  sourceFilePath: string
): Promise<{ inputUris: string[]; pageCount: number; tempSplitPrefix: string | null }> {
  const bucket = storage.bucket(sourceBucketName);
  const [pdfBytes] = await bucket.file(sourceFilePath).download();

  // IMPORTANT: some PDFs can be encrypted => pdf-lib might throw
  // If you ever hit encryption errors, you can switch to:
  // const pdfDoc = await PDFDocument.load(pdfBytes, { ignoreEncryption: true });
  const pdfDoc = await PDFDocument.load(pdfBytes);

  const totalPages = pdfDoc.getPageCount();

  logger.info("PDF page count detected", {
    sourceBucketName,
    sourceFilePath,
    totalPages,
  });

  // No split needed: use original file
  if (totalPages <= MAX_PAGES_PER_PART) {
    return {
      inputUris: [`gs://${sourceBucketName}/${sourceFilePath}`],
      pageCount: totalPages,
      tempSplitPrefix: null,
    };
  }

  const numParts = Math.ceil(totalPages / MAX_PAGES_PER_PART);
  const splitBase = `temp-split/${uuidv4()}`;
  const inputUris: string[] = [];

  logger.info("Splitting large PDF", {
    totalPages,
    maxPagesPerPart: MAX_PAGES_PER_PART,
    numParts,
    splitBase,
  });

  for (let partIndex = 0; partIndex < numParts; partIndex++) {
    const startPage = partIndex * MAX_PAGES_PER_PART; // inclusive (0-based)
    const endPage = Math.min(totalPages, (partIndex + 1) * MAX_PAGES_PER_PART); // exclusive

    const partDoc = await PDFDocument.create();
    const pageIndices = Array.from({ length: endPage - startPage }, (_, i) => startPage + i);

    const copiedPages = await partDoc.copyPages(pdfDoc, pageIndices);
    copiedPages.forEach((p) => partDoc.addPage(p));

    const partBytes = await partDoc.save();

    const partName = `part-${String(partIndex + 1).padStart(3, "0")}.pdf`;
    const partPath = `${splitBase}/${partName}`;

    await storage.bucket(APP_BUCKET).file(partPath).save(Buffer.from(partBytes), {
      resumable: false,
      contentType: "application/pdf",
    });

    const gcsUri = `gs://${APP_BUCKET}/${partPath}`;
    inputUris.push(gcsUri);

    logger.info("Created split PDF part", {
      partIndex: partIndex + 1,
      partPath,
      startPage,
      endPage: endPage - 1,
      gcsUri,
    });
  }

  return {
    inputUris,
    pageCount: totalPages,
    tempSplitPrefix: splitBase,
  };
}

// Helper to delete temp-split folder after OCR is done
async function deleteTempFolder(bucketName: string, prefix: string) {
  const bucket = storage.bucket(bucketName);
  const [files] = await bucket.getFiles({ prefix });

  if (!files.length) {
    logger.info("No temp-split files to delete", { prefix });
    return;
  }

  await Promise.all(files.map((f) => f.delete()));
  logger.info("Deleted temp-split files", {
    prefix,
    count: files.length,
  });
}

// ================== Helpers to extract text ==================
function sliceFromAnyAnchor(anchor: any, fullText: string): string {
  if (!anchor) return "";
  if (typeof anchor.content === "string") return anchor.content; // Rare in batch
  const segs = anchor.textSegments || anchor.segments || anchor.textSegment || [];
  if (Array.isArray(segs) && typeof fullText === "string") {
    let out = "";
    for (const s of segs) {
      const start = Number(s.startIndex ?? s.start ?? 0);
      const end = Number(s.endIndex ?? s.end ?? 0);
      if (!isNaN(start) && !isNaN(end) && end > start) {
        out += fullText.substring(start, end);
      }
    }
    return out;
  }
  return "";
}

const pickLayoutAnchor = (node: any) =>
  node?.layout?.textAnchor || node?.textAnchor || null;

const concatIf = (str: string, add: string) =>
  add && add.trim() ? (str ? str + "\n" : "") + add.trim() : str;

function extractOnePageText(page: any, fullText: string): string {
  let pageText = sliceFromAnyAnchor(pickLayoutAnchor(page), fullText);

  if (!pageText.trim() && Array.isArray(page?.paragraphs)) {
    for (const p of page.paragraphs) {
      pageText = concatIf(pageText, sliceFromAnyAnchor(pickLayoutAnchor(p), fullText));
    }
  }

  if (!pageText.trim() && Array.isArray(page?.lines)) {
    for (const l of page.lines) {
      pageText = concatIf(pageText, sliceFromAnyAnchor(pickLayoutAnchor(l), fullText));
    }
  }

  if (!pageText.trim() && Array.isArray(page?.blocks)) {
    for (const b of page.blocks) {
      pageText = concatIf(pageText, sliceFromAnyAnchor(pickLayoutAnchor(b), fullText));
    }
  }

  if (!pageText.trim() && Array.isArray(page?.tokens)) {
    const parts: string[] = [];
    for (const t of page.tokens) {
      const tok = sliceFromAnyAnchor(pickLayoutAnchor(t), fullText);
      if (tok) parts.push(tok);
    }
    if (parts.length) pageText = parts.join("");
  }

  // Final fallback: use direct layout content if available
  if (!pageText.trim()) {
    if (Array.isArray(page?.paragraphs)) {
      for (const p of page.paragraphs) {
        pageText = concatIf(pageText, (p.layout?.textAnchor?.content as string) || "");
      }
    } else if (Array.isArray(page?.lines)) {
      for (const l of page.lines) {
        pageText = concatIf(pageText, (l.layout?.textAnchor?.content as string) || "");
      }
    } else if (Array.isArray(page?.blocks)) {
      for (const b of page.blocks) {
        pageText = concatIf(pageText, (b.layout?.textAnchor?.content as string) || "");
      }
    }
  }

  return pageText.trim();
}

// ================== Post-processing: clean pages ==================

/**
 * Detect whether a line is just a page number (ASCII or Arabic-Indic digits),
 * or forms like "Page 3" / "صفحة ٣".
 */
function isPageNumberLine(line: string): boolean {
  const trimmed = line.trim();
  if (!trimmed) return false;

  const noSpaces = trimmed.replace(/\s+/g, "");

  // Only digits (ASCII + Arabic-Indic + Extended Arabic-Indic)
  if (/^[0-9\u0660-\u0669\u06F0-\u06F9]+$/.test(noSpaces)) return true;

  // Roman numerals like i, ii, iii, xiv, ...
  if (/^[ivxlcdm]+$/i.test(noSpaces)) return true;

  // "Page 3" or "صفحة ٣"
  if (/^(page|صفحة)\s*[0-9\u0660-\u0669\u06F0-\u06F9]+$/i.test(trimmed)) return true;

  return false;
}

/**
 * Detect if a single line looks like a table-of-contents entry.
 */
function isTocLikeLine(line: string): boolean {
  const trimmed = line.trim();
  if (!trimmed) return false;

  // "title ..... 15" style
  if (/\.{3,}\s*[0-9\u0660-\u0669\u06F0-\u06F9]{1,4}\s*$/.test(trimmed)) {
    return true;
  }

  // "61 السابع"
  if (/^[0-9\u0660-\u0669\u06F0-\u06F9]{1,4}\s+.+$/.test(trimmed)) {
    return true;
  }

  // "السابع 61"
  if (/^.+\s[0-9\u0660-\u0669\u06F0-\u06F9]{1,4}\s*$/.test(trimmed)) {
    return true;
  }

  return false;
}

/**
 * Short Arabic title-like line without sentence punctuation.
 * Used to detect TOC pages where only titles are listed (no page numbers).
 */
function isShortTitleLine(line: string): boolean {
  const trimmed = line.trim();
  if (!trimmed) return false;

  if (!/[\u0600-\u06FF]{3,}/.test(trimmed)) return false;
  if (trimmed.length > 40) return false;
  if (/[\.؟!؛،]/.test(trimmed)) return false;

  return true;
}

/**
 * Detect if a whole page structurally behaves like a table of contents.
 * We restrict to early pages to avoid dropping real content.
 */
function isTocStructurePage(lines: string[], pageIndex: number): boolean {
  const MAX_TOC_PAGE_INDEX = 14; // first 15 pages
  if (pageIndex > MAX_TOC_PAGE_INDEX) return false;

  const nonEmpty = lines.map((l) => l.trim()).filter(Boolean);
  if (nonEmpty.length < 5) return false;

  let tocLike = 0;
  let shortTitleLike = 0;

  for (const ln of nonEmpty) {
    if (isTocLikeLine(ln)) tocLike++;
    else if (isShortTitleLine(ln)) shortTitleLike++;
  }

  const candidateCount = tocLike + shortTitleLike;
  if (candidateCount < 5) return false;

  if (candidateCount >= nonEmpty.length * 0.6) return true;
  return false;
}

/**
 * Remove inline page numbers embedded between sentences.
 */
function removeInlinePageNumbers(text: string): string {
  text = text.replace(
    /([\.!\؟؟!])\s*[0-9\u0660-\u0669\u06F0-\u06F9]{1,3}\s+(?=[A-Za-zء-ي])/g,
    "$1 "
  );

  text = text.replace(
    /^([^\n0-9\u0660-\u0669\u06F0-\u06F9]*?)\s[0-9\u0660-\u0669\u06F0-\u06F9]{1,3}\s*$/gm,
    "$1"
  );

  return text;
}

/**
 * Detect and remove a reference/footer block at the bottom of the page.
 */
function stripReferenceFooterFromLines(lines: string[]): string[] {
  const n = lines.length;
  if (n < 4) return lines;

  // (0) Divider line near the bottom
  for (let i = Math.max(0, n - 6); i < n; i++) {
    const l = lines[i].trim();
    if (/^[\.\-\_]{5,}$/.test(l)) {
      return lines.slice(0, i);
    }
  }

  // (1) Generic mixed Arabic/Latin reference footer
  const lookback = Math.min(10, n);
  const candidateIdxs: number[] = [];
  let hasRefKeyword = false;

  for (let i = n - lookback; i < n; i++) {
    const l = lines[i].trim();
    if (!l) continue;

    const hasArabicRefWord = /المرجع|المراجع|المصادر|انظر/.test(l);
    const latinCount = (l.match(/[A-Za-z]/g) || []).length;

    if (hasArabicRefWord) {
      hasRefKeyword = true;
      candidateIdxs.push(i);
    } else if (latinCount >= 8) {
      candidateIdxs.push(i);
    }
  }

  if (hasRefKeyword && candidateIdxs.length >= 2) {
    const start = Math.min(...candidateIdxs);
    if (start >= n - 6) {
      return lines.slice(0, start);
    }
  }

  // (2) Hindawi-style Arabic-only footer
  const hindawiStartRegex = /انظر\s+أيضًا|انظر\s+ايضاً|انظر\s+ايضا/i;
  const metaRegex = /(الكتاب|سلسلة|المؤلف|تأليف|ترجمة|دار النشر|من سلسلة|الطبعة)/;

  const searchFrom = Math.max(0, n - 5);
  for (let i = searchFrom; i < n; i++) {
    const line = lines[i].trim();
    if (!line) continue;

    if (!hindawiStartRegex.test(line)) continue;
    if (i < n - 4) continue;

    let hasMeta = false;
    for (let j = i; j < n; j++) {
      const lj = lines[j].trim();
      if (!lj) continue;
      if (metaRegex.test(lj)) {
        hasMeta = true;
        break;
      }
      if (/(19|20)\d{2}/.test(lj) || /[\u0660-\u0669]{4}/.test(lj)) {
        hasMeta = true;
        break;
      }
    }

    if (hasMeta) {
      return lines.slice(0, i);
    }
  }

  return lines;
}

// ================== NEW: front-matter / publisher / contact filtering ==================

/** Arabic/Latin digits for phone detection */
function looksLikePhoneOrWhatsapp(line: string): boolean {
  const t = line.trim();
  if (!t) return false;

  // contains "واتس/واتساب" OR starts with international prefix OR has long digit run
  if (/واتس|واتساب|whats\s*app/i.test(t)) return true;

  // +966..., 00966..., 0020..., etc.
  if (/^(\+|00)\d{6,}/.test(t.replace(/\s+/g, ""))) return true;

  // long digits (Arabic-Indic or ASCII) -> phone-ish
  const digits = t.match(/[0-9\u0660-\u0669\u06F0-\u06F9]/g) || [];
  if (digits.length >= 9) return true;

  return false;
}

function looksLikeHandleOrContactLine(line: string): boolean {
  const t = line.trim();
  if (!t) return false;

  // social handles
  if (/@[A-Za-z0-9_\.]{2,}/.test(t)) return true;

  // emails
  if (/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/.test(t)) return true;

  // URLs even without scheme
  if (/(https?:\/\/|www\.)/i.test(t)) return true;
  if (/\b[A-Za-z0-9-]+\.(com|net|org|io|sa|me|app|edu|gov)\b/i.test(t)) return true;

  // contact keywords
  if (/للتواصل|للتواصل:|للتواصل\s*$|الموقع\s*الإلكتروني|الموقع الالكتروني|موقع\s*الكتروني|حساب|حسابات|تويتر|سناب|انستقرام/i.test(t)) {
    return true;
  }

  // phone/whatsapp
  if (looksLikePhoneOrWhatsapp(t)) return true;

  return false;
}

/**
 * Lines that are bibliographic/publisher metadata:
 * - "فهرسة مكتبة الملك فهد الوطنية..."
 * - "ردمك / ISBN"
 * - "رقم الإيداع / ديوي / التصنيف"
 * - "دار النشر / مركز ... للنشر والتوزيع / التجهيز الفني..."
 */
function looksLikeBibliographicMetaLine(line: string): boolean {
  const t = line.trim();
  if (!t) return false;

  const metaRe =
    /فهرسة\s+مكتبة|مكتبة\s+الملك\s+فهد|أثناء\s+النشر|ردمك|isbn|رقم\s+الإيداع|التصنيف|ديوي|رقم\s+التسجيل|الترقيم\s+الدولي|حقوق\s+النشر|جميع\s+الحقوق|الناشر|دار\s+النشر|الطبعة|التجهيز\s+الفني|تصميم|مصمم|الغلاف|لجنة\s+النشر|النشر\s+و\s*التوزيع|مركز\s+خدمة\s+المؤلفين|خدمة\s+المؤلفين|طباعة|تسويق|توزيع/i;

  if (metaRe.test(t)) return true;

  // ".... ١٥×٢٢ سم" size line / physical description
  if (/[0-9\u0660-\u0669\u06F0-\u06F9]+\s*×\s*[0-9\u0660-\u0669\u06F0-\u06F9]+\s*سم/.test(t)) return true;

  // ".... ص ؛" pages/format line often appears in CIP
  if (/\bص\b\s*[؛;]/.test(t)) return true;

  return false;
}

/**
 * Decide if the whole page is front-matter metadata (CIP/publisher/contact).
 * We keep it conservative + protect real content like "مقدمة" / "الفصل".
 */
function isFrontMatterMetaPage(rawText: string, pageIndex: number): boolean {
  // Most of these pages appear early; but sometimes repeat later. We'll allow early bias.
  const earlyBias = pageIndex <= 12;

  const text = rawText.trim();
  if (!text) return false;

  // protect real narrative beginnings
  if (/(^|\n)\s*مقدمة\s*($|\n)/.test(text)) return false;
  if (/(^|\n)\s*(الفصل|الباب)\s+/.test(text)) return false;

  const lines = text.split(/\r?\n+/).map((l) => l.trim()).filter(Boolean);
  if (!lines.length) return false;

  let metaHits = 0;
  let contactHits = 0;

  for (const ln of lines.slice(0, 80)) {
    if (looksLikeBibliographicMetaLine(ln)) metaHits++;
    if (looksLikeHandleOrContactLine(ln)) contactHits++;
  }

  // If it screams metadata/contact
  const strong =
    metaHits >= 4 ||
    (metaHits >= 2 && contactHits >= 2) ||
    contactHits >= 5;

  // Also if many short label-like lines and very little punctuation, typical CIP blocks
  const punctCount = (text.match(/[\.؟!؛،:]/g) || []).length;
  const arabicLetters = (text.match(/[\u0600-\u06FF]/g) || []).length;

  const cipStyle =
    (metaHits + contactHits) >= Math.max(6, Math.floor(lines.length * 0.35)) &&
    punctCount <= 6 &&
    arabicLetters < 1800;

  if (earlyBias && (strong || cipStyle)) return true;
  if (!earlyBias && strong && (metaHits + contactHits) >= 8) return true;

  return false;
}

// ================== Cleaning pages ==================

/**
 * Clean book pages:
 * - Remove table of contents / publisher / rights pages entirely
 * - Remove page-number lines
 * - Remove repeating small headers/footers
 * - Remove TOC-like dotted lines
 * - Remove decorative-only lines
 * - Strip reference-style footer blocks at the bottom (per page)
 * - NEW: remove bibliographic/publisher/contact front-matter pages + lines
 */
function cleanPages(rawPages: string[]): string[] {
  if (!rawPages.length) return [];

  const pagesLines = rawPages.map((p) => p.split(/\r?\n+/));

  // 1) Detect repeated small header/footer lines across pages
  const freq = new Map<string, number>();

  for (const lines of pagesLines) {
    const top = lines.slice(0, 3);
    const bottom = lines.slice(-2);
    for (const raw of [...top, ...bottom]) {
      const line = raw.trim();
      if (!line) continue;
      if (isPageNumberLine(line)) continue;
      if (line.length > 80) continue;
      const key = line;
      freq.set(key, (freq.get(key) || 0) + 1);
    }
  }

  const headerFooterCandidates = new Set<string>();
  for (const [line, count] of freq.entries()) {
    if (count >= 2) headerFooterCandidates.add(line);
  }

  const cleaned: string[] = [];

  for (let pageIndex = 0; pageIndex < pagesLines.length; pageIndex++) {
    const lines = pagesLines[pageIndex];
    const rawPageText = lines.join("\n");
    const lower = rawPageText.toLowerCase();

    // NEW: skip full front-matter meta pages (CIP/publisher/contact)
    if (isFrontMatterMetaPage(rawPageText, pageIndex)) {
      continue;
    }

    const isTocByStructure = isTocStructurePage(lines, pageIndex);

    const isTocPage =
      isTocByStructure ||
      /المحتويات/.test(rawPageText) ||
      /الفهرس/.test(rawPageText);

    const publisherKeywords = [
      "مؤسسة هنداوي",
      "الناشر",
      "hindawi.org",
      "حقوق النشر",
      "الترقيم الدولي",
      "isbn",
      "copyright",
    ];

    const isPublisherPage = publisherKeywords.some((kw) =>
      lower.includes(kw.toLowerCase())
    );

    if (isTocPage || isPublisherPage) {
      continue;
    }

    // 3) Line-by-line cleaning before footer detection
    const candidateLines: string[] = [];

    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (!line) continue;

      if (isPageNumberLine(line)) continue;
      if (headerFooterCandidates.has(line)) continue;

      if (/^(الفهرس|المحتويات|فهرس المحتويات|table of contents|contents)\b/i.test(line)) {
        continue;
      }

      // NEW: drop contact/handle/phone lines anywhere
      if (looksLikeHandleOrContactLine(line)) continue;

      // NEW: drop bibliographic/publisher meta lines anywhere
      // (BUT do not delete "مقدمة" or "الفصل..." lines)
      if (!/^\s*مقدمة\s*$/i.test(line) && !/^\s*(الفصل|الباب)\s+/i.test(line)) {
        if (looksLikeBibliographicMetaLine(line)) continue;
      }

      candidateLines.push(line);
    }

    // 3.5) Strip reference-style footer block from the bottom of this page
    const footerStrippedLines = stripReferenceFooterFromLines(candidateLines);

    // Remove dotted leaders and decorative-only lines
    const finalLines: string[] = [];
    for (const l of footerStrippedLines) {
      if (/\.{5,}/.test(l)) continue;            // dotted leaders
      if (/^[\u2022•·]+$/.test(l)) continue;     // bullets-only
      if (/^[\.\-\_]{3,}$/.test(l)) continue;    // horizontal dividers
      finalLines.push(l);
    }

    let joined = finalLines.join("\n").trim();

    // Remove inline page numbers
    joined = removeInlinePageNumbers(joined).trim();

    if (joined) cleaned.push(joined);
  }

  return cleaned;
}

// =============== English stripping & page classification (UPDATED) ===============

/** Strip inline English from text: words, URLs, emails, DOIs; keep Arabic. */
function stripInlineEnglish(text: string): string {
  let t = text;

  // Remove URLs + domains even without scheme
  t = t.replace(/https?:\/\/\S+|www\.\S+|doi\.org\/\S+/gi, " ");
  t = t.replace(/\b[A-Za-z0-9-]+\.(com|net|org|io|sa|me|app|edu|gov)\S*/gi, " ");

  // Remove emails
  t = t.replace(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/g, " ");

  // Remove @handles
  t = t.replace(/@[A-Za-z0-9_\.]{2,}/g, " ");

  // Remove standalone Latin words/tokens
  t = t.replace(/\b[A-Za-z][A-Za-z\-']*\b/g, " ");

  // Remove phone-ish sequences (to reduce noise)
  t = t.replace(/(\+|00)\d{6,}/g, " ");
  t = t.replace(/[0-9\u0660-\u0669\u06F0-\u06F9]{9,}/g, " ");

  // Collapse extra spaces and tidy lines
  t = t
    .split(/\r?\n+/)
    .map((ln) => ln.replace(/\s{2,}/g, " ").trim())
    .filter((ln) => ln.length > 0)
    .join("\n");

  return t.trim();
}

/** Quick counters */
function countMatches(s: string, re: RegExp): number {
  const m = s.match(re);
  return m ? m.length : 0;
}

/** Detect 'References/المراجع' pages to skip completely. */
function looksLikeReferencesPage(text: string): boolean {
  const t = text.trim();
  if (/^(المراجع|المصادر|المراجع\s*والمصادر)\b/.test(t)) return true;
  if (/^references\b/i.test(t)) return true;

  const lines = t.split(/\r?\n+/);
  let refLike = 0;
  for (const ln of lines.slice(0, 60)) {
    const l = ln.trim();
    if (!l) continue;
    if (/\(\s*\d{4}\s*\)\.?$/.test(l) || /[\u0660-\u0669]{4}\s*[\.\)]?$/.test(l)) refLike++;
    if (/doi\.org|http|https|www\./i.test(l)) refLike++;
    if (/[A-Za-z]{3,}.*,/.test(l)) refLike++;
  }
  return refLike >= 3;
}

/**
 * Heuristic: skip whole page if it's mostly English or becomes noise after stripping.
 */
function shouldSkipAsMostlyEnglish(rawText: string): boolean {
  const lettersOnly = rawText.replace(/[^A-Za-z\u0600-\u06FF]/g, "");
  const latinCount = countMatches(lettersOnly, /[A-Za-z]/g);
  const arabicCount = countMatches(lettersOnly, /[\u0600-\u06FF]/g);

  if (latinCount >= Math.max(60, 3 * arabicCount) && arabicCount < 120) {
    return true;
  }

  const arabicOnly = stripInlineEnglish(rawText);
  if (!arabicOnly) return true;

  const core = arabicOnly.replace(
    /[0-9\u0660-\u0669\u06F0-\u06F9\s\.\,\-\_\:\;\(\)\[\]\{\}\/\\|~`'"!?…•٫٬؛،]+/g,
    ""
  );
  if (core.length < 20) return true;

  const arabicLines = arabicOnly
    .split(/\r?\n+/)
    .map((s) => s.trim())
    .filter(Boolean)
    .filter((s) => /[\u0600-\u06FF]{3,}/.test(s)).length;

  if (arabicLines <= 1 && core.length < 40) return true;

  return false;
}

/**
 * Decide per-page: type + spoken text (Arabic only).
 */
function processOnePageForSpeech(rawText: string) {
  const base = rawText.trim();
  if (!base) return { type: "empty" as const, spokenText: "" };

  // NEW: final safety net — if somehow meta page passed earlier, drop it here too
  // (we don't have pageIndex here, but still useful)
  if (isFrontMatterMetaPage(base, 0)) {
    return { type: "front_matter" as const, spokenText: "" };
  }

  if (looksLikeReferencesPage(base)) {
    return { type: "references" as const, spokenText: "" };
  }

  if (shouldSkipAsMostlyEnglish(base)) {
    return { type: "english" as const, spokenText: "" };
  }

  const arabicOnly = stripInlineEnglish(base);
  if (!arabicOnly) return { type: "empty" as const, spokenText: "" };

  return { type: "text" as const, spokenText: arabicOnly };
}

// ========== Read all JSON files under outPrefix at any depth, and collect pages ==========
async function collectPages(outPrefix: string): Promise<string[]> {
  const bucket = storage.bucket(DOC_OUTPUT_BUCKET);

  const maxAttempts = 12;
  const delayMs = 5000;
  const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

  let jsonFiles: any[] = [];
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const [files] = await bucket.getFiles({
      prefix: outPrefix,
      autoPaginate: true,
    });
    jsonFiles = files.filter((f) => f.name.endsWith(".json"));
    logger.info("OCR JSON scan", {
      outPrefix,
      attempt,
      totalFound: files.length,
      jsonFound: jsonFiles.length,
      sampleFirst: jsonFiles[0]?.name,
      sampleLast: jsonFiles[jsonFiles.length - 1]?.name,
    });
    if (jsonFiles.length > 0) break;
    await sleep(delayMs);
  }
  if (!jsonFiles.length) throw new Error("No OCR JSON files found");

  jsonFiles.sort((a, b) => a.name.localeCompare(b.name));

  const pagesTexts: string[] = [];
  let anyFullText = false;

  let readCount = 0;
  let withDocCount = 0;
  let skippedNoDoc = 0;

  for (const f of jsonFiles) {
    readCount++;
    const [buf] = await bucket.file(f.name).download();
    const j = JSON.parse(buf.toString("utf-8"));

    const candidateDoc =
      j?.document ||
      j?.documentShard?.document ||
      (j?.pages && j?.text ? j : null);

    if (!candidateDoc) {
      skippedNoDoc++;
      logger.warn("JSON without document object", { name: f.name });
      continue;
    }
    withDocCount++;

    const doc = candidateDoc;
    const full: string = typeof doc.text === "string" ? doc.text : "";
    const pagesArr: any[] = Array.isArray(doc.pages) ? doc.pages : [];

    logger.info("Doc structure", {
      name: f.name,
      fullTextLen: full.length,
      pagesCount: pagesArr.length,
      hasParagraphs: !!pagesArr[0]?.paragraphs,
      hasLines: !!pagesArr[0]?.lines,
      hasBlocks: !!pagesArr[0]?.blocks,
      hasTokens: !!pagesArr[0]?.tokens,
    });

    if (full) anyFullText = true;

    if (!pagesArr.length) {
      if (full?.trim()) pagesTexts.push(full.trim());
      else logger.warn("No pages and no document.text", { name: f.name });
      continue;
    }

    for (const page of pagesArr) {
      const txt = extractOnePageText(page, full);
      if (txt) pagesTexts.push(txt);
    }
  }

  logger.info("JSON summary", { readCount, withDocCount, skippedNoDoc });

  if (!pagesTexts.length && anyFullText) {
    logger.warn("Fallback to single-page from full document.text");
    for (const f of jsonFiles) {
      const [buf] = await bucket.file(f.name).download();
      const j = JSON.parse(buf.toString("utf-8"));
      const doc =
        j?.document ||
        j?.documentShard?.document ||
        (j?.pages && j?.text ? j : null);
      const full = doc?.text;
      if (typeof full === "string" && full.trim()) {
        pagesTexts.push(full.trim());
        break;
      }
    }
  }

  const nonEmpty = pagesTexts.filter((p) => p && p.trim().length > 0);
  logger.info("Pages collected (raw)", {
    pages: nonEmpty.length,
  });

  const cleaned = cleanPages(nonEmpty);
  logger.info("Pages after cleaning", {
    before: nonEmpty.length,
    after: cleaned.length,
  });

  return cleaned;
}

// ========== Generic helper: process items with bounded concurrency ==========
async function processWithConcurrency<T, R>(
  items: T[],
  maxConcurrent: number,
  worker: (item: T, index: number) => Promise<R>
): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let currentIndex = 0;

  async function runWorker() {
    while (true) {
      const i = currentIndex++;
      if (i >= items.length) break;
      results[i] = await worker(items[i], i);
    }
  }

  const workers: Promise<void>[] = [];
  const workerCount = Math.min(maxConcurrent, items.length);
  for (let i = 0; i < workerCount; i++) {
    workers.push(runWorker());
  }

  await Promise.all(workers);
  return results;
}

// ================== MAIN FUNCTION ==================
export const ocrOnPdfUploadV2 = onObjectFinalized(
  {
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "2GiB",
  },
  async (event) => {
    // Only process PDFs from the expected bucket
    const triggeredBucket = event.data?.bucket;
    if (triggeredBucket !== APP_BUCKET) {
      logger.info("Skip different bucket", {
        triggeredBucket,
        expected: APP_BUCKET,
      });
      return;
    }

    const { name: filePath, contentType } = event.data || {};
    if (!filePath || !contentType?.includes("pdf")) {
      logger.info("Skip non-PDF", { filePath, contentType });
      return;
    }

    // Determine upload context (admin public book vs user private book)
    const ctx = getUploadContext(filePath);
    if (!ctx) {
      logger.info("Skip invalid path (not admin nor user book)", { filePath });
      return;
    }

    const logId =
      ctx.kind === "admin"
        ? ctx.bookId
        : `${ctx.userId}/${ctx.docId}`;

    logger.info("Triggered OCR", {
      filePath,
      kind: ctx.kind,
      id: logId,
      basePrefix: ctx.basePrefix,
    });

    // 0) If the PDF is large, split it into multiple parts and process each separately.
    const { inputUris, pageCount, tempSplitPrefix } = await preparePdfParts(
      triggeredBucket,
      filePath
    );

    logger.info("Prepared PDF parts for OCR", {
      id: logId,
      totalPages: pageCount,
      parts: inputUris.length,
      maxPagesPerPart: MAX_PAGES_PER_PART,
    });

    // Use a single runId for this OCR run so prefixes are stable
    const runId = Date.now().toString();

    // 1) Run Batch OCR on each part with bounded parallelism
    const partResults = await processWithConcurrency(
      inputUris,
      MAX_OCR_PART_CONCURRENCY,
      async (partUri, idx) => {
        const partNumber = idx + 1;
        const outPrefix = `${ctx.basePrefix}/ocr/${runId}-p${partNumber}/`;

        logger.info("Starting OCR for part", {
          id: logId,
          part: partNumber,
          partUri,
          outPrefix,
        });

        await runBatchOCR(partUri, outPrefix);

        const partPages = await collectPages(outPrefix);
        logger.info("Collected cleaned pages for part", {
          id: logId,
          part: partNumber,
          pages: partPages.length,
        });

        return partPages;
      }
    );

    const pages = partResults.flat();

    if (!pages.length) {
      logger.error("No text pages found after OCR", {
        id: logId,
        kind: ctx.kind,
        basePrefix: ctx.basePrefix,
      });
      return;
    }

    // 2) Classify each page and build combined text (Arabic only)
    const pagesFolder = `${ctx.basePrefix}/pages`;
    const combinedPath = `${ctx.basePrefix}/book.txt`;
    const combinedToken = uuidv4();
    const processed = pages.map(processOnePageForSpeech);

    const combinedParts: string[] = [];
    for (const p of processed) {
      if (p.type === "text") combinedParts.push(p.spokenText);
    }
    const combinedText = combinedParts.join("\n\n");

    await storage.bucket(APP_BUCKET).file(combinedPath).save(combinedText, {
      resumable: false,
      contentType: "text/plain; charset=utf-8",
      metadata: {
        cacheControl: "no-cache",
        metadata: {
          firebaseStorageDownloadTokens: combinedToken,
        },
      },
    });

    for (let i = 0; i < processed.length; i++) {
      const n = String(i + 1).padStart(3, "0");
      const pPath = `${pagesFolder}/page-${n}.txt`;
      const p = processed[i];
      const payload = p.type === "text" ? p.spokenText : "";
      await storage.bucket(APP_BUCKET).file(pPath).save(payload ? payload + "\n" : "", {
        resumable: false,
        contentType: "text/plain; charset=utf-8",
        metadata: { cacheControl: "no-cache" },
      });
    }

    const publicUrl =
      `https://firebasestorage.googleapis.com/v0/b/${APP_BUCKET}/o/` +
      `${encodeURIComponent(combinedPath)}?alt=media&token=${combinedToken}`;

    logger.info("book.txt created successfully", {
      id: logId,
      kind: ctx.kind,
      totalPages: pageCount,
      logicalPages: pages.length,
      publicUrl,
      pagesFolder,
    });

    // 3) After everything is successful, delete temp-split parts if they exist
    if (tempSplitPrefix) {
      await deleteTempFolder(APP_BUCKET, tempSplitPrefix);
    }
  }
);
