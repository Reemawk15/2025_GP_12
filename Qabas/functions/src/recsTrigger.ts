import { onDocumentCreated, onDocumentDeleted } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { GoogleAuth } from "google-auth-library";

const RUN_URL = "https://qabas-recs-593229990673.us-central1.run.app/recompute";

async function callRun(type: "books" | "podcasts" | "both") {
  const auth = new GoogleAuth();
  const client = await auth.getIdTokenClient(RUN_URL);

  const res = await client.request({
    url: RUN_URL,
    method: "POST",
    data: { type },
    headers: { "Content-Type": "application/json" },
  });

  return res.data;
}

export const onNewBookRecs = onDocumentCreated("audiobooks/{id}", async () => {
  try {
    const out = await callRun("books");
    logger.info("Recompute books OK", out);
  } catch (e) {
    logger.error("Recompute books FAILED", e);
  }
});
export const onDeleteBookRecs = onDocumentDeleted("audiobooks/{id}", async () => {
  try {
    const out = await callRun("books");
    logger.info("Recompute books after delete OK", out);
  } catch (e) {
    logger.error("Recompute books after delete FAILED", e);
  }
});

export const onNewPodcastRecs = onDocumentCreated("podcasts/{id}", async () => {
  try {
    const out = await callRun("podcasts");
    logger.info("Recompute podcasts OK", out);
  } catch (e) {
    logger.error("Recompute podcasts FAILED", e);
  }
});
export const onDeletePodcastRecs = onDocumentDeleted("podcasts/{id}", async () => {
  try {
    const out = await callRun("podcasts");
    logger.info("Recompute podcasts after delete OK", out);
  } catch (e) {
    logger.error("Recompute podcasts after delete FAILED", e);
  }
});