// functions/src/index.ts

export { generateBookAudio } from "./generate_audio";
export { generateSummaryAudio } from "./generateSummaryAudio";
export { generateMyBookAudio } from "./generateMyBookAudio";
export * from "./generate_summary";

// OCR trigger
export { ocrOnPdfUploadV2 } from "./ocrFunction";
export { prepareBookChat, askBookChat } from "./book_chat";
