import os
import re
import time
import threading
from typing import Any, List

import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

import firebase_admin
from firebase_admin import firestore

from sentence_transformers import SentenceTransformer

# ================= CONFIG =================
MODEL_NAME = os.getenv("MODEL_NAME", "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2")
TOP_K = int(os.getenv("TOP_K", "20"))

W_CATEGORY = 3.0
W_AUTHOR = 2.0
W_TITLE_TOKEN = 1.0
W_DESC_SEM = 2.0

MIN_SCORE = 3.0
MIN_DESC_SEM = 0.30

BATCH_FLUSH_EVERY = int(os.getenv("BATCH_FLUSH_EVERY", "400"))

# ================= APP =================
app = FastAPI()

class Req(BaseModel):
    type: str = "both"   # "books" | "podcasts" | "both"

# ================= GLOBAL MODEL (load once lazily) =================
_model = None
_model_lock = threading.Lock()
_model_error: str | None = None

def _init_firestore():
    if not firebase_admin._apps:
        firebase_admin.initialize_app()  # Default credentials on Cloud Run
    return firestore.client()

def _load_model_once():
    """
    Load model once with retries.
    Important: do NOT load at import time, so container can start and pass health check.
    """
    global _model, _model_error

    if _model is not None:
        return _model

    with _model_lock:
        if _model is not None:
            return _model

        hf_token = os.getenv("HF_TOKEN", "").strip()
        if hf_token:
            # Optional: authenticate to avoid HF anonymous rate limits
            try:
                from huggingface_hub import login
                login(token=hf_token, add_to_git_credential=False)
            except Exception:
                # If login fails, still try to load (maybe cached)
                pass

        # Retry loop (handles transient 429)
        last_err = None
        for attempt in range(1, 6):  # 5 tries
            try:
                _model = SentenceTransformer(MODEL_NAME)
                _model_error = None
                return _model
            except Exception as e:
                last_err = e
                _model = None
                _model_error = str(e)

                # exponential backoff
                sleep_s = min(15 * attempt, 90)
                time.sleep(sleep_s)

        raise RuntimeError(f"Failed to load model after retries: {last_err}")

# ================= HELPERS =================
AR_STOP = set([
    "من","في","على","إلى","عن","مع","هذا","هذه","ذلك","تلك","هو","هي","كان","كانت",
])

def normalize_text(s: str) -> str:
    s = s or ""
    s = re.sub(r"[^\u0600-\u06FF0-9A-Za-z\s]", " ", s)
    s = re.sub(r"\s+", " ", s).strip().lower()
    return s

def tokenize_ar(s: str) -> List[str]:
    s = normalize_text(s)
    return [t for t in s.split() if len(t) >= 3 and t not in AR_STOP]

def as_list(v: Any) -> List[str]:
    if v is None:
        return []
    if isinstance(v, list):
        return [str(x).strip() for x in v if str(x).strip()]
    v = str(v).strip()
    return [v] if v else []

def normalize_category(cat: str) -> str:
    return (cat or "").strip().lower()

def jaccard(a: List[str], b: List[str]) -> float:
    sa, sb = set(a), set(b)
    if not sa or not sb:
        return 0.0
    return len(sa & sb) / len(sa | sb)

def safe_str(x: Any) -> str:
    return (x or "").strip() if isinstance(x, str) else str(x).strip()

# ================= CORE =================
def write_similar(db, collection: str, out_field: str):
    snaps = list(db.collection(collection).stream())
    items = [(s.id, s.to_dict() or {}) for s in snaps]

    if len(items) < 2:
        return {"collection": collection, "updated": 0, "note": "not_enough_items"}

    model = _load_model_once()

    desc_texts = [safe_str(it.get("description", "")) for _, it in items]
    desc_emb = model.encode(desc_texts, normalize_embeddings=True)
    desc_emb = np.array(desc_emb)
    desc_sim = desc_emb @ desc_emb.T

    batch = db.batch()
    pending = 0
    updated = 0

    for i, (id1, it1) in enumerate(items):
        scored = []

        c1 = set(normalize_category(x) for x in as_list(it1.get("category")))
        a1 = normalize_text(it1.get("author", ""))

        for j, (id2, it2) in enumerate(items):
            if id1 == id2:
                continue

            c2 = set(normalize_category(x) for x in as_list(it2.get("category")))
            a2 = normalize_text(it2.get("author", ""))

            # gate: must share category or same author
            if not (c1 & c2 or (a1 and a1 == a2)):
                continue

            score = 0.0

            if c1 & c2:
                score += W_CATEGORY
            if a1 and a1 == a2:
                score += W_AUTHOR

            t1 = tokenize_ar(it1.get("title", ""))
            t2 = tokenize_ar(it2.get("title", ""))
            score += W_TITLE_TOKEN * jaccard(t1, t2)

            sem = float(desc_sim[i, j])
            if sem >= MIN_DESC_SEM:
                score += W_DESC_SEM * sem

            if score >= MIN_SCORE:
                scored.append((score, id2))

        scored.sort(reverse=True)
        similar_ids = [sid for _, sid in scored[:TOP_K]]

        batch.update(db.collection(collection).document(id1), {out_field: similar_ids})
        updated += 1

        pending += 1
        if pending >= BATCH_FLUSH_EVERY:
            batch.commit()
            batch = db.batch()
            pending = 0

    if pending:
        batch.commit()

    return {"collection": collection, "updated": updated}

def run_all(which: str):
    db = _init_firestore()
    out = {"which": which, "results": []}

    if which in ("books", "both"):
        out["results"].append(write_similar(db, "audiobooks", "similarBookIds"))

    if which in ("podcasts", "both"):
        out["results"].append(write_similar(db, "podcasts", "similarPodcastIds"))

    return out

# ================= API =================
@app.get("/")
def health():
    # مهم عشان ما يطلع Not Found
    return {
        "ok": True,
        "service": "qabas-recs",
        "model": MODEL_NAME,
        "model_loaded": _model is not None,
        "model_error": _model_error,
        "routes": ["/", "/recompute"],
    }

@app.post("/recompute")
def recompute(req: Req):
    t = (req.type or "both").strip().lower()
    if t not in ("books", "podcasts", "both"):
        t = "both"

    try:
        return run_all(t)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))