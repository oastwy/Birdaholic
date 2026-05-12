#!/usr/bin/env python3
"""Birdaholic media upload server.

Run on the server beside:
  /data/species
  /data/indexes
  /data/server/world_birds.json
  /data/server/uploader.html
"""

from __future__ import annotations

import json
import os
import re
import shutil
import time
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any

from fastapi import Body, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse


DATA_DIR = Path(os.environ.get("BIRDAHOLIC_DATA_DIR", "/data"))
SERVER_DIR = Path(os.environ.get("BIRDAHOLIC_SERVER_DIR", "/data/server"))
SPECIES_DIR = DATA_DIR / "species"
INDEX_DIR = DATA_DIR / "indexes"
WORLD_BIRDS_PATH = Path(
    os.environ.get("BIRDAHOLIC_WORLD_BIRDS", str(SERVER_DIR / "world_birds.json"))
)
UPLOAD_TOKEN = os.environ.get("BIRDAHOLIC_UPLOAD_TOKEN", "")
PUBLIC_BASE_URL = os.environ.get(
    "BIRDAHOLIC_PUBLIC_BASE_URL", "http://124.223.101.188:8080"
).rstrip("/")

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".heic"}
AUDIO_EXTS = {".mp3", ".m4a", ".aac", ".wav", ".flac", ".ogg"}
ALIASES = {
    "common chaffinch": "eurasian chaffinch",
}

app = FastAPI(title="Birdaholic Upload Server")


def species_key(scientific_name: str) -> str:
    return "_".join(scientific_name.strip().split())


def normalize_name(value: str) -> str:
    text = Path(value).stem.lower()
    text = re.sub(r"[_\-]+", " ", text)
    text = re.split(r"\b(mon|tue|wed|thu|fri|sat|sun)\b", text, maxsplit=1)[0]
    text = re.split(r"\b\d{4}[-_ ]\d{2}[-_ ]\d{2}\b", text, maxsplit=1)[0]
    text = text.replace("gray", "grey")
    text = re.sub(
        r"\b(song|call|audio|sound|image|photo|bird|male|female|"
        r"jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|"
        r"monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b",
        " ",
        text,
    )
    text = re.sub(r"\b\d+\b", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    text = ALIASES.get(text, text)
    return text


def load_world_birds() -> list[dict[str, Any]]:
    if not WORLD_BIRDS_PATH.exists():
        return []
    return json.loads(WORLD_BIRDS_PATH.read_text(encoding="utf-8"))


WORLD_BIRDS = load_world_birds()


def candidate_names(item: dict[str, Any]) -> list[str]:
    names = [
        item.get("sci", ""),
        item.get("en", ""),
        item.get("zh", ""),
        item.get("zh_tw", ""),
        item.get("code", ""),
    ]
    names.extend(item.get("en_alt", []) or [])
    return [name for name in names if isinstance(name, str) and name.strip()]


def match_species(query: str) -> dict[str, Any] | None:
    normalized = normalize_name(query)
    if not normalized:
        return None

    for item in WORLD_BIRDS:
        sci = item.get("sci", "")
        if normalized == normalize_name(sci) or normalized == species_key(sci).lower():
            return item
        for name in candidate_names(item):
            if normalized == normalize_name(name):
                return item

    best: tuple[float, dict[str, Any] | None] = (0.0, None)
    for item in WORLD_BIRDS:
        for name in candidate_names(item):
            score = SequenceMatcher(None, normalized, normalize_name(name)).ratio()
            if score > best[0]:
                best = (score, item)
    return best[1] if best[0] >= 0.88 else None


def check_token(authorization: str | None, token: str | None) -> None:
    bearer = ""
    if authorization and authorization.lower().startswith("bearer "):
        bearer = authorization[7:].strip()
    if UPLOAD_TOKEN and token != UPLOAD_TOKEN and bearer != UPLOAD_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid upload token")


def media_kind(filename: str, content_type: str = "") -> str | None:
    suffix = Path(filename).suffix.lower()
    if suffix in IMAGE_EXTS or content_type.startswith("image/"):
        return "images"
    if suffix in AUDIO_EXTS or content_type.startswith("audio/"):
        return "audio"
    return None


def safe_filename(filename: str) -> str:
    suffix = Path(filename).suffix.lower()
    stem = re.sub(r"[^A-Za-z0-9_.-]+", "_", Path(filename).stem).strip("._")
    if not stem:
        stem = "media"
    return f"{int(time.time() * 1000)}_{stem[:80]}{suffix}"


def load_manifest(sci: str, item: dict[str, Any] | None = None) -> dict[str, Any]:
    key = species_key(sci)
    path = SPECIES_DIR / key / "manifest.json"
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    item = item or {}
    return {
        "sci": sci,
        "cn": item.get("zh", ""),
        "en": item.get("en", ""),
        "order": item.get("order", ""),
        "family": item.get("family", ""),
        "cons": item.get("protection", ""),
        "habitat": "",
        "images": [],
        "audio": [],
        "source_packs": [],
    }


def public_url(sci: str, kind: str, filename: str) -> str:
    key = species_key(sci)
    return f"{PUBLIC_BASE_URL}/species/{key}/{kind}/{filename}"


def update_index() -> None:
    INDEX_DIR.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, Any]] = []
    for manifest_path in sorted(SPECIES_DIR.glob("*/manifest.json")):
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        rows.append(
            {
                "sci": manifest.get("sci", ""),
                "cn": manifest.get("cn", ""),
                "en": manifest.get("en", ""),
                "order": manifest.get("order", ""),
                "family": manifest.get("family", ""),
                "species_dir": manifest_path.parent.name,
                "manifest_url": f"{PUBLIC_BASE_URL}/species/{manifest_path.parent.name}/manifest.json",
                "image_count": len(manifest.get("images", [])),
                "audio_count": len(manifest.get("audio", [])),
                "source_packs": manifest.get("source_packs", []),
            }
        )
    (INDEX_DIR / "species_media_index.json").write_text(
        json.dumps(rows, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


@app.get("/uploader")
def uploader() -> FileResponse:
    html = SERVER_DIR / "uploader.html"
    if not html.exists():
        raise HTTPException(status_code=404, detail="uploader.html not found")
    return FileResponse(html)


@app.get("/api/search")
def search(q: str = "") -> list[dict[str, str]]:
    query = normalize_name(q)
    if not query:
        return []
    results: list[dict[str, str]] = []
    for item in WORLD_BIRDS:
        joined = " ".join(candidate_names(item)).lower()
        if query in normalize_name(joined):
            results.append(
                {
                    "sci": item.get("sci", ""),
                    "en": item.get("en", ""),
                    "zh": item.get("zh", ""),
                    "code": item.get("code", ""),
                }
            )
        if len(results) >= 20:
            break
    return results


@app.get("/api/recognize_filename")
def recognize_filename(filename: str) -> dict[str, Any]:
    item = match_species(filename)
    return {"matched": bool(item), "species": item or {}}


@app.post("/api/upload")
async def upload(
    files: list[UploadFile] = File(...),
    token: str = Form(""),
    sci: str = Form(""),
    contributor: str = Form("用户上传"),
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    check_token(authorization, token)
    SPECIES_DIR.mkdir(parents=True, exist_ok=True)

    selected = None
    if sci.strip():
        selected = match_species(sci) or {"sci": sci.strip()}

    saved: list[dict[str, Any]] = []
    failed: list[dict[str, str]] = []

    for upload_file in files:
        kind = media_kind(upload_file.filename, upload_file.content_type or "")
        if kind is None:
            failed.append({"file": upload_file.filename, "reason": "unsupported file type"})
            continue

        item = selected or match_species(upload_file.filename)
        if not item or not item.get("sci"):
            failed.append({"file": upload_file.filename, "reason": "species not recognized"})
            continue

        target_sci = item["sci"]
        key = species_key(target_sci)
        target_dir = SPECIES_DIR / key / kind
        target_dir.mkdir(parents=True, exist_ok=True)
        filename = safe_filename(upload_file.filename)
        target = target_dir / filename
        with target.open("wb") as handle:
            shutil.copyfileobj(upload_file.file, handle)

        manifest = load_manifest(target_sci, item)
        if kind == "images":
            manifest.setdefault("images", []).append(
                {
                    "file": f"images/{filename}",
                    "url": public_url(target_sci, "images", filename),
                    "contributor": contributor.strip() or "用户上传",
                    "contributor_url": "",
                    "source": "birdaholic-upload",
                }
            )
        else:
            file_type = "song" if "song" in upload_file.filename.lower() else "call"
            manifest.setdefault("audio", []).append(
                {
                    "file": f"audio/{filename}",
                    "url": public_url(target_sci, "audio", filename),
                    "type": file_type,
                    "contributor": contributor.strip() or "用户上传",
                    "contributor_url": "",
                    "source": "birdaholic-upload",
                }
            )
        (SPECIES_DIR / key / "manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        saved.append({"file": upload_file.filename, "sci": target_sci, "kind": kind})

    update_index()
    return {"saved": saved, "failed": failed}


@app.post("/api/features")
async def save_features(
    payload: dict[str, Any] = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    check_token(authorization, token)
    sci = str(payload.get("sci", "")).strip()
    if not sci:
        raise HTTPException(status_code=400, detail="Missing sci")

    item = match_species(sci) or {
        "sci": sci,
        "zh": str(payload.get("cn", "")),
        "en": str(payload.get("en", "")),
    }
    key = species_key(sci)
    (SPECIES_DIR / key).mkdir(parents=True, exist_ok=True)
    manifest = load_manifest(sci, item)
    manifest["identification_features"] = str(payload.get("features", "")).strip()
    manifest["identification_features_updated_at"] = int(time.time())
    (SPECIES_DIR / key / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    update_index()
    return {"saved": True, "sci": sci}
