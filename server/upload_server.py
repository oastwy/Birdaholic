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
import subprocess
import time
import secrets
import threading
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any

from fastapi import Body, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse


DATA_DIR = Path(os.environ.get("BIRDAHOLIC_DATA_DIR", "/data"))
SERVER_DIR = Path(os.environ.get("BIRDAHOLIC_SERVER_DIR", "/data/server"))
SPECIES_DIR = DATA_DIR / "species"
INDEX_DIR = DATA_DIR / "indexes"
WORLD_BIRDS_PATH = Path(
    os.environ.get("BIRDAHOLIC_WORLD_BIRDS", str(SERVER_DIR / "world_birds.json"))
)
try:
    from PIL import Image, ImageOps
    import pillow_heif

    pillow_heif.register_heif_opener()
    _PIL_OK = True
except Exception:
    _PIL_OK = False


UPLOAD_TOKEN = os.environ.get("BIRDAHOLIC_UPLOAD_TOKEN", "")
USERS_FILE = Path("/data/server/users.json")
FEEDBACK_FILE = Path("/data/server/feedback.json")
_feedback_lock = threading.Lock()

# ── 发现页运营内容（二维码 / 志愿招募 / 观鸟资讯）────────────────
DISCOVER_FILE = Path("/data/server/discover.json")
DISCOVER_DIR = DATA_DIR / "discover"  # 二维码等图片，nginx 经 /discover/ 提供

# ── 删除回收站 ─────────────────────────────────────────────────
TRASH_DIR = DATA_DIR / "trash"  # 删除的媒体先移到这里
TRASH_RETENTION_DAYS = 30  # 超过此天数自动清除
DELETE_LOG_FILE = Path("/data/server/delete_log.json")  # 删除/恢复历史
OPS_LOG_FILE = Path("/data/server/admin_ops.json")  # 统一管理操作日志
QUIZ_LOG_FILE = Path("/data/server/quiz_log.json")  # 识别测验出题日志（App 回传）
TOKEN_REQ_FILE = Path("/data/server/token_requests.json")  # 匿名上传权限申请队列
DISCOVER_PUBLIC_BASE = os.environ.get(
    "BIRDAHOLIC_DISCOVER_BASE", "https://birding.today/discover"
)
_discover_lock = threading.Lock()


def load_users() -> dict:
    if USERS_FILE.exists():
        try:
            return json.loads(USERS_FILE.read_text(encoding="utf-8"))
        except Exception:
            return {}
    return {}


PUBLIC_BASE_URL = os.environ.get(
    "BIRDAHOLIC_PUBLIC_BASE_URL", "http://your-server-ip:8080"
).rstrip("/")

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".heic"}
AUDIO_EXTS = {".mp3", ".m4a", ".aac", ".wav", ".flac", ".ogg"}
ALIASES = {
    "common chaffinch": "eurasian chaffinch",
}

app = FastAPI(title="Birdaholic Upload Server")


def species_key(scientific_name: str) -> str:
    key = "_".join(scientific_name.strip().split())
    # 防路径穿越：key 会被拼进 SPECIES_DIR/<key>/... 做 mkdir / read / write。
    # 合法学名不含 / \ 或 ..；拒绝可挡住 sci="../../x"、绝对路径等越界读写。
    # match_species 只对 world_birds（干净二名）调本函数，正常调用不会触发。
    if (
        not key
        or key in (".", "..")
        or key.startswith(".")
        or "/" in key
        or "\\" in key
        or ".." in key
    ):
        raise HTTPException(status_code=400, detail="Invalid species name")
    return key


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

# 预计算每个物种中文名的拼音首字母缩写(_pyi, 如 鹪鹩→jl)与全拼(_pyf, jiaoliao)，
# 供 /api/search 支持拼音搜索。pypinyin 不可用时静默跳过。
try:
    from pypinyin import lazy_pinyin, Style as _PyStyle

    def _compute_pinyin(text: str) -> tuple[str, str]:
        if not text:
            return "", ""
        try:
            initials = "".join(
                lazy_pinyin(text, style=_PyStyle.FIRST_LETTER, errors="ignore")
            ).lower()
            full = "".join(lazy_pinyin(text, errors="ignore")).lower()
            return initials, full
        except Exception:
            return "", ""

    for _item in WORLD_BIRDS:
        _zh = str(_item.get("zh", "")).strip()
        _item["_pyi"], _item["_pyf"] = _compute_pinyin(_zh)
except Exception:
    pass


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
        return {
            "id": "legacy_admin",
            "role": "admin",
            "name": "管理员",
            "token": provided,
        }
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


def _safe_manifest_file(value: str, expected_prefix: str) -> Path:
    rel = Path(value)
    if rel.is_absolute() or ".." in rel.parts or not value.startswith(expected_prefix):
        raise HTTPException(status_code=400, detail="Invalid file path")
    return rel


def try_generate_spectrogram(sci: str, audio_file: Path) -> dict[str, str]:
    """Best-effort spectrogram generation. Upload must succeed even if this fails."""
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return {}
    key = species_key(sci)
    out_dir = SPECIES_DIR / key / "audio_spectrograms"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_name = f"{audio_file.stem}.jpg"
    out_path = out_dir / out_name
    # The first pass removes common low-frequency rumble and high-frequency hiss
    # before showspectrumpic renders the FFT image.  Some ffmpeg builds lack
    # afftdn; fall back to a plain spectrogram so upload never fails.
    filter_chains = [
        (
            "aformat=channel_layouts=mono,"
            "highpass=f=120,"
            "lowpass=f=12000,"
            "afftdn=nf=-25,"
            "showspectrumpic=s=900x334:legend=disabled"
        ),
        "showspectrumpic=s=900x334:legend=disabled",
    ]
    generated = False
    for filter_chain in filter_chains:
        try:
            subprocess.run(
                [
                    ffmpeg,
                    "-y",
                    "-i",
                    str(audio_file),
                    "-lavfi",
                    filter_chain,
                    "-q:v",
                    "5",
                    str(out_path),
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=75,
                check=True,
            )
            generated = True
            break
        except Exception:
            continue
    if not generated:
        return {}
    return {
        "spectrogram": f"audio_spectrograms/{out_name}",
        "spectrogram_url": public_url(sci, "audio_spectrograms", out_name),
    }


def build_index_rows() -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for manifest_path in sorted(SPECIES_DIR.glob("*/manifest.json")):
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        sci = str(manifest.get("sci", "")).strip()
        world_item = WORLD_BY_SCI.get(sci.lower(), {})
        rows.append(
            {
                "sci": sci,
                # world_birds.json 是权威鸟种表，优先用它；manifest 里的名字是创建时的旧快照，
                # 仅当该 sci 不在 world_birds 时才回退。修复英文名空白/为中文、与 App 名字不一致。
                "cn": world_item.get("zh", "") or manifest.get("cn", ""),
                "en": world_item.get("en", "") or manifest.get("en", ""),
                "order": world_item.get("order", "") or manifest.get("order", ""),
                "family": world_item.get("family", "") or manifest.get("family", ""),
                "species_dir": manifest_path.parent.name,
                "manifest_url": f"{PUBLIC_BASE_URL}/species/{manifest_path.parent.name}/manifest.json",
                "image_count": sum(
                    1 for x in manifest.get("images", []) if not x.get("pending")
                ),
                "audio_count": sum(
                    1 for x in manifest.get("audio", []) if not x.get("pending")
                ),
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


@app.get("/admin")
def admin_page() -> FileResponse:
    html = SERVER_DIR / "admin.html"
    if not html.exists():
        raise HTTPException(status_code=404, detail="admin.html not found")
    return FileResponse(html)


@app.get("/admin/")
def admin_page_slash() -> RedirectResponse:
    return RedirectResponse(url="/admin", status_code=307)


@app.get("/api/search")
def search(q: str = "") -> list[dict[str, str]]:
    query = normalize_name(q)
    if not query:
        return []
    # 按匹配精确度排序后再截断，避免“鹪鹩”这种被一堆“XX鹪鹩”挤出。
    # rank: 0=某名字完全等于查询，1=以查询开头，2=名字包含，3=拼音包含。
    # 纯字母查询额外匹配中文名的拼音首字母(_pyi)与全拼(_pyf)，支持 jl / jiaoliao 搜鹪鹩。
    q_compact = query.replace(" ", "")
    is_alpha = bool(q_compact) and bool(re.fullmatch(r"[a-z]+", q_compact))
    scored: list[tuple[int, int, dict[str, Any]]] = []
    for idx, item in enumerate(WORLD_BIRDS):
        names = [normalize_name(n) for n in candidate_names(item)]
        rank = None
        for nn in names:
            if not nn:
                continue
            if nn == query:
                rank = 0
                break
            if nn.startswith(query):
                rank = 1 if rank is None else min(rank, 1)
            elif query in nn:
                rank = 2 if rank is None else min(rank, 2)
        if rank != 0 and is_alpha:
            for p in (item.get("_pyi", ""), item.get("_pyf", "")):
                if not p:
                    continue
                if p == q_compact:
                    rank = 0
                    break
                if p.startswith(q_compact):
                    rank = 1 if rank is None else min(rank, 1)
                elif q_compact in p:
                    rank = 3 if rank is None else min(rank, 3)
        if rank is not None:
            scored.append((rank, idx, item))
    scored.sort(key=lambda t: (t[0], t[1]))
    return [
        {
            "sci": item.get("sci", ""),
            "en": item.get("en", ""),
            "zh": item.get("zh", ""),
            "code": item.get("code", ""),
        }
        for _rank, _idx, item in scored[:300]
    ]


@app.get("/api/stats")
def stats(q: str = "") -> dict[str, Any]:
    rows = build_index_rows()
    query = normalize_name(q)
    if query:
        rows = [
            row
            for row in rows
            if query
            in normalize_name(
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
    features: str = Form(""),
    description: str = Form(""),
    media_type: str = Form(""),
    audio_type: str = Form(""),
    license: str = Form("CC BY-NC 4.0"),
    location: str = Form(""),
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    user = authenticate(authorization, token)
    SPECIES_DIR.mkdir(parents=True, exist_ok=True)
    is_admin = user["role"] == "admin"
    now_ts = int(time.time())
    loc = location.strip()[:200]

    # Clamp difficulty to [1, 5]; 0 means "not specified"
    if difficulty:
        difficulty = max(1, min(5, difficulty))

    # Single batch-level identification features applied to every file
    feat = features.strip()

    selected = None
    if sci.strip():
        selected = match_species(sci) or {"sci": sci.strip()}

    saved: list[dict[str, Any]] = []
    failed: list[dict[str, str]] = []

    for upload_file in files:
        kind = media_kind(upload_file.filename, upload_file.content_type or "")
        requested_kind = media_type.strip().lower()
        if requested_kind in {"image", "images"}:
            requested_kind = "images"
        elif requested_kind == "audio":
            requested_kind = "audio"
        else:
            requested_kind = ""
        if requested_kind and kind and requested_kind != kind:
            failed.append(
                {"file": upload_file.filename, "reason": "media type mismatch"}
            )
            continue
        if requested_kind and not kind:
            kind = requested_kind
        if kind is None:
            failed.append(
                {"file": upload_file.filename, "reason": "unsupported file type"}
            )
            continue

        item = selected or match_species(upload_file.filename)
        if not item or not item.get("sci"):
            failed.append(
                {"file": upload_file.filename, "reason": "species not recognized"}
            )
            continue

        target_sci = item["sci"]
        key = species_key(target_sci)
        target_dir = SPECIES_DIR / key / kind
        target_dir.mkdir(parents=True, exist_ok=True)
        filename = safe_filename(upload_file.filename)
        target = target_dir / filename
        with target.open("wb") as handle:
            shutil.copyfileobj(upload_file.file, handle)

        if kind == "images":
            final_path = _compress_image(target)
            filename = final_path.name
            target = final_path

        manifest = load_manifest(target_sci, item)
        # Note: per-photo difficulty is recorded on the entry below.
        # We intentionally do NOT touch manifest["difficulty"] here —
        # species-level difficulty is changed only via /api/set_difficulty.
        if kind == "images":
            entry = {
                "file": f"images/{filename}",
                "url": public_url(target_sci, "images", filename),
                "contributor": contributor.strip() or user.get("name", "用户上传"),
                "contributor_url": "",
                "source": "birdaholic-upload",
                "license": license.strip() or "CC BY-NC 4.0",
                "uploader_id": user["id"],
                "uploader_role": user["role"],
                "uploader_name": user.get("name", ""),
                "uploaded_at": now_ts,
            }
            if description.strip():
                entry["description"] = description.strip()
            if loc:
                entry["location"] = loc
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
            normalized_audio_type = audio_type.strip().lower()
            if normalized_audio_type not in {"song", "call"}:
                normalized_audio_type = (
                    "song" if "song" in upload_file.filename.lower() else "call"
                )
            entry = {
                "file": f"audio/{filename}",
                "url": public_url(target_sci, "audio", filename),
                "type": normalized_audio_type,
                "contributor": contributor.strip() or user.get("name", "用户上传"),
                "contributor_url": "",
                "source": "birdaholic-upload",
                "license": license.strip() or "CC BY-NC 4.0",
                "uploader_id": user["id"],
                "uploader_role": user["role"],
                "uploader_name": user.get("name", ""),
                "uploaded_at": now_ts,
            }
            if description.strip():
                entry["description"] = description.strip()
            if loc:
                entry["location"] = loc
            entry.update(try_generate_spectrogram(target_sci, target))
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
        saved.append(
            {
                "file": upload_file.filename,
                "sci": target_sci,
                "kind": kind,
                "entry": entry,
            }
        )

    update_index()
    if is_admin and saved:
        # 管理员上传即为非 pending，立刻计入致谢/评级队列；内测上传是 pending，两处都不计，无需失效
        _invalidate_contributors_cache()
        _invalidate_rate_queue_cache()
    if saved:
        _log_op(
            "上传媒体",
            user.get("id", ""),
            ", ".join(sorted({s["sci"] for s in saved}))[:120],
            f"{len(saved)} 个文件" + ("（待审核）" if not is_admin else ""),
        )
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
    # 仅管理员直接写物种难度；内测用户走 /api/rate/submit 进待审队列。
    _require_admin(authorization, token)
    sci = str(payload.get("sci", "")).strip()
    try:
        difficulty = int(payload.get("difficulty", 0))
    except (TypeError, ValueError):
        raise HTTPException(status_code=400, detail="difficulty must be 1-5")
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
    _invalidate_rate_queue_cache()
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


# ── 用户反馈 / 纠错 ───────────────────────────────────────────
def _resolve_user_soft(authorization, token) -> dict:
    """解析用户身份；token 无效或缺失时按匿名处理（反馈仍可提交）。"""
    try:
        return authenticate(authorization, token)
    except HTTPException:
        return {"id": "anon", "role": "anon", "name": "匿名用户", "token": ""}


def _load_feedback() -> list[dict]:
    if FEEDBACK_FILE.exists():
        try:
            data = json.loads(FEEDBACK_FILE.read_text(encoding="utf-8"))
            if isinstance(data, list):
                return data
        except Exception:
            pass
    return []


def _save_feedback(items: list[dict]) -> None:
    FEEDBACK_FILE.parent.mkdir(parents=True, exist_ok=True)
    FEEDBACK_FILE.write_text(
        json.dumps(items, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    try:
        FEEDBACK_FILE.chmod(0o600)
    except Exception:
        pass


@app.post("/api/feedback")
async def submit_feedback(
    payload: dict = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    user = _resolve_user_soft(authorization, token)
    message = str(payload.get("message", "")).strip()
    if not message:
        raise HTTPException(status_code=400, detail="Empty feedback")
    entry = {
        "id": secrets.token_urlsafe(9),
        "uploader_id": user.get("id", "anon"),
        "uploader_name": user.get("name", ""),
        "role": user.get("role", "anon"),
        "client_id": str(payload.get("client_id", "")).strip()[:80],
        "message": message[:4000],
        "page": str(payload.get("page", ""))[:200],
        "species_cn": str(payload.get("species_cn", ""))[:200],
        "species_sci": str(payload.get("species_sci", ""))[:200],
        "created_at": int(time.time()),
        "status": "open",
    }
    # 图片问题反馈：保留被举报图片的定位信息（哪张图 / 谁传的），
    # 供管理员核实后按 species_sci + image_file 反查并回达图片提交者。
    for _k in (
        "report_type",
        "image_url",
        "image_file",
        "image_source",
        "image_contributor",
        "image_contributor_url",
    ):
        _v = str(payload.get(_k, "")).strip()
        if _v:
            entry[_k] = _v[:500]
    with _feedback_lock:
        items = _load_feedback()
        items.append(entry)
        _save_feedback(items)
    return {"ok": True, "id": entry["id"]}


@app.get("/api/admin/feedback")
def admin_feedback(
    token: str = "",
    authorization: str | None = Header(default=None),
) -> list[dict]:
    _require_admin(authorization, token)
    # image_relay 是「回达提交者」生成的出站通知，不是收到的反馈，不进审核列表
    items = [
        it
        for it in _load_feedback()
        if it.get("kind") not in ("image_relay", "approve_notice")
    ]
    items.sort(key=lambda x: x.get("created_at", 0), reverse=True)
    return items


@app.post("/api/admin/feedback/resolve")
async def admin_feedback_resolve(
    payload: dict = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    _admin = _require_admin(authorization, token)
    fid = str(payload.get("id", "")).strip()
    if not fid:
        raise HTTPException(status_code=400, detail="Missing id")
    with _feedback_lock:
        items = _load_feedback()
        found = False
        for it in items:
            if it.get("id") == fid:
                it["status"] = "resolved"
                it["resolved_at"] = int(time.time())
                found = True
                break
        if not found:
            raise HTTPException(status_code=404, detail="Feedback not found")
        _save_feedback(items)
    _log_op("标记反馈已处理", _admin.get("id", ""), fid)
    return {"ok": True, "id": fid}


@app.post("/api/admin/feedback/reply")
async def admin_feedback_reply(
    payload: dict = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    admin = _require_admin(authorization, token)
    fid = str(payload.get("id", "")).strip()
    reply = str(payload.get("reply", "")).strip()
    if not fid:
        raise HTTPException(status_code=400, detail="Missing id")
    if not reply:
        raise HTTPException(status_code=400, detail="Empty reply")
    with _feedback_lock:
        items = _load_feedback()
        target = None
        for it in items:
            if it.get("id") == fid:
                it["reply"] = reply[:2000]
                it["replied_at"] = int(time.time())
                it["replied_by"] = admin.get("name") or admin.get("id", "")
                it["status"] = "resolved"
                it.setdefault("resolved_at", int(time.time()))
                target = it
                break
        if target is None:
            raise HTTPException(status_code=404, detail="Feedback not found")
        _save_feedback(items)
    _log_op("回复反馈", admin.get("id", ""), fid, reply[:80])
    return {"ok": True, "id": fid, "reply": reply}


@app.get("/api/feedback/replies")
def feedback_replies(
    token: str = "",
    client_id: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    """供 App 端拉取：当前用户收到的纠错回复。
    有 token 的用户按 uploader_id 匹配；匿名用户按本机 client_id 匹配（同机可收回复）。"""
    user = _resolve_user_soft(authorization, token)
    uid = user.get("id", "")
    cid = (client_id or "").strip()
    out = []
    for it in _load_feedback():
        if not it.get("reply"):
            continue
        match = (uid and uid != "anon" and it.get("uploader_id") == uid) or (
            cid and it.get("client_id") == cid
        )
        if match:
            out.append(
                {
                    "id": it.get("id"),
                    "message": it.get("message", ""),
                    "reply": it.get("reply", ""),
                    "replied_at": it.get("replied_at"),
                    "species_cn": it.get("species_cn", ""),
                    "species_sci": it.get("species_sci", ""),
                }
            )
    return {"items": out}


def _notify_upload_approved(
    entry: dict, sci: str, cn: str, file: str, kind: str
) -> None:
    """审核通过后给上传者发「已过审」通知：复用 feedback replies 机制下发（App 端「反馈
    与通知」按 uploader_id + reply 即可收到），不暴露任何第三方、单向、无互动——守去社交。
    只对真·App 用户上传（source==birdaholic-upload、有 uploader_id）发；iNat/补图/占位图不发。"""
    uid = str(entry.get("uploader_id", "")).strip()
    if not uid or uid == "anon" or entry.get("source") != "birdaholic-upload":
        return
    label = (cn or sci or "").strip()
    what = "鸟鸣" if kind == "audio" else "图片"
    now = int(time.time())
    notice = {
        "id": secrets.token_urlsafe(9),
        "uploader_id": uid,
        "uploader_name": str(entry.get("contributor", "")).strip(),
        "role": "user",
        "client_id": "",
        "message": f"你上传的「{label}」{what}审核结果",
        "reply": f"你上传的「{label}」{what}已通过审核、已收录，感谢你的分享！",
        "page": "上传审核通知",
        "species_cn": cn,
        "species_sci": sci,
        "image_file": file,
        "kind": "approve_notice",
        "replied_at": now,
        "created_at": now,
        "status": "resolved",
        "resolved_at": now,
    }
    with _feedback_lock:
        items = _load_feedback()
        # 同一上传者+同一文件的旧审核通知先移除，避免删/恢复反复审核刷出重复通知
        items = [
            it
            for it in items
            if not (
                it.get("kind") == "approve_notice"
                and it.get("uploader_id") == uid
                and it.get("image_file") == file
            )
        ]
        items.append(notice)
        _save_feedback(items)


def _resolve_image_uploader(species_sci: str, image_file: str, image_url: str) -> dict:
    """按 sci + 图文件名在 manifest 里反查那张图的上传者。
    只有 App 用户上传图（source==birdaholic-upload）才有真实 uploader_id 可回达；
    iNat / Wikimedia / 占位图返回空。"""
    if not species_sci:
        return {}
    try:
        manifest = load_manifest(species_sci)
    except Exception:
        return {}

    def _base(p: str) -> str:
        return (p or "").rsplit("/", 1)[-1].strip().lower()

    want_file = (image_file or "").strip().lower()
    want_base = _base(image_file) or _base(image_url)
    for img in manifest.get("images", []):
        if img.get("pending"):
            continue  # 未过审图不回达（其提交者身份尚不该被据此触达）
        f = str(img.get("file", "")).strip().lower()
        u = str(img.get("url", "")).strip()
        if not f:
            continue
        # 优先精确文件名匹配；basename 仅作兜底（文件名带毫秒前缀，基本唯一）。
        if (want_file and f == want_file) or (
            want_base and (_base(f) == want_base or _base(u) == want_base)
        ):
            return {
                "uploader_id": str(img.get("uploader_id", "")).strip(),
                "uploader_name": str(
                    img.get("uploader_name", "") or img.get("contributor", "")
                ).strip(),
                "source": str(img.get("source", "")).strip(),
            }
    return {}


@app.post("/api/admin/feedback/relay")
async def admin_feedback_relay(
    payload: dict = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    """把某条图片反馈核实后回达给图片提交者（仅 App 用户上传图）。
    生成一条新的、定向给提交者 uploader_id 的通知记录（带 reply，
    供 /api/feedback/replies 下发），不暴露举报者身份。"""
    admin = _require_admin(authorization, token)
    fid = str(payload.get("id", "")).strip()
    message = str(payload.get("message", "")).strip()
    if not fid:
        raise HTTPException(status_code=400, detail="Missing id")
    if not message:
        raise HTTPException(status_code=400, detail="Empty message")
    with _feedback_lock:
        items = _load_feedback()
        src = next((it for it in items if it.get("id") == fid), None)
        if src is None:
            raise HTTPException(status_code=404, detail="Feedback not found")
        info = _resolve_image_uploader(
            src.get("species_sci", ""),
            src.get("image_file", ""),
            src.get("image_url", ""),
        )
        sub_uid = info.get("uploader_id", "")
        if (
            not sub_uid
            or sub_uid == "anon"
            or info.get("source") != "birdaholic-upload"
        ):
            return {"ok": False, "reason": "no_app_submitter"}
        now = int(time.time())
        notice = {
            "id": secrets.token_urlsafe(9),
            "uploader_id": sub_uid,  # 收件人 = 图片提交者
            "uploader_name": info.get("uploader_name", ""),
            "role": "user",
            "client_id": "",
            "message": f"关于你上传的「{src.get('species_cn', '')}」图片的反馈",
            "page": "图片提交者通知",
            "species_cn": src.get("species_cn", ""),
            "species_sci": src.get("species_sci", ""),
            "image_file": src.get("image_file", ""),
            "image_url": src.get("image_url", ""),
            "kind": "image_relay",
            "source_feedback_id": fid,
            "reply": message[:2000],  # 有 reply → replies 接口会下发
            "replied_at": now,
            "replied_by": admin.get("name") or admin.get("id", ""),
            "created_at": now,
            "status": "resolved",
            "resolved_at": now,
        }
        # 同一条反馈重复回达：先移除该反馈的旧通知，避免提交者收到重复
        # （src 自身无 source_feedback_id，过滤后仍在列表里，可继续 mutate）
        items = [it for it in items if it.get("source_feedback_id") != fid]
        items.append(notice)
        src["relayed_to"] = sub_uid
        src["relayed_at"] = now
        _save_feedback(items)
    _log_op("回达图片提交者", admin.get("id", ""), fid, message[:80])
    return {"ok": True, "id": notice["id"], "uploader_id": sub_uid}


# ── 匿名上传权限申请（App 不需注册，本机 client_id 提交，管理员审核发 token）──
_token_req_lock = threading.Lock()


def _load_token_reqs() -> list[dict]:
    try:
        data = json.loads(TOKEN_REQ_FILE.read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []
    except Exception:
        return []


def _save_token_reqs(items: list[dict]) -> None:
    try:
        TOKEN_REQ_FILE.write_text(
            json.dumps(items, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        TOKEN_REQ_FILE.chmod(0o600)
    except Exception:
        pass


def _token_req_public(rec: dict) -> dict:
    """只回 App 端 status + token（approved 才带 token）。"""
    approved = rec.get("status") == "approved"
    return {
        "status": rec.get("status", "pending"),
        "token": rec.get("token", "") if approved else "",
    }


@app.post("/api/token_requests")
def submit_token_request(payload: dict = Body(...)) -> dict:
    client_id = str(payload.get("client_id", "")).strip()[:80]
    if not client_id:
        raise HTTPException(status_code=400, detail="Missing client_id")
    now = int(time.time())
    with _token_req_lock:
        items = _load_token_reqs()
        rec = next((r for r in items if r.get("client_id") == client_id), None)
        if rec is None:
            rec = {
                "client_id": client_id,
                "note": str(payload.get("note", ""))[:500],
                "platform": str(payload.get("platform", ""))[:40],
                "app_version": str(payload.get("app_version", ""))[:40],
                "app_build": str(payload.get("app_build", ""))[:40],
                "status": "pending",
                "token": "",
                "created_at": now,
                "updated_at": now,
            }
            items.append(rec)
        else:
            # 已批准的保持不变；否则（none/rejected/pending）重新置为 pending 并刷新信息
            if rec.get("status") != "approved":
                rec["status"] = "pending"
                rec["note"] = str(payload.get("note", rec.get("note", "")))[:500]
                rec["platform"] = str(payload.get("platform", rec.get("platform", "")))[
                    :40
                ]
                rec["app_version"] = str(
                    payload.get("app_version", rec.get("app_version", ""))
                )[:40]
                rec["app_build"] = str(
                    payload.get("app_build", rec.get("app_build", ""))
                )[:40]
            rec["updated_at"] = now
        _save_token_reqs(items)
    return _token_req_public(rec)


@app.get("/api/token_requests/status")
def token_request_status(client_id: str = "") -> dict:
    cid = (client_id or "").strip()
    if not cid:
        return {"status": "none", "token": ""}
    rec = next((r for r in _load_token_reqs() if r.get("client_id") == cid), None)
    return _token_req_public(rec) if rec else {"status": "none", "token": ""}


@app.get("/api/admin/token_requests")
def admin_list_token_requests(
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    _require_admin(authorization, token)
    items = sorted(
        _load_token_reqs(), key=lambda r: r.get("created_at", 0), reverse=True
    )
    return {"items": items}


# ── 逐种评级（admin）：给中国鸟逐种逐图打「物种难度 / 图片质量难度」 ──────────
_CHINA_BIRDS_CACHE: list[dict[str, Any]] | None = None


def _load_china_birds() -> list[dict[str, Any]]:
    """中国鸟名录（~1490 种）。文件与 upload_server.py 同目录（/data/server/china_birds.json）。"""
    global _CHINA_BIRDS_CACHE
    if _CHINA_BIRDS_CACHE is None:
        p = Path(__file__).resolve().parent / "china_birds.json"
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
            _CHINA_BIRDS_CACHE = data if isinstance(data, list) else []
        except Exception:
            _CHINA_BIRDS_CACHE = []
    return _CHINA_BIRDS_CACHE


# 评级队列缓存：admin 评级页用，要扫 ~1490 个 manifest。60s TTL + 评级写操作即时失效，
# 既省重复扫描，又保证评级后刷新能立刻看到最新「已评」进度。
_RATE_QUEUE_CACHE: dict[str, Any] | None = None
_RATE_QUEUE_CACHE_TS: float = 0.0
_RATE_QUEUE_CACHE_TTL = 60  # 秒
_RATE_QUEUE_CACHE_LOCK = (
    threading.Lock()
)  # 单飞：失效后只让一个线程扫 ~1490 manifest，余者复用


def _invalidate_rate_queue_cache() -> None:
    """set_difficulty / set_image_difficulty / _apply_rating 等评级写操作后调用。"""
    global _RATE_QUEUE_CACHE
    _RATE_QUEUE_CACHE = None


def _compute_rate_queue() -> dict[str, Any]:
    items: list[dict[str, Any]] = []
    for s in _load_china_birds():
        sci = str(s.get("sci", "")).strip()
        if not sci:
            continue
        world = WORLD_BY_SCI.get(sci.lower(), {})
        try:
            key = species_key(sci)
        except HTTPException:
            continue  # china_birds.json 里个别异常 sci 跳过，别让坏一条 500 掉整个评级队列
        mp = SPECIES_DIR / key / "manifest.json"
        has_manifest = mp.exists()  # 只 stat 一次，下面复用
        species_diff = 0
        species_rated = False
        img_count = 0
        img_rated = 0
        if has_manifest:
            try:
                m = json.loads(mp.read_text(encoding="utf-8"))
            except Exception:
                m = {}
            species_rated = "difficulty" in m
            species_diff = int(m.get("difficulty", 0) or 0)
            for x in m.get("images", []):
                if (
                    x.get("pending")
                    or x.get("placeholder")
                    or x.get("source") == "placeholder"
                ):
                    continue
                img_count += 1
                if "difficulty" in x:
                    img_rated += 1
        items.append(
            {
                "sci": sci,
                "zh": (s.get("zh") or world.get("zh") or s.get("cn") or "").strip(),
                "en": (s.get("en") or world.get("en") or "").strip(),
                "order": (s.get("order") or world.get("order") or "").strip(),
                "family": (s.get("family") or world.get("family") or "").strip(),
                "key": key,
                "has_manifest": has_manifest,
                "species_difficulty": species_diff,
                "species_rated": species_rated,
                "image_count": img_count,
                "image_rated": img_rated,
            }
        )
    rated = sum(1 for x in items if x["species_rated"])
    return {"items": items, "total": len(items), "rated": rated}


@app.get("/api/admin/rate/queue")
def admin_rate_queue(
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    """返回中国鸟评级队列：每种的已评状态 + 图片数。图片明细由前端按需拉 manifest。
    带 60s TTL 缓存（评级写操作即时失效）——该接口要扫 ~1490 个 manifest。"""
    _require_admin(authorization, token)
    global _RATE_QUEUE_CACHE, _RATE_QUEUE_CACHE_TS
    now = time.time()
    cache = _RATE_QUEUE_CACHE
    if cache is None or (now - _RATE_QUEUE_CACHE_TS) > _RATE_QUEUE_CACHE_TTL:
        # 单飞 + 双检：失效后只让一个线程扫 ~1490 manifest，其余并发请求复用结果，
        # 避免过期瞬间多请求各自重复全量扫描、把同步线程池占满。
        with _RATE_QUEUE_CACHE_LOCK:
            cache = _RATE_QUEUE_CACHE
            if (
                cache is None
                or (time.time() - _RATE_QUEUE_CACHE_TS) > _RATE_QUEUE_CACHE_TTL
            ):
                cache = _compute_rate_queue()
                _RATE_QUEUE_CACHE = cache
                _RATE_QUEUE_CACHE_TS = time.time()
    return cache


# ── 逐种评级提交 / 待审 / 审核（管理员直接生效，内测进待审队列）──────────
_PENDING_RATINGS_PATH = Path(__file__).resolve().parent / "pending_ratings.json"
_pending_ratings_lock = threading.Lock()


def _load_pending_ratings() -> list[dict[str, Any]]:
    try:
        data = json.loads(_PENDING_RATINGS_PATH.read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []
    except Exception:
        return []


def _save_pending_ratings(items: list[dict[str, Any]]) -> None:
    _PENDING_RATINGS_PATH.write_text(
        json.dumps(items, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def _apply_rating(sci: str, file: str, difficulty: int) -> None:
    """把一条评级写进 manifest：file 为空=物种难度；否则=该图质量难度。"""
    key = species_key(sci)
    mp = SPECIES_DIR / key / "manifest.json"
    if not file:
        item = match_species(sci) or {"sci": sci}
        (SPECIES_DIR / key).mkdir(parents=True, exist_ok=True)
        manifest = load_manifest(sci, item)
        manifest["difficulty"] = difficulty
        mp.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    else:
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
        mp.write_text(
            json.dumps(m, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    update_index()
    _invalidate_rate_queue_cache()


@app.post("/api/rate/submit")
async def rate_submit(
    payload: dict[str, Any] = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    """评级提交：管理员直接写入 manifest；内测用户进待审队列等管理员审核。"""
    user = authenticate(authorization, token)
    sci = str(payload.get("sci", "")).strip()
    file = str(payload.get("file", "")).strip()
    try:
        difficulty = int(payload.get("difficulty", 0))
    except (TypeError, ValueError):
        raise HTTPException(status_code=400, detail="difficulty must be 1-5")
    if not sci:
        raise HTTPException(status_code=400, detail="Missing sci")
    if not (1 <= difficulty <= 5):
        raise HTTPException(status_code=400, detail="difficulty must be 1-5")
    if user["role"] == "admin":
        _apply_rating(sci, file, difficulty)
        return {"applied": True, "pending": False}
    rec = {
        "id": secrets.token_hex(6),
        "sci": sci,
        "zh": str(payload.get("zh", "")).strip(),
        "file": file,
        "kind": "image" if file else "species",
        "difficulty": difficulty,
        "contributor": user.get("name", "") or user.get("id", ""),
        "uploader_id": user.get("id", ""),
        "ts": int(time.time()),
    }
    with _pending_ratings_lock:
        items = _load_pending_ratings()
        # 同一用户对同一目标的重复提交：覆盖旧的
        items = [
            r
            for r in items
            if not (
                r.get("uploader_id") == rec["uploader_id"]
                and r.get("sci") == sci
                and r.get("file") == file
            )
        ]
        items.append(rec)
        _save_pending_ratings(items)
    return {"applied": False, "pending": True}


@app.get("/api/admin/rate/pending")
def admin_rate_pending(
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    _require_admin(authorization, token)
    with _pending_ratings_lock:
        items = _load_pending_ratings()
    items = sorted(items, key=lambda r: r.get("ts", 0), reverse=True)
    return {"items": items, "total": len(items)}


@app.post("/api/admin/rate/resolve")
async def admin_rate_resolve(
    payload: dict[str, Any] = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    _require_admin(authorization, token)
    rid = str(payload.get("id", "")).strip()
    approve = bool(payload.get("approve", False))
    if not rid:
        raise HTTPException(status_code=400, detail="Missing id")
    # 先在锁内取出并移除待审记录（避免重复审核），再到锁外执行重活 _apply_rating
    # （它会 update_index() 全量扫盘）。这样：① 不在持锁时跑慢扫描阻塞其它待审操作；
    # ② 即便 _apply_rating 因目标图已被删而抛 404，记录也已移除、不会永远卡在队列里。
    with _pending_ratings_lock:
        items = _load_pending_ratings()
        rec = next((r for r in items if r.get("id") == rid), None)
        if rec is None:
            raise HTTPException(status_code=404, detail="评级不存在")
    applied = False
    apply_error = ""
    if approve:
        # 锁外执行重活 _apply_rating（含 update_index 全量扫盘）。成功、或目标已被删
        # (HTTPException) 才往下移除记录；其它异常（磁盘满 / manifest JSON 损坏等）直接
        # 抛出 → 记录保留、可重试，不丢数据。（这正是「先删后应用」会引入的数据丢失点。）
        try:
            _apply_rating(
                str(rec.get("sci", "")),
                str(rec.get("file", "")),
                int(rec.get("difficulty", 1)),
            )
            applied = True
        except HTTPException as exc:
            apply_error = str(exc.detail)  # 目标在提交后被删：记录无意义，照常出队
    # reject、approve 成功、或 approve 但目标已删——都把记录出队（非 HTTPException 已在上面抛出）。
    with _pending_ratings_lock:
        items = _load_pending_ratings()
        items = [r for r in items if r.get("id") != rid]
        _save_pending_ratings(items)
    return {
        "resolved": True,
        "approved": approve,
        "applied": applied,
        "error": apply_error,
    }


@app.post("/api/admin/token_requests/approve")
async def admin_approve_token_request(
    payload: dict = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    admin = _require_admin(authorization, token)
    client_id = str(payload.get("client_id", "")).strip()
    if not client_id:
        raise HTTPException(status_code=400, detail="Missing client_id")
    name = str(payload.get("name", "")).strip() or f"用户_{client_id[:6]}"
    with _token_req_lock:
        items = _load_token_reqs()
        rec = next((r for r in items if r.get("client_id") == client_id), None)
        if rec is None:
            raise HTTPException(status_code=404, detail="申请不存在")
        if rec.get("status") != "approved" or not rec.get("token"):
            new_token = _gen_token("beta")
            users = load_users()
            uid = f"u_{client_id[:8]}_{int(time.time()) % 10000}"
            users[new_token] = {"id": uid, "role": "beta", "name": name}
            _save_users(users)
            rec["token"] = new_token
            rec["user_id"] = uid
        rec["status"] = "approved"
        rec["name"] = name
        rec["decided_at"] = int(time.time())
        rec["decided_by"] = admin.get("id", "")
        _save_token_reqs(items)
    _log_op("批准上传权限", admin.get("id", ""), client_id, name)
    return {"ok": True, "client_id": client_id, "token": rec["token"]}


@app.post("/api/admin/token_requests/reject")
async def admin_reject_token_request(
    payload: dict = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    admin = _require_admin(authorization, token)
    client_id = str(payload.get("client_id", "")).strip()
    if not client_id:
        raise HTTPException(status_code=400, detail="Missing client_id")
    with _token_req_lock:
        items = _load_token_reqs()
        rec = next((r for r in items if r.get("client_id") == client_id), None)
        if rec is None:
            raise HTTPException(status_code=404, detail="申请不存在")
        rec["status"] = "rejected"
        rec["reason"] = str(payload.get("reason", ""))[:200]
        rec["decided_at"] = int(time.time())
        rec["decided_by"] = admin.get("id", "")
        _save_token_reqs(items)
    _log_op("拒绝上传权限", admin.get("id", ""), client_id, rec.get("reason", ""))
    return {"ok": True, "client_id": client_id}


# ── 发现页运营内容 ───────────────────────────────────────────
def _default_discover() -> dict:
    return {"groupQr": {"imageUrl": "", "updatedAt": ""}, "volunteers": [], "news": []}


def _load_discover() -> dict:
    if DISCOVER_FILE.exists():
        try:
            data = json.loads(DISCOVER_FILE.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                base = _default_discover()
                base.update({k: data.get(k, base[k]) for k in base})
                return base
        except Exception:
            pass
    return _default_discover()


def _save_discover(data: dict) -> None:
    DISCOVER_FILE.parent.mkdir(parents=True, exist_ok=True)
    DISCOVER_FILE.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def _sanitize_discover(payload: dict) -> dict:
    """只保留已知字段，避免后台误传脏数据。"""
    out = _default_discover()
    qr = payload.get("groupQr") or {}
    if isinstance(qr, dict):
        out["groupQr"] = {
            "imageUrl": str(qr.get("imageUrl", ""))[:500],
            "updatedAt": str(qr.get("updatedAt", ""))[:40],
        }
    for v in (payload.get("volunteers") or [])[:50]:
        if not isinstance(v, dict):
            continue
        out["volunteers"].append(
            {
                "id": str(v.get("id", "") or secrets.token_urlsafe(6))[:40],
                "title": str(v.get("title", ""))[:200],
                "org": str(v.get("org", ""))[:120],
                "date": str(v.get("date", ""))[:60],
                "url": str(v.get("url", ""))[:500],
                "status": (
                    "expired" if str(v.get("status", "")) == "expired" else "active"
                ),
            }
        )
    for n in (payload.get("news") or [])[:100]:
        if not isinstance(n, dict):
            continue
        out["news"].append(
            {
                "id": str(n.get("id", "") or secrets.token_urlsafe(6))[:40],
                "title": str(n.get("title", ""))[:200],
                "summary": str(n.get("summary", ""))[:600],
                "url": str(n.get("url", ""))[:500],
                "category": str(n.get("category", ""))[:40],
                "date": str(n.get("date", ""))[:60],
                "status": (
                    "expired" if str(n.get("status", "")) == "expired" else "active"
                ),
            }
        )
    return out


@app.get("/api/discover")
def get_discover() -> dict:
    """公开：发现页运营内容（App 自行过滤 status==active）。"""
    return _load_discover()


@app.post("/api/discover")
async def set_discover(
    payload: dict = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    _require_admin(authorization, token)
    cleaned = _sanitize_discover(payload)
    with _discover_lock:
        # 保留已有二维码（后台只改文字时不必重传图）
        if not cleaned["groupQr"]["imageUrl"]:
            cleaned["groupQr"] = _load_discover().get("groupQr", cleaned["groupQr"])
        _save_discover(cleaned)
    return {"ok": True}


@app.post("/api/discover/qr")
async def set_discover_qr(
    file: UploadFile = File(...),
    token: str = Form(""),
    authorization: str | None = Header(default=None),
) -> dict:
    _require_admin(authorization, token)
    if media_kind(file.filename, file.content_type or "") != "images":
        raise HTTPException(status_code=400, detail="请上传图片")
    DISCOVER_DIR.mkdir(parents=True, exist_ok=True)
    ext = Path(file.filename or "qr.jpg").suffix.lower() or ".jpg"
    target = DISCOVER_DIR / f"group_qr_{int(time.time())}{ext}"
    with target.open("wb") as handle:
        shutil.copyfileobj(file.file, handle)
    final = _compress_image(target, max_side=1200, target_kb=400)
    url = f"{DISCOVER_PUBLIC_BASE}/{final.name}"
    with _discover_lock:
        data = _load_discover()
        data["groupQr"] = {"imageUrl": url, "updatedAt": str(int(time.time()))}
        _save_discover(data)
    return {"ok": True, "imageUrl": url}


@app.get("/admin/discover")
def admin_discover_page() -> FileResponse:
    html = SERVER_DIR / "discover_admin.html"
    if not html.exists():
        raise HTTPException(status_code=404, detail="discover_admin.html not found")
    return FileResponse(html)


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
                    items.append(
                        {
                            "sci": sci,
                            "cn": cn,
                            "en": en,
                            "kind": kind,
                            "file": entry.get("file", ""),
                            "url": entry.get("url", ""),
                            "contributor": entry.get("contributor", ""),
                            "suggested_difficulty": entry.get(
                                "suggested_difficulty", 0
                            ),
                            "uploader_id": entry.get("uploader_id", ""),
                            "uploader_name": entry.get("uploader_name", ""),
                            "uploaded_at": entry.get("uploaded_at", 0),
                        }
                    )
    items.sort(key=lambda x: x.get("uploaded_at", 0), reverse=True)
    return items


@app.post("/api/admin/approve")
async def admin_approve(
    payload: dict = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    admin = _require_admin(authorization, token)
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
        idx = next(
            (
                i
                for i, e in enumerate(lst)
                if e.get("file") == file and e.get("pending")
            ),
            -1,
        )
        if idx >= 0:
            entry = lst.pop(idx)
            entry.pop("pending", None)
            suggested = entry.pop("suggested_difficulty", None)
            if suggested and not entry.get("difficulty"):
                try:
                    entry["difficulty"] = max(1, min(5, int(suggested)))
                except Exception:
                    pass
            entry["approved_at"] = approved_at
            # 置顶到数组第 0 位，但不动顶层 image/image_credit 主图字段
            lst.insert(0, entry)
            m[kind] = lst
            found_kind = kind
            break
    if not found_kind:
        raise HTTPException(status_code=404, detail="Pending entry not found")
    # 物种重新有了正式（非 pending）图片后，解除补图审核标记
    if sum(1 for e in m.get("images", []) if not e.get("pending")) > 0:
        m.pop("backfill_review", None)
    mp.write_text(json.dumps(m, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    update_index()
    _invalidate_contributors_cache()  # 新通过的用户图会进致谢，刷新缓存
    _invalidate_rate_queue_cache()  # 通过后该图计入 image_count，刷新评级队列
    # 审核通过后给真·App 上传者发「已过审」通知（纯服务器，App「反馈与通知」自动收到）
    _notify_upload_approved(entry, sci, m.get("cn", ""), file, found_kind)
    _log_op("通过审核", admin.get("id", ""), f"{sci} / {file}", found_kind or "")
    return {
        "approved": True,
        "sci": sci,
        "file": file,
        "kind": found_kind,
        "entry": entry,
    }


@app.post("/api/admin/reject")
async def admin_reject(
    payload: dict = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    admin = _require_admin(authorization, token)
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
    _log_op("拒绝审核", admin.get("id", ""), f"{sci} / {file}")
    return {"rejected": True, "sci": sci, "file": file}


# ── 回收站 / 删除历史 工具 ────────────────────────────────────
def _purge_trash(retention_days: int = TRASH_RETENTION_DAYS) -> int:
    """清除回收站中超过保留期的条目，返回清除数量。"""
    if not TRASH_DIR.exists():
        return 0
    cutoff = time.time() - retention_days * 86400
    purged = 0
    for entry_dir in TRASH_DIR.iterdir():
        if not entry_dir.is_dir():
            continue
        deleted_at = 0.0
        try:
            meta = json.loads((entry_dir / "meta.json").read_text(encoding="utf-8"))
            deleted_at = float(meta.get("deleted_at", 0))
        except Exception:
            try:
                deleted_at = entry_dir.stat().st_mtime
            except Exception:
                deleted_at = 0.0
        if deleted_at and deleted_at < cutoff:
            try:
                shutil.rmtree(entry_dir)
                purged += 1
            except Exception:
                pass
    return purged


def _read_trash_entries() -> list[dict[str, Any]]:
    _purge_trash()
    out: list[dict[str, Any]] = []
    if not TRASH_DIR.exists():
        return out
    for entry_dir in sorted(TRASH_DIR.iterdir(), key=lambda p: p.name, reverse=True):
        if not entry_dir.is_dir():
            continue
        try:
            out.append(
                json.loads((entry_dir / "meta.json").read_text(encoding="utf-8"))
            )
        except Exception:
            continue
    return out


def _append_delete_log(record: dict[str, Any]) -> None:
    """把删除/恢复事件追加到历史日志（最多保留近 2000 条）。"""
    try:
        log = json.loads(DELETE_LOG_FILE.read_text(encoding="utf-8"))
        if not isinstance(log, list):
            log = []
    except Exception:
        log = []
    log.append(record)
    log = log[-2000:]
    try:
        DELETE_LOG_FILE.write_text(
            json.dumps(log, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    except Exception:
        pass


def _log_op(action: str, by: str, target: str = "", note: str = "") -> None:
    """统一管理操作日志（审核/上传/删除/恢复/反馈/密钥等），最多保留近 3000 条。"""
    try:
        log = json.loads(OPS_LOG_FILE.read_text(encoding="utf-8"))
        if not isinstance(log, list):
            log = []
    except Exception:
        log = []
    log.append(
        {
            "at": int(time.time()),
            "action": action,
            "by": by or "",
            "target": target,
            "note": note,
        }
    )
    log = log[-3000:]
    try:
        OPS_LOG_FILE.write_text(
            json.dumps(log, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    except Exception:
        pass


@app.delete("/api/admin/media")
async def admin_delete_media(
    payload: dict = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    admin = _require_admin(authorization, token)
    sci = str(payload.get("sci", "")).strip()
    kind = str(payload.get("kind", "")).strip()
    file = str(payload.get("file", "")).strip()
    if not sci or not kind or not file:
        raise HTTPException(status_code=400, detail="Missing sci/kind/file")
    if kind not in ("images", "audio"):
        raise HTTPException(status_code=400, detail="kind must be images or audio")

    prefix = "images/" if kind == "images" else "audio/"
    rel = _safe_manifest_file(file, prefix)
    key = species_key(sci)
    mp = SPECIES_DIR / key / "manifest.json"
    if not mp.exists():
        raise HTTPException(status_code=404, detail="Manifest not found")
    m = json.loads(mp.read_text(encoding="utf-8"))

    removed: dict[str, Any] | None = None
    kept = []
    for entry in m.get(kind, []):
        if entry.get("file") == file and removed is None:
            removed = entry
            continue
        kept.append(entry)
    if removed is None:
        raise HTTPException(status_code=404, detail="Media entry not found")
    m[kind] = kept
    was_cover = bool(kind == "images" and m.get("image") == file)

    # 不直接删除，移入回收站，保留 30 天可恢复
    _purge_trash()
    trash_id = time.strftime("%Y%m%d-%H%M%S") + "-" + secrets.token_urlsafe(4)
    entry_dir = TRASH_DIR / trash_id
    entry_dir.mkdir(parents=True, exist_ok=True)
    stored_files: list[dict[str, str]] = []
    for field in ("file", "spectrogram"):
        rel_value = str(removed.get(field, "")).strip()
        if not rel_value:
            continue
        expected = prefix if field == "file" else "audio_spectrograms/"
        try:
            rel_path = _safe_manifest_file(rel_value, expected)
        except HTTPException:
            continue
        src = SPECIES_DIR / key / rel_path
        if not src.exists():
            continue
        dest = entry_dir / rel_path.name
        try:
            shutil.move(str(src), str(dest))
            stored_files.append(
                {"field": field, "rel": str(rel_path), "stored": dest.name}
            )
        except Exception:
            pass

    deleted_at = time.time()
    meta = {
        "trash_id": trash_id,
        "sci": sci,
        "key": key,
        "kind": kind,
        "file": file,
        "entry": removed,
        "stored_files": stored_files,
        "was_cover": was_cover,
        "deleted_by": admin.get("id", ""),
        "deleted_at": deleted_at,
    }
    (entry_dir / "meta.json").write_text(
        json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    if kind == "images" and m.get("image") == file:
        next_image = next(
            (e for e in m.get("images", []) if not e.get("pending")), None
        )
        if next_image:
            m["image"] = next_image.get("file", "")
            m["image_credit"] = next_image.get("credit") or next_image.get(
                "contributor", ""
            )
            m["image_license"] = next_image.get("license", "")
        else:
            for field in ("image", "image_credit", "image_license"):
                m.pop(field, None)

    # 若该物种图片被清空：标记需人工审核，自动补图只能进待审核队列
    remaining_images = sum(1 for e in m.get("images", []) if not e.get("pending"))
    emptied = bool(kind == "images" and remaining_images == 0)
    if emptied:
        m["backfill_review"] = True

    mp.write_text(json.dumps(m, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    update_index()
    _invalidate_contributors_cache()  # 删的可能是已通过的用户图，刷新致谢缓存
    _invalidate_rate_queue_cache()  # image_count 变化，刷新评级队列

    _append_delete_log(
        {
            "action": "delete",
            "trash_id": trash_id,
            "sci": sci,
            "key": key,
            "kind": kind,
            "file": file,
            "contributor": removed.get("contributor", ""),
            "by": admin.get("id", ""),
            "at": deleted_at,
            "emptied_species": emptied,
        }
    )
    _log_op(
        "删除媒体",
        admin.get("id", ""),
        f"{sci} / {file}",
        "图片已清空→补图转审核" if emptied else "",
    )
    return {
        "deleted": True,
        "sci": sci,
        "kind": kind,
        "file": file,
        "trash_id": trash_id,
        "emptied_species": emptied,
    }


@app.get("/api/admin/trash")
def admin_list_trash(
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    _require_admin(authorization, token)
    items = []
    for meta in _read_trash_entries():
        entry = meta.get("entry", {}) or {}
        deleted_at = meta.get("deleted_at") or 0
        has_file = any(sf.get("field") == "file" for sf in meta.get("stored_files", []))
        items.append(
            {
                "trash_id": meta.get("trash_id"),
                "sci": meta.get("sci"),
                "kind": meta.get("kind"),
                "file": meta.get("file"),
                "contributor": entry.get("contributor", ""),
                "license": entry.get("license", ""),
                "deleted_by": meta.get("deleted_by", ""),
                "deleted_at": deleted_at,
                "expires_at": (
                    deleted_at + TRASH_RETENTION_DAYS * 86400 if deleted_at else 0
                ),
                "has_file": has_file,
            }
        )
    return {"items": items, "retention_days": TRASH_RETENTION_DAYS}


@app.get("/api/admin/trash/file")
def admin_trash_file(
    id: str = "",
    token: str = "",
    authorization: str | None = Header(default=None),
) -> FileResponse:
    _require_admin(authorization, token)
    if not id or "/" in id or ".." in id:
        raise HTTPException(status_code=400, detail="Invalid id")
    entry_dir = TRASH_DIR / id
    try:
        meta = json.loads((entry_dir / "meta.json").read_text(encoding="utf-8"))
    except Exception:
        raise HTTPException(status_code=404, detail="Not found")
    main = next(
        (sf for sf in meta.get("stored_files", []) if sf.get("field") == "file"), None
    )
    if not main:
        raise HTTPException(status_code=404, detail="No file")
    fp = entry_dir / main["stored"]
    if not fp.exists():
        raise HTTPException(status_code=404, detail="File missing")
    return FileResponse(str(fp))


@app.post("/api/admin/trash/restore")
async def admin_restore_media(
    payload: dict = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    admin = _require_admin(authorization, token)
    _purge_trash()
    trash_id = str(payload.get("trash_id", "")).strip()
    if not trash_id or "/" in trash_id or ".." in trash_id:
        raise HTTPException(status_code=400, detail="Invalid trash_id")
    entry_dir = TRASH_DIR / trash_id
    try:
        meta = json.loads((entry_dir / "meta.json").read_text(encoding="utf-8"))
    except Exception:
        raise HTTPException(status_code=404, detail="回收站条目不存在或已过期")
    key = meta["key"]
    kind = meta["kind"]
    entry = meta.get("entry", {}) or {}

    for sf in meta.get("stored_files", []):
        src = entry_dir / sf["stored"]
        try:
            rel_path = _safe_manifest_file(
                sf["rel"],
                (
                    "images/"
                    if sf["field"] == "file" and kind == "images"
                    else ("audio/" if sf["field"] == "file" else "audio_spectrograms/")
                ),
            )
        except HTTPException:
            continue
        dest = SPECIES_DIR / key / rel_path
        dest.parent.mkdir(parents=True, exist_ok=True)
        if src.exists():
            try:
                shutil.move(str(src), str(dest))
            except Exception:
                pass

    mp = SPECIES_DIR / key / "manifest.json"
    try:
        m = json.loads(mp.read_text(encoding="utf-8")) if mp.exists() else {}
    except Exception:
        m = {}
    arr = m.get(kind, [])
    if not any(e.get("file") == entry.get("file") for e in arr):
        arr.append(entry)
    m[kind] = arr
    if meta.get("was_cover") and kind == "images" and entry.get("file"):
        m["image"] = entry.get("file")
        m["image_credit"] = entry.get("credit") or entry.get("contributor", "")
        m["image_license"] = entry.get("license", "")
    if sum(1 for e in m.get("images", []) if not e.get("pending")) > 0:
        m.pop("backfill_review", None)
    mp.parent.mkdir(parents=True, exist_ok=True)
    mp.write_text(json.dumps(m, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    update_index()
    _invalidate_contributors_cache()  # 恢复的可能是已通过的用户图，重新计入致谢
    _invalidate_rate_queue_cache()  # 恢复后 image_count 回升，刷新评级队列
    try:
        shutil.rmtree(entry_dir)
    except Exception:
        pass

    _append_delete_log(
        {
            "action": "restore",
            "trash_id": trash_id,
            "sci": meta.get("sci"),
            "key": key,
            "kind": kind,
            "file": entry.get("file"),
            "by": admin.get("id", ""),
            "at": time.time(),
        }
    )
    _log_op("恢复媒体", admin.get("id", ""), f"{meta.get('sci')} / {entry.get('file')}")
    return {
        "restored": True,
        "sci": meta.get("sci"),
        "kind": kind,
        "file": entry.get("file"),
    }


@app.get("/api/admin/delete_log")
def admin_delete_log(
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    _require_admin(authorization, token)
    try:
        log = json.loads(DELETE_LOG_FILE.read_text(encoding="utf-8"))
        if not isinstance(log, list):
            log = []
    except Exception:
        log = []
    return {"items": list(reversed(log[-500:]))}


@app.get("/api/admin/ops_log")
def admin_ops_log(
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    _require_admin(authorization, token)
    try:
        log = json.loads(OPS_LOG_FILE.read_text(encoding="utf-8"))
        if not isinstance(log, list):
            log = []
    except Exception:
        log = []
    return {"items": list(reversed(log[-800:]))}


# ── 识别测验出题日志（用于定位有问题的题/图）──────────────────
_quiz_lock = threading.Lock()


@app.post("/api/quiz/log")
def quiz_log(
    payload: dict = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    """App 出题/答题后回传一条记录。建议只回传答错或被举报的题。
    期望字段：sci(正确种), image(相对路径), options[list], correct, chosen,
    is_correct(bool), reported(bool), mode, client。"""
    user = _resolve_user_soft(authorization, token)
    sci = str(payload.get("sci", "")).strip()
    if not sci:
        raise HTTPException(status_code=400, detail="Missing sci")
    rec = {
        "sci": sci,
        "image": str(payload.get("image", ""))[:300],
        "options": [str(o)[:120] for o in (payload.get("options") or [])][:8],
        "correct": str(payload.get("correct", ""))[:120],
        "chosen": str(payload.get("chosen", ""))[:120],
        "is_correct": bool(payload.get("is_correct", False)),
        "reported": bool(payload.get("reported", False)),
        "mode": str(payload.get("mode", ""))[:40],
        "client": str(payload.get("client", ""))[:60],
        "uploader_id": user.get("id", "anon"),
        "at": int(time.time()),
    }
    with _quiz_lock:
        try:
            log = json.loads(QUIZ_LOG_FILE.read_text(encoding="utf-8"))
            if not isinstance(log, list):
                log = []
        except Exception:
            log = []
        log.append(rec)
        log = log[-5000:]
        try:
            QUIZ_LOG_FILE.write_text(
                json.dumps(log, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )
        except Exception:
            pass
    return {"ok": True}


@app.get("/api/admin/quiz_log")
def admin_quiz_log(
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    _require_admin(authorization, token)
    try:
        log = json.loads(QUIZ_LOG_FILE.read_text(encoding="utf-8"))
        if not isinstance(log, list):
            log = []
    except Exception:
        log = []
    # 按图片聚合，凸显"反复答错/被举报"的问题图
    by_img: dict[str, dict[str, Any]] = {}
    for r in log:
        img = r.get("image") or ""
        k = (r.get("sci", ""), img)
        key = "".join(k)
        a = by_img.setdefault(
            key,
            {
                "sci": r.get("sci", ""),
                "image": img,
                "wrong": 0,
                "reported": 0,
                "total": 0,
            },
        )
        a["total"] += 1
        if not r.get("is_correct"):
            a["wrong"] += 1
        if r.get("reported"):
            a["reported"] += 1
    problems = sorted(
        by_img.values(), key=lambda x: (x["reported"], x["wrong"]), reverse=True
    )
    return {
        "items": list(reversed(log[-500:])),
        "problems": problems[:200],
        "total": len(log),
        "total_wrong": sum(1 for r in log if not r.get("is_correct")),
        "total_reported": sum(1 for r in log if r.get("reported")),
    }


# 公开致谢名单：全量聚合带 TTL 缓存。该接口公开无鉴权且每次都要扫全部 manifest（约 1.1 万个），
# 不缓存会成为软 DoS 面 + 服务器抖动源；致谢名单容忍 5 分钟延迟，故用进程内 TTL 缓存。
_CONTRIB_CACHE: dict[str, Any] | None = None
_CONTRIB_CACHE_TS: float = 0.0
_CONTRIB_CACHE_TTL = 300  # 秒
_CONTRIB_CACHE_LOCK = threading.Lock()  # 单飞：失效后只让一个线程扫全量，其余复用结果


def _compute_contributors_full() -> dict[str, Any]:
    """扫全部 manifest，按署名聚合（只计已通过、不暴露 uploader_id）。返回未截断的全量结果。"""
    cagg: dict[str, dict[str, Any]] = {}
    for mp in SPECIES_DIR.glob("*/manifest.json"):
        try:
            m = json.loads(mp.read_text(encoding="utf-8"))
        except Exception:
            continue
        key = mp.parent.name
        for kind in ("images", "audio"):
            for e in m.get(kind, []):
                if not e.get("uploader_id"):
                    continue
                if e.get("pending"):
                    continue  # 只统计已通过的内容
                cname = (e.get("contributor") or "").strip() or "（未署名）"
                c = cagg.setdefault(
                    cname,
                    {"contributor": cname, "images": 0, "audio": 0, "_species": set()},
                )
                c["_species"].add(key)
                if kind == "images":
                    c["images"] += 1
                else:
                    c["audio"] += 1
    rows = [
        {
            "contributor": c["contributor"],
            "images": c["images"],
            "audio": c["audio"],
            "species": len(c["_species"]),
        }
        for c in cagg.values()
    ]
    rows.sort(key=lambda r: (r["images"], r["audio"], r["species"]), reverse=True)
    total_images = sum(r["images"] for r in rows)
    total_species = len({k for c in cagg.values() for k in c["_species"]})
    return {
        "rows": rows,
        "total_contributors": len(cagg),
        "total_images": total_images,
        "total_species": total_species,
    }


def _invalidate_contributors_cache() -> None:
    """审核通过/拒绝、删媒体等会改动署名统计的写操作后调用，让致谢名单及时刷新。"""
    global _CONTRIB_CACHE
    _CONTRIB_CACHE = None


@app.get("/api/contributors")
def public_contributors(limit: int = 50) -> dict:
    """公开只读：按署名(contributor)聚合的用户上传致谢名单（只计已通过、不暴露 uploader_id）。
    全量聚合带 5 分钟 TTL 缓存（见 _compute_contributors_full），limit 仅做切片、共享缓存。"""
    global _CONTRIB_CACHE, _CONTRIB_CACHE_TS
    now = time.time()
    cache = _CONTRIB_CACHE
    if cache is None or (now - _CONTRIB_CACHE_TS) > _CONTRIB_CACHE_TTL:
        # 单飞 + 双检：失效后只让一个线程扫全量 manifest（约 1.1 万个），其余并发请求
        # 等它算完直接复用，避免每个请求各自重复全量扫描、把同步线程池耗尽。
        with _CONTRIB_CACHE_LOCK:
            cache = _CONTRIB_CACHE
            if cache is None or (time.time() - _CONTRIB_CACHE_TS) > _CONTRIB_CACHE_TTL:
                cache = _compute_contributors_full()
                _CONTRIB_CACHE = cache
                _CONTRIB_CACHE_TS = time.time()
    rows = cache["rows"]
    if limit and limit > 0:
        rows = rows[:limit]
    return {
        "rows": rows,
        "total_contributors": cache["total_contributors"],
        "total_images": cache["total_images"],
        "total_species": cache["total_species"],
    }


@app.get("/api/admin/contributors")
def admin_contributors(
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    """按用户统计上传贡献（只计 uploader_id 标记的用户上传，不含 iNaturalist 自动补图）。"""
    _require_admin(authorization, token)
    users = load_users() or {}
    id_name: dict[str, str] = {}
    for _tok, u in users.items():
        if isinstance(u, dict) and u.get("id"):
            id_name[u["id"]] = u.get("name") or u["id"]

    agg: dict[str, dict[str, Any]] = {}
    cagg: dict[str, dict[str, Any]] = {}  # 按署名(contributor)聚合（仍只计用户上传）
    for mp in SPECIES_DIR.glob("*/manifest.json"):
        try:
            m = json.loads(mp.read_text(encoding="utf-8"))
        except Exception:
            continue
        key = mp.parent.name
        for kind in ("images", "audio"):
            for e in m.get(kind, []):
                uid = e.get("uploader_id")
                if not uid:
                    continue
                a = agg.setdefault(
                    uid,
                    {
                        "uploader_id": uid,
                        "name": e.get("uploader_name") or "",
                        "images": 0,
                        "audio": 0,
                        "pending": 0,
                        "_species": set(),
                    },
                )
                cname = (e.get("contributor") or "").strip() or "（未署名）"
                c = cagg.setdefault(
                    cname,
                    {
                        "contributor": cname,
                        "images": 0,
                        "audio": 0,
                        "pending": 0,
                        "_species": set(),
                    },
                )
                a["_species"].add(key)
                c["_species"].add(key)
                if e.get("pending"):
                    a["pending"] += 1
                    c["pending"] += 1
                elif kind == "images":
                    a["images"] += 1
                    c["images"] += 1
                else:
                    a["audio"] += 1
                    c["audio"] += 1

    rows = []
    for uid, a in agg.items():
        rows.append(
            {
                "uploader_id": uid,
                "name": id_name.get(uid) or a.get("name") or uid,
                "images": a["images"],
                "audio": a["audio"],
                "pending": a["pending"],
                "species": len(a["_species"]),
            }
        )
    rows.sort(key=lambda r: (r["images"], r["audio"], r["species"]), reverse=True)
    crows = []
    for cname, c in cagg.items():
        crows.append(
            {
                "contributor": cname,
                "images": c["images"],
                "audio": c["audio"],
                "pending": c["pending"],
                "species": len(c["_species"]),
            }
        )
    crows.sort(key=lambda r: (r["images"], r["audio"], r["species"]), reverse=True)
    return {
        "rows": rows,
        "by_contributor": crows,
        "total_users": len(rows),
        "total_contributors": len(crows),
        "total_images": sum(r["images"] for r in rows),
        "total_audio": sum(r["audio"] for r in rows),
        "total_pending": sum(r["pending"] for r in rows),
        "total_species": len({k for a in agg.values() for k in a["_species"]}),
    }


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
        out.append(
            {
                "token": tok,
                "id": info.get("id", ""),
                "role": info.get("role", "beta"),
                "name": info.get("name", ""),
                "is_self": tok == me_token,
            }
        )
    out.sort(key=lambda x: (x["role"] != "admin", x["id"]))
    return out


@app.post("/api/admin/users")
async def admin_add_user(
    payload: dict = Body(...),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    _admin = _require_admin(authorization, token)
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
    _log_op("新增密钥", _admin.get("id", ""), f"{name} ({user_id})", role)
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
    _log_op(
        "删除密钥",
        me.get("id", ""),
        f"{removed.get('name', '')} ({removed.get('id', '')})",
    )
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
    update_index()
    _invalidate_rate_queue_cache()
    return {"saved": True, "sci": sci, "file": file, "difficulty": difficulty}


@app.post("/api/admin/spectrograms/backfill")
async def admin_backfill_spectrograms(
    payload: dict = Body(default={}),
    token: str = "",
    authorization: str | None = Header(default=None),
) -> dict:
    _require_admin(authorization, token)
    limit = int(payload.get("limit", 5000))
    dry_run = bool(payload.get("dry_run", False))
    force = bool(payload.get("force", False))
    limit = max(1, min(50000, limit))

    scanned = generated = skipped = failed = 0
    items: list[dict[str, Any]] = []
    for mp in sorted(SPECIES_DIR.glob("*/manifest.json")):
        if scanned >= limit:
            break
        try:
            manifest = json.loads(mp.read_text(encoding="utf-8"))
        except Exception:
            failed += 1
            continue
        sci = str(manifest.get("sci", "")).strip()
        if not sci:
            skipped += 1
            continue
        changed = False
        for entry in manifest.get("audio", []):
            if scanned >= limit:
                break
            scanned += 1
            if entry.get("pending"):
                skipped += 1
                continue
            if entry.get("spectrogram_url") and not force:
                skipped += 1
                continue
            rel = str(entry.get("file", "")).strip()
            try:
                audio_rel = _safe_manifest_file(rel, "audio/")
            except HTTPException:
                failed += 1
                continue
            audio_path = mp.parent / audio_rel
            if not audio_path.exists():
                failed += 1
                continue
            if dry_run:
                items.append({"sci": sci, "file": rel, "would_generate": True})
                continue
            result = try_generate_spectrogram(sci, audio_path)
            if result:
                entry.update(result)
                generated += 1
                changed = True
                items.append({"sci": sci, "file": rel, **result})
            else:
                failed += 1
        if changed:
            mp.write_text(
                json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
    if generated and not dry_run:
        update_index()
    return {
        "scanned": scanned,
        "generated": generated,
        "skipped": skipped,
        "failed": failed,
        "dry_run": dry_run,
        "force": force,
        "items": items[:50],
    }


def _compress_image(
    file_path: Path, *, max_side: int = 1600, quality: int = 82, target_kb: int = 600
) -> Path:
    """Re-encode image as JPEG (long side <= max_side, ~target_kb). HEIC/PNG/WebP -> JPEG (renamed).
    Returns final path (extension may change to .jpg). Fail-open: returns original on error.
    """
    if not _PIL_OK:
        return file_path
    try:
        with Image.open(file_path) as im:
            im = ImageOps.exif_transpose(im)
            if im.mode in ("RGBA", "LA", "P"):
                bg = Image.new("RGB", im.size, (255, 255, 255))
                if im.mode == "P":
                    im = im.convert("RGBA")
                bg.paste(im, mask=im.split()[-1] if im.mode in ("RGBA", "LA") else None)
                im = bg
            elif im.mode != "RGB":
                im = im.convert("RGB")
            w, h = im.size
            scale = min(1.0, max_side / max(w, h))
            if scale < 1.0:
                im = im.resize((int(w * scale), int(h * scale)), Image.LANCZOS)
            q = quality
            tmp = file_path.with_suffix(file_path.suffix + ".tmp.jpg")
            for _ in range(4):
                im.save(tmp, format="JPEG", quality=q, optimize=True, progressive=True)
                if tmp.stat().st_size <= target_kb * 1024 or q <= 60:
                    break
                q -= 8
            ext = file_path.suffix.lower()
            if ext in (".jpg", ".jpeg"):
                tmp.replace(file_path)
                return file_path
            new_path = file_path.with_suffix(".jpg")
            tmp.replace(new_path)
            if new_path != file_path and file_path.exists():
                file_path.unlink()
            return new_path
    except Exception as e:
        print(f"compress failed for {file_path}: {e}")
    return file_path
