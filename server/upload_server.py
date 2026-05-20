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
from fastapi.responses import FileResponse, HTMLResponse


DATA_DIR = Path(os.environ.get("BIRDAHOLIC_DATA_DIR", "/data"))
SERVER_DIR = Path(os.environ.get("BIRDAHOLIC_SERVER_DIR", "/data/server"))
SPECIES_DIR = DATA_DIR / "species"
INDEX_DIR = DATA_DIR / "indexes"
WORLD_BIRDS_PATH = Path(
    os.environ.get("BIRDAHOLIC_WORLD_BIRDS", str(SERVER_DIR / "world_birds.json"))
)
UPLOAD_TOKEN = os.environ.get("BIRDAHOLIC_UPLOAD_TOKEN", "")
USERS_FILE = Path("/data/server/users.json")


def load_users() -> dict:
    if USERS_FILE.exists():
        try:
            return json.loads(USERS_FILE.read_text(encoding="utf-8"))
        except Exception:
            return {}
    return {}
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
WORLD_BY_SCI = {
    str(item.get("sci", "")).strip().lower(): item
    for item in WORLD_BIRDS
    if item.get("sci")
}


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


def authenticate(authorization: str | None, token: str | None) -> dict:
    """Resolve token to a user record {id, role, name, token}.
    Order: users.json -> legacy UPLOAD_TOKEN env -> 401.
    """
    bearer = ""
    if authorization and authorization.lower().startswith("bearer "):
        bearer = authorization[7:].strip()
    provided = (bearer or (token or "")).strip()
    if not provided:
        if not UPLOAD_TOKEN and not load_users():
            return {"id": "anon", "role": "admin", "name": "anon", "token": ""}
        raise HTTPException(status_code=401, detail="Missing upload token")
    users = load_users()
    if provided in users:
        u = dict(users[provided])
        u.setdefault("id", "user")
        u.setdefault("role", "beta")
        u.setdefault("name", u["id"])
        u["token"] = provided
        return u
    if UPLOAD_TOKEN and provided == UPLOAD_TOKEN:
        return {"id": "legacy_admin", "role": "admin", "name": "管理员", "token": provided}
    raise HTTPException(status_code=401, detail="Invalid upload token")


def check_token(authorization: str | None, token: str | None) -> None:
    authenticate(authorization, token)


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


def build_index_rows() -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for manifest_path in sorted(SPECIES_DIR.glob("*/manifest.json")):
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        sci = str(manifest.get("sci", "")).strip()
        world_item = WORLD_BY_SCI.get(sci.lower(), {})
        rows.append(
            {
                "sci": sci,
                "cn": manifest.get("cn", "") or world_item.get("zh", ""),
                "en": manifest.get("en", "") or world_item.get("en", ""),
                "order": manifest.get("order", "") or world_item.get("order", ""),
                "family": manifest.get("family", "") or world_item.get("family", ""),
                "species_dir": manifest_path.parent.name,
                "manifest_url": f"{PUBLIC_BASE_URL}/species/{manifest_path.parent.name}/manifest.json",
                "image_count": sum(1 for x in manifest.get("images", []) if not x.get("pending")),
                "audio_count": sum(1 for x in manifest.get("audio", []) if not x.get("pending")),
                "source_packs": manifest.get("source_packs", []),
            }
        )
    return rows


def update_index() -> None:
    INDEX_DIR.mkdir(parents=True, exist_ok=True)
    rows = build_index_rows()
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


@app.get("/tester")
def tester() -> FileResponse:
    """Beta-tester focused upload page (simplified; works for admins too)."""
    html = SERVER_DIR / "tester.html"
    if not html.exists():
        raise HTTPException(status_code=404, detail="tester.html not found")
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


@app.get("/api/stats")
def stats(q: str = "") -> dict[str, Any]:
    rows = build_index_rows()
    query = normalize_name(q)
    if query:
        rows = [
            row
            for row in rows
            if query in normalize_name(
                " ".join(
                    [
                        str(row.get("sci", "")),
                        str(row.get("cn", "")),
                        str(row.get("en", "")),
                        str(row.get("species_dir", "")),
                    ]
                )
            )
        ]
    return {
        "species_count": len(rows),
        "image_count": sum(int(row.get("image_count", 0)) for row in rows),
        "audio_count": sum(int(row.get("audio_count", 0)) for row in rows),
        "rows": rows,
    }


@app.get("/stats", response_class=HTMLResponse)
def stats_page() -> str:
    return """<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Birdaholic 服务器媒体统计</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f5f1e8;
      --ink: #1f261c;
      --muted: #66705f;
      --line: #ddd4c2;
      --panel: #fffdf8;
      --green: #255c21;
      --green-2: #e7f1df;
      --gold: #a06a1b;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--ink);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    header {
      padding: 22px 28px 16px;
      border-bottom: 1px solid var(--line);
      background: #fffaf0;
      position: sticky;
      top: 0;
      z-index: 2;
    }
    h1 { margin: 0 0 12px; font-size: 24px; letter-spacing: 0; }
    .toolbar { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
    input {
      width: min(420px, 100%);
      font-size: 16px;
      padding: 10px 12px;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: white;
      color: var(--ink);
    }
    button, a.button {
      border: 0;
      border-radius: 6px;
      padding: 10px 14px;
      background: var(--green);
      color: white;
      font-size: 15px;
      text-decoration: none;
      cursor: pointer;
    }
    main { padding: 18px 28px 28px; }
    .cards {
      display: grid;
      grid-template-columns: repeat(3, minmax(140px, 1fr));
      gap: 12px;
      margin-bottom: 16px;
    }
    .card {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 14px 16px;
    }
    .label { color: var(--muted); font-size: 13px; }
    .value { font-size: 28px; font-weight: 700; margin-top: 4px; }
    .table-wrap {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      overflow: auto;
    }
    table { width: 100%; border-collapse: collapse; min-width: 900px; }
    th, td { padding: 10px 12px; border-bottom: 1px solid var(--line); text-align: left; vertical-align: top; }
    th { background: #f7ecd7; position: sticky; top: 0; z-index: 1; }
    tr:hover td { background: var(--green-2); }
    .num { font-variant-numeric: tabular-nums; text-align: right; }
    .muted { color: var(--muted); }
    .species { font-weight: 650; }
    .sci { color: var(--muted); font-style: italic; margin-top: 2px; }
    .empty { padding: 24px; color: var(--muted); }
    @media (max-width: 760px) {
      header, main { padding-left: 14px; padding-right: 14px; }
      .cards { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <header>
    <h1>Birdaholic 服务器媒体统计</h1>
    <div class="toolbar">
      <input id="q" placeholder="搜索中文名 / English / 拉丁名">
      <button id="search">搜索</button>
      <button id="clear">清空</button>
      <a class="button" href="/api/stats" target="_blank">查看原始 JSON</a>
    </div>
  </header>
  <main>
    <section class="cards">
      <div class="card"><div class="label">物种数</div><div class="value" id="speciesCount">-</div></div>
      <div class="card"><div class="label">图片数</div><div class="value" id="imageCount">-</div></div>
      <div class="card"><div class="label">音频数</div><div class="value" id="audioCount">-</div></div>
    </section>
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>物种</th>
            <th>分类</th>
            <th class="num">图片</th>
            <th class="num">音频</th>
            <th>数据包</th>
            <th>链接</th>
          </tr>
        </thead>
        <tbody id="rows"><tr><td colspan="6" class="empty">正在加载...</td></tr></tbody>
      </table>
    </div>
  </main>
  <script>
    const q = document.getElementById('q');
    const rowsEl = document.getElementById('rows');
    const speciesCount = document.getElementById('speciesCount');
    const imageCount = document.getElementById('imageCount');
    const audioCount = document.getElementById('audioCount');

    function esc(value) {
      return String(value ?? '').replace(/[&<>"']/g, ch => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
      }[ch]));
    }

    async function load() {
      rowsEl.innerHTML = '<tr><td colspan="6" class="empty">正在加载...</td></tr>';
      const params = q.value.trim() ? '?q=' + encodeURIComponent(q.value.trim()) : '';
      const res = await fetch('/api/stats' + params);
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const data = await res.json();
      speciesCount.textContent = data.species_count ?? 0;
      imageCount.textContent = data.image_count ?? 0;
      audioCount.textContent = data.audio_count ?? 0;
      const rows = data.rows || [];
      if (!rows.length) {
        rowsEl.innerHTML = '<tr><td colspan="6" class="empty">没有匹配结果</td></tr>';
        return;
      }
      rowsEl.innerHTML = rows.map(row => `
        <tr>
          <td>
            <div class="species">${esc(row.cn || row.en || row.sci)}</div>
            <div class="sci">${esc(row.sci)}</div>
            <div class="muted">${esc(row.en || '')}</div>
          </td>
          <td>${esc(row.order || '')}<br><span class="muted">${esc(row.family || '')}</span></td>
          <td class="num">${esc(row.image_count || 0)}</td>
          <td class="num">${esc(row.audio_count || 0)}</td>
          <td>${esc((row.source_packs || []).join(', '))}</td>
          <td><a href="${esc(row.manifest_url)}" target="_blank">manifest</a></td>
        </tr>
      `).join('');
    }

    document.getElementById('search').addEventListener('click', load);
    document.getElementById('clear').addEventListener('click', () => { q.value = ''; load(); });
    q.addEventListener('keydown', event => { if (event.key === 'Enter') load(); });
    load().catch(err => {
      rowsEl.innerHTML = '<tr><td colspan="6" class="empty">加载失败：' + esc(err.message) + '</td></tr>';
    });
  </script>
</body>
</html>"""


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
    difficulty: int = Form(0),
    features: list[str] = Form(default_factory=list),
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    user = authenticate(authorization, token)
    SPECIES_DIR.mkdir(parents=True, exist_ok=True)
    is_admin = user["role"] == "admin"
    now_ts = int(time.time())

    # Clamp difficulty to [1, 5]; 0 means "not specified"
    if difficulty:
        difficulty = max(1, min(5, difficulty))

    selected = None
    if sci.strip():
        selected = match_species(sci) or {"sci": sci.strip()}

    saved: list[dict[str, Any]] = []
    failed: list[dict[str, str]] = []

    for idx, upload_file in enumerate(files):
        kind = media_kind(upload_file.filename, upload_file.content_type or "")
        if kind is None:
            failed.append({"file": upload_file.filename, "reason": "unsupported file type"})
            continue

        item = selected or match_species(upload_file.filename)
        if not item or not item.get("sci"):
            failed.append({"file": upload_file.filename, "reason": "species not recognized"})
            continue

        # Per-file identification features (notes); same index as files[]
        feat = features[idx].strip() if idx < len(features) else ""

        target_sci = item["sci"]
        key = species_key(target_sci)
        target_dir = SPECIES_DIR / key / kind
        target_dir.mkdir(parents=True, exist_ok=True)
        filename = safe_filename(upload_file.filename)
        target = target_dir / filename
        with target.open("wb") as handle:
            shutil.copyfileobj(upload_file.file, handle)

        manifest = load_manifest(target_sci, item)
        # Persist difficulty at the species level (overwrites if newer value provided)
        if difficulty and is_admin:
            manifest["difficulty"] = difficulty
        if kind == "images":
            entry = {
                "file": f"images/{filename}",
                "url": public_url(target_sci, "images", filename),
                "contributor": contributor.strip() or user.get("name", "用户上传"),
                "contributor_url": "",
                "source": "birdaholic-upload",
                "uploader_id": user["id"],
                "uploader_role": user["role"],
                "uploader_name": user.get("name", ""),
                "uploaded_at": now_ts,
            }
            if difficulty:
                # Admin: authoritative entry-level difficulty.
                # Beta: suggested difficulty, surfaced during review.
                entry["difficulty" if is_admin else "suggested_difficulty"] = difficulty
            if feat:
                entry["features"] = feat
            if not is_admin:
                entry["pending"] = True
            manifest.setdefault("images", []).append(entry)
        else:
            file_type = "song" if "song" in upload_file.filename.lower() else "call"
            entry = {
                "file": f"audio/{filename}",
                "url": public_url(target_sci, "audio", filename),
                "type": file_type,
                "contributor": contributor.strip() or user.get("name", "用户上传"),
                "contributor_url": "",
                "source": "birdaholic-upload",
                "uploader_id": user["id"],
                "uploader_role": user["role"],
                "uploader_name": user.get("name", ""),
                "uploaded_at": now_ts,
            }
            if difficulty:
                entry["difficulty" if is_admin else "suggested_difficulty"] = difficulty
            if feat:
                entry["features"] = feat
            if not is_admin:
                entry["pending"] = True
            manifest.setdefault("audio", []).append(entry)
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


@app.post("/api/set_difficulty")
async def set_difficulty(
    payload: dict[str, Any] = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    check_token(authorization, token)
    sci = str(payload.get("sci", "")).strip()
    difficulty = int(payload.get("difficulty", 0))
    if not sci:
        raise HTTPException(status_code=400, detail="Missing sci")
    if not (1 <= difficulty <= 5):
        raise HTTPException(status_code=400, detail="difficulty must be 1-5")

    item = match_species(sci) or {"sci": sci}
    key = species_key(sci)
    (SPECIES_DIR / key).mkdir(parents=True, exist_ok=True)
    manifest = load_manifest(sci, item)
    manifest["difficulty"] = difficulty
    (SPECIES_DIR / key / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    update_index()
    return {"saved": True, "sci": sci, "difficulty": difficulty}


@app.get("/api/whoami")
def whoami(
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    user = authenticate(authorization, token)
    return {"id": user["id"], "role": user["role"], "name": user.get("name", "")}


@app.get("/api/upload_stats")
def upload_stats(
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    user = authenticate(authorization, token)
    my_id = user["id"]
    my_images = my_audio = my_pending = pending_total = 0
    for mp in SPECIES_DIR.glob("*/manifest.json"):
        try:
            m = json.loads(mp.read_text(encoding="utf-8"))
        except Exception:
            continue
        for kind, ctr in (("images", "img"), ("audio", "aud")):
            for entry in m.get(kind, []):
                is_mine = entry.get("uploader_id") == my_id
                is_pending = bool(entry.get("pending"))
                if is_mine:
                    if is_pending:
                        my_pending += 1
                    else:
                        if kind == "images":
                            my_images += 1
                        else:
                            my_audio += 1
                if is_pending:
                    pending_total += 1
    result = {
        "my_images": my_images,
        "my_audio": my_audio,
        "my_pending": my_pending,
        "role": user["role"],
    }
    if user["role"] == "admin":
        result["pending_total"] = pending_total
    return result


def _require_admin(authorization, token):
    user = authenticate(authorization, token)
    if user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Admin only")
    return user


@app.get("/api/admin/pending")
def admin_pending(
    token: str = "",
    authorization: str | None = Header(default=None),
) -> list[dict]:
    _require_admin(authorization, token)
    items: list[dict] = []
    for mp in sorted(SPECIES_DIR.glob("*/manifest.json")):
        try:
            m = json.loads(mp.read_text(encoding="utf-8"))
        except Exception:
            continue
        sci = m.get("sci", "")
        cn = m.get("cn", "")
        en = m.get("en", "")
        for kind in ("images", "audio"):
            for entry in m.get(kind, []):
                if entry.get("pending"):
                    items.append({
                        "sci": sci, "cn": cn, "en": en, "kind": kind,
                        "file": entry.get("file", ""),
                        "url": entry.get("url", ""),
                        "contributor": entry.get("contributor", ""),
                        "uploader_id": entry.get("uploader_id", ""),
                        "uploader_name": entry.get("uploader_name", ""),
                        "uploaded_at": entry.get("uploaded_at", 0),
                    })
    items.sort(key=lambda x: x.get("uploaded_at", 0), reverse=True)
    return items


@app.post("/api/admin/approve")
async def admin_approve(
    payload: dict = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    _require_admin(authorization, token)
    sci = str(payload.get("sci", "")).strip()
    file = str(payload.get("file", "")).strip()
    if not sci or not file:
        raise HTTPException(status_code=400, detail="Missing sci/file")
    key = species_key(sci)
    mp = SPECIES_DIR / key / "manifest.json"
    if not mp.exists():
        raise HTTPException(status_code=404, detail="Manifest not found")
    m = json.loads(mp.read_text(encoding="utf-8"))
    approved_at = int(time.time())
    found_kind = None
    for kind in ("images", "audio"):
        lst = m.get(kind, [])
        idx = next((i for i, e in enumerate(lst) if e.get("file") == file and e.get("pending")), -1)
        if idx >= 0:
            entry = lst.pop(idx)
            entry.pop("pending", None)
            entry["approved_at"] = approved_at
            # 置顶到数组第 0 位，但不动顶层 image/image_credit 主图字段
            lst.insert(0, entry)
            m[kind] = lst
            found_kind = kind
            break
    if not found_kind:
        raise HTTPException(status_code=404, detail="Pending entry not found")
    mp.write_text(json.dumps(m, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    update_index()
    return {"approved": True, "sci": sci, "file": file, "kind": found_kind}


@app.post("/api/admin/reject")
async def admin_reject(
    payload: dict = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    _require_admin(authorization, token)
    sci = str(payload.get("sci", "")).strip()
    file = str(payload.get("file", "")).strip()
    if not sci or not file:
        raise HTTPException(status_code=400, detail="Missing sci/file")
    key = species_key(sci)
    mp = SPECIES_DIR / key / "manifest.json"
    if not mp.exists():
        raise HTTPException(status_code=404, detail="Manifest not found")
    m = json.loads(mp.read_text(encoding="utf-8"))
    found = False
    for kind in ("images", "audio"):
        lst = m.get(kind, [])
        keep = []
        for e in lst:
            if e.get("file") == file and e.get("pending"):
                fp = SPECIES_DIR / key / e["file"]
                try:
                    if fp.exists():
                        fp.unlink()
                except Exception:
                    pass
                found = True
                continue
            keep.append(e)
        m[kind] = keep
    if not found:
        raise HTTPException(status_code=404, detail="Pending entry not found")
    mp.write_text(json.dumps(m, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    update_index()
    return {"rejected": True, "sci": sci, "file": file}


def _save_users(users: dict) -> None:
    USERS_FILE.write_text(
        json.dumps(users, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    try:
        USERS_FILE.chmod(0o600)
    except Exception:
        pass


def _gen_token(prefix: str = "beta") -> str:
    import secrets
    return f"{prefix}_{secrets.token_urlsafe(16)}"


@app.get("/api/admin/users")
def admin_list_users(
    token: str = "",
    authorization: str | None = Header(default=None),
) -> list[dict]:
    _require_admin(authorization, token)
    users = load_users()
    me_token = ""
    bearer = ""
    if authorization and authorization.lower().startswith("bearer "):
        bearer = authorization[7:].strip()
    me_token = (bearer or token or "").strip()
    out: list[dict] = []
    for tok, info in users.items():
        out.append({
            "token": tok,
            "id": info.get("id", ""),
            "role": info.get("role", "beta"),
            "name": info.get("name", ""),
            "is_self": tok == me_token,
        })
    out.sort(key=lambda x: (x["role"] != "admin", x["id"]))
    return out


@app.post("/api/admin/users")
async def admin_add_user(
    payload: dict = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    _require_admin(authorization, token)
    name = str(payload.get("name", "")).strip()
    user_id = str(payload.get("id", "")).strip()
    role = str(payload.get("role", "beta")).strip().lower()
    custom_token = str(payload.get("token", "")).strip()
    if not name:
        raise HTTPException(status_code=400, detail="name required")
    if role not in ("admin", "beta"):
        raise HTTPException(status_code=400, detail="role must be admin or beta")
    if not user_id:
        # generate id from name (sanitized) + suffix
        base = re.sub(r"[^A-Za-z0-9_-]+", "_", name) or "user"
        user_id = f"{base}_{int(time.time()) % 100000}"
    users = load_users()
    # uniqueness on id
    for existing_tok, existing_info in users.items():
        if existing_info.get("id") == user_id:
            raise HTTPException(status_code=409, detail="user id already exists")
    new_token = custom_token or _gen_token("admin" if role == "admin" else "beta")
    if new_token in users:
        raise HTTPException(status_code=409, detail="token already in use")
    users[new_token] = {"id": user_id, "role": role, "name": name}
    _save_users(users)
    return {"token": new_token, "id": user_id, "role": role, "name": name}


@app.delete("/api/admin/users")
async def admin_delete_user(
    payload: dict = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    me = _require_admin(authorization, token)
    target_token = str(payload.get("token", "")).strip()
    if not target_token:
        raise HTTPException(status_code=400, detail="token required")
    if target_token == me.get("token"):
        raise HTTPException(status_code=400, detail="cannot delete your own token")
    users = load_users()
    if target_token not in users:
        raise HTTPException(status_code=404, detail="user not found")
    removed = users.pop(target_token)
    _save_users(users)
    return {"deleted": True, "id": removed.get("id", "")}


@app.post("/api/set_image_difficulty")
async def set_image_difficulty(
    payload: dict = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    _require_admin(authorization, token)
    sci = str(payload.get("sci", "")).strip()
    file = str(payload.get("file", "")).strip()
    difficulty = int(payload.get("difficulty", 0))
    if not sci or not file:
        raise HTTPException(status_code=400, detail="Missing sci/file")
    if not (1 <= difficulty <= 5):
        raise HTTPException(status_code=400, detail="difficulty must be 1-5")
    key = species_key(sci)
    mp = SPECIES_DIR / key / "manifest.json"
    if not mp.exists():
        raise HTTPException(status_code=404, detail="Manifest not found")
    m = json.loads(mp.read_text(encoding="utf-8"))
    found = False
    for kind in ("images", "audio"):
        for entry in m.get(kind, []):
            if entry.get("file") == file:
                entry["difficulty"] = difficulty
                found = True
                break
        if found:
            break
    if not found:
        raise HTTPException(status_code=404, detail="File not found in manifest")
    mp.write_text(json.dumps(m, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {"saved": True, "sci": sci, "file": file, "difficulty": difficulty}

