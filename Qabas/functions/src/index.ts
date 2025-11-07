import { onObjectFinalized } from "firebase-functions/v2/storage";
import { logger } from "firebase-functions";
import { Storage } from "@google-cloud/storage";
import { DocumentProcessorServiceClient } from "@google-cloud/documentai";
import { v4 as uuidv4 } from "uuid";

// ================== CONFIGURATION ==================
const APP_BUCKET = "qabas-95e06.firebasestorage.app";   // Firebase Storage bucket
const DOC_OUTPUT_BUCKET = "qabas-95e06-docai-us-1";     // Document AI output bucket
const LOCATION = "us";                                  // Processor location
const PROCESSOR_ID = "63d2df301e9805cd";                // Processor ID

const storage = new Storage();
const docai = new DocumentProcessorServiceClient();

// Path pattern: audiobooks/{bookId}/file.pdf
function getBookIdFromPath(filePath: string): string | null {
  const parts = filePath.split("/");
  return parts.length >= 3 && parts[0] === "audiobooks" ? parts[1] : null;
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
      pageText = concatIf(
        pageText,
        sliceFromAnyAnchor(pickLayoutAnchor(p), fullText)
      );
    }
  }

  if (!pageText.trim() && Array.isArray(page?.lines)) {
    for (const l of page.lines) {
      pageText = concatIf(
        pageText,
        sliceFromAnyAnchor(pickLayoutAnchor(l), fullText)
      );
    }
  }

  if (!pageText.trim() && Array.isArray(page?.blocks)) {
    for (const b of page.blocks) {
      pageText = concatIf(
        pageText,
        sliceFromAnyAnchor(pickLayoutAnchor(b), fullText)
      );
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
        pageText = concatIf(
          pageText,
          (p.layout?.textAnchor?.content as string) || ""
        );
      }
    } else if (Array.isArray(page?.lines)) {
      for (const l of page.lines) {
        pageText = concatIf(
          pageText,
          (l.layout?.textAnchor?.content as string) || ""
        );
      }
    } else if (Array.isArray(page?.blocks)) {
      for (const b of page.blocks) {
        pageText = concatIf(
          pageText,
          (b.layout?.textAnchor?.content as string) || ""
        );
      }
    }
  }

  return pageText.trim();
}

// ================== Post-processing: clean pages ==================

/**
 * Detect whether a line is just a page number (ASCII or Arabic-Indic digits),
 * or forms like "Page 3" / "صفحة ٣".
 * Supports:
 * - 0-9
 * - ٠-٩ (Arabic-Indic)
 * - ۰-۹ (Extended Arabic-Indic)
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
 * Remove inline page numbers embedded between sentences:
 * - After punctuation like ". ۱۲ الكلمة"
 * - Trailing small number at end of line, but ONLY if no other digits in that line.
 *
 * The goal is to capture page markers like "۱۱" without touching real numbers in context,
 * especially years (١٩٢٨) or measures (۱۸٠ درجة).
 */
function removeInlinePageNumbers(text: string): string {
  // 1) Remove patterns like ". ۱۲ الكلمة" or "؟ ۱۱ الفصل الثاني"
  //    Punctuation (. ! ؟) + spaces + 1-3 digits + space + letter
  text = text.replace(
    /([\.!\؟؟!])\s*[0-9\u0660-\u0669\u06F0-\u06F9]{1,3}\s+(?=[A-Za-zء-ي])/g,
    "$1 "
  );

  // 2) For each line, remove trailing small number if the rest of the line has NO digits.
  //    Example:
  //      "ركز عينيه على الطريق ومضى في سبيله. ۱۱"
  //    This is very likely a page number.
  text = text.replace(
    /^([^\n0-9\u0660-\u0669\u06F0-\u06F9]*?)\s[0-9\u0660-\u0669\u06F0-\u06F9]{1,3}\s*$/gm,
    "$1"
  );

  return text;
}

/**
 * Clean book pages:
 * - Remove table of contents / publisher / rights pages entirely
 * - Remove page-number lines ("7", "١١", "۱۱", "Page 3", "صفحة ٥")
 * - Remove repeating small headers/footers
 * - Remove TOC-like dotted lines
 * - Remove decorative-only lines (•, ... , ----- , _____)
 * - Remove inline little page numbers after punctuation or at line end (with safeguards)
 */
function cleanPages(rawPages: string[]): string[] {
  if (!rawPages.length) return [];

  const pagesLines = rawPages.map((p) => p.split(/\r?\n+/));

  // 1) Detect common small header/footer lines that repeat across pages
  const freq = new Map<string, number>();

  for (const lines of pagesLines) {
    const top = lines.slice(0, 3);
    const bottom = lines.slice(-2);
    for (const raw of [...top, ...bottom]) {
      const line = raw.trim();
      if (!line) continue;
      // Skip page-number-like lines when building header/footer candidates
      if (isPageNumberLine(line)) continue;
      if (line.length > 80) continue; // too long to be header/footer
      const key = line;
      freq.set(key, (freq.get(key) || 0) + 1);
    }
  }

  const headerFooterCandidates = new Set<string>();
  for (const [line, count] of freq.entries()) {
    if (count >= 2) {
      headerFooterCandidates.add(line);
    }
  }

  const cleaned: string[] = [];

  for (const lines of pagesLines) {
    const rawPageText = lines.join("\n");
    const lower = rawPageText.toLowerCase();

    // 2) Drop full pages that look like table of contents or publisher/rights pages
    const isTocPage =
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
      // Skip this page entirely
      continue;
    }

    // 3) Line-by-line cleaning
    const newLines: string[] = [];

    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (!line) continue;

      // Skip pure page-number style lines
      if (isPageNumberLine(line)) continue;

      // Skip repeated small header/footer lines
      if (headerFooterCandidates.has(line)) continue;

      // Skip obvious table-of-contents headers (safety if any remain)
      if (/^(الفهرس|المحتويات|فهرس المحتويات|table of contents|contents)\b/i.test(line)) {
        continue;
      }

      // Skip lines that look like TOC entries with dotted leaders (عنوان .... ١٢)
      if (/\.{5,}/.test(line)) continue;

      // Skip purely decorative lines: bullets or repeated punctuation
      // • , ••• , ... , ----- , _____ , etc.
      if (/^[\u2022•·]+$/.test(line)) continue;          // only bullet-like chars
      if (/^[\.\-\_]{3,}$/.test(line)) continue;         // only dots/dashes/underscores

      newLines.push(line);
    }

    let joined = newLines.join("\n").trim();

    // Remove inline page numbers like ". ۱۲ الفصل الثاني" or trailing " ... ۱۱"
    joined = removeInlinePageNumbers(joined).trim();

    // Drop pages that become empty after cleaning (pure TOC/rights pages)
    if (joined) cleaned.push(joined);
  }

  return cleaned;
}

// ========== Read all JSON files under outPrefix at any depth, and collect pages ==========
async function collectPages(outPrefix: string): Promise<string[]> {
  const bucket = storage.bucket(DOC_OUTPUT_BUCKET);

  // Wait for JSON files to appear (batch OCR output can be slightly delayed)
  const maxAttempts = 12;
  const delayMs = 5000;
  const sleep = (ms: number) =>
    new Promise((r) => setTimeout(r, ms));

  let jsonFiles: any[] = [];
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const [files] = await bucket.getFiles({
      prefix: outPrefix,
      autoPaginate: true,
    });
    jsonFiles = files.filter(
      (f) => f.name.endsWith(".json") && f.name.includes("book-")
    );
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

  // Sort as book-0.json, book-1.json, ...
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

    // Try to locate the document structure wherever it is
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
      // If there are no pages but we have document.text, treat it as a single page
      if (full?.trim()) pagesTexts.push(full.trim());
      else logger.warn("No pages and no document.text", { name: f.name });
      continue;
    }

    // Extract each page separately
    for (const page of pagesArr) {
      const txt = extractOnePageText(page, full);
      if (txt) pagesTexts.push(txt);
    }
  }

  logger.info("JSON summary", { readCount, withDocCount, skippedNoDoc });

  // Final fallback: if we have no pages but at least one full text, use that as single page
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

  const nonEmpty = pagesTexts.filter(
    (p) => p && p.trim().length > 0
  );
  logger.info("Pages collected (raw)", {
    pages: nonEmpty.length,
  });

  // Apply cleaning (remove TOC, publisher pages, headers, page numbers, etc.)
  const cleaned = cleanPages(nonEmpty);
  logger.info("Pages after cleaning", {
    before: nonEmpty.length,
    after: cleaned.length,
  });

  return cleaned;
}

// ================== MAIN FUNCTION ==================
export const ocrOnPdfUploadV2 = onObjectFinalized(
  {
    // No "bucket" field here to avoid region issues with some CLIs
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "2GiB",
  },
  async (event) => {
    // Process only if the event comes from the expected bucket
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

    const bookId = getBookIdFromPath(filePath);
    if (!bookId) {
      logger.info("Skip invalid path", { filePath });
      return;
    }

    logger.info("Triggered OCR", { bookId, filePath });

    // 1) Run Batch OCR on the uploaded PDF
    const gcsInputUri = `gs://${triggeredBucket}/${filePath}`;
    const outPrefix = `audiobooks/${bookId}/ocr/${Date.now()}/`;
    await runBatchOCR(gcsInputUri, outPrefix);

    // 2) Collect text page by page (already cleaned)
    const pages = await collectPages(outPrefix);
    if (!pages.length) {
      logger.error("No text pages found after OCR", { bookId });
      return;
    }

    // 3) Store:
    //    - book.txt as a continuous cleaned text (no explicit page numbers)
    //    - pages/page-xxx.txt for each cleaned page
    const pagesFolder = `audiobooks/${bookId}/pages`;
    const combinedPath = `audiobooks/${bookId}/book.txt`;

    const combinedToken = uuidv4();

    // Do NOT insert "PAGE N" markers, just separate pages by blank lines
    const combinedText = pages.join("\n\n");

    // Save combined file with a public download token
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

    // Save per-page files (kept private by default)
    for (let i = 0; i < pages.length; i++) {
      const n = String(i + 1).padStart(3, "0");
      const pPath = `${pagesFolder}/page-${n}.txt`;
      await storage
        .bucket(APP_BUCKET)
        .file(pPath)
        .save(pages[i] + "\n", {
          resumable: false,
          contentType: "text/plain; charset=utf-8",
          metadata: { cacheControl: "no-cache" },
        });
    }

    const publicUrl =
      `https://firebasestorage.googleapis.com/v0/b/${APP_BUCKET}/o/` +
      `${encodeURIComponent(combinedPath)}?alt=media&token=${combinedToken}`;

    logger.info("✅ book.txt created successfully", {
      bookId,
      pages: pages.length,
      publicUrl,
      pagesFolder,
    });
  }
);
