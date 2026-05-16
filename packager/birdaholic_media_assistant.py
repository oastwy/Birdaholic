#!/usr/bin/env python3
"""Birdaholic local media assistant.

This is a small Mac-friendly Tkinter app for preparing media uploads locally.
It recognizes species from filenames first and can optionally call
BirdNET-Analyzer for unrecognized audio files when birdnet_analyzer is installed.
"""

from __future__ import annotations

import csv
import http.server
import importlib.util
import json
import math
import os
import queue
import re
import shutil
import socketserver
import struct
import subprocess
import sys
import tempfile
import threading
import tkinter as tk
import time
import urllib.error
import urllib.parse
import urllib.request
import wave
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from pathlib import Path
from tkinter import filedialog, messagebox, ttk
from typing import Any

try:
    from pypinyin import Style as PinyinStyle, lazy_pinyin
except Exception:
    PinyinStyle = None
    lazy_pinyin = None


IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".heic"}
AUDIO_EXTS = {".mp3", ".m4a", ".aac", ".wav", ".flac", ".ogg"}
APP_VERSION = "1.3.3"
STATE_FILE = "media_assistant_state.json"
HISTORY_FILE = "upload_history.json"
EBIRD_API = "https://api.ebird.org/v2"
EBIRD_CACHE_DIR = Path.home() / ".cache" / "birdaholic_media_assistant"
COUNTRY_OPTIONS = [
    "全球",
    "中国 CN",
    "新西兰 NZ",
    "澳大利亚 AU",
    "美国 US",
    "英国 GB",
    "日本 JP",
    "印度 IN",
    "尼泊尔 NP",
    "泰国 TH",
    "越南 VN",
    "马来西亚 MY",
    "印度尼西亚 ID",
    "菲律宾 PH",
    "新加坡 SG",
]
ALIASES = {
    "common chaffinch": "eurasian chaffinch",
}


def app_root() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parents[1] / "Resources"
    return Path(__file__).resolve().parents[1]


def bundled_world_birds_path() -> Path:
    candidates = [
        app_root() / "assets/data/world_birds.json",
        Path(__file__).resolve().parents[1] / "assets/data/world_birds.json",
        Path.cwd() / "assets/data/world_birds.json",
    ]
    for path in candidates:
        if path.exists():
            return path
    return candidates[0]


def bundled_osea_model_path() -> Path:
    candidates = [
        app_root() / "models/osea/bird_model.onnx",
        Path(__file__).resolve().parents[1] / "models/osea/bird_model.onnx",
        Path.cwd() / "models/osea/bird_model.onnx",
    ]
    for path in candidates:
        if path.exists():
            return path
    return candidates[0]


def bundled_osea_info_path() -> Path:
    candidates = [
        app_root() / "models/osea/bird_info.json",
        Path(__file__).resolve().parents[1] / "models/osea/bird_info.json",
        Path.cwd() / "models/osea/bird_info.json",
    ]
    for path in candidates:
        if path.exists():
            return path
    return candidates[0]


@dataclass
class MediaDecision:
    src: Path
    kind: str
    status: str
    sci: str = ""
    zh: str = ""
    en: str = ""
    score: float = 0.0
    method: str = ""
    output: str = ""
    active: bool = True
    candidates: list[dict[str, Any]] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "src": str(self.src),
            "kind": self.kind,
            "status": self.status,
            "sci": self.sci,
            "zh": self.zh,
            "en": self.en,
            "score": self.score,
            "method": self.method,
            "output": self.output,
            "active": self.active,
            "candidates": self.candidates,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "MediaDecision":
        status = str(data.get("status") or "candidate")
        if status == "recognized":
            status = "candidate"
        return cls(
            src=Path(data.get("src") or data.get("original") or ""),
            kind=str(data.get("kind") or ""),
            status=status,
            sci=str(data.get("sci") or ""),
            zh=str(data.get("zh") or ""),
            en=str(data.get("en") or ""),
            score=float(data.get("score") or 0),
            method=str(data.get("method") or ""),
            output=str(data.get("output") or ""),
            active=bool(data.get("active", True)) and status == "confirmed",
            candidates=list(data.get("candidates") or []),
        )


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
    return ALIASES.get(text, text)


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


def media_kind(path: Path) -> str | None:
    suffix = path.suffix.lower()
    if suffix in IMAGE_EXTS:
        return "images"
    if suffix in AUDIO_EXTS:
        return "audio"
    return None


class SpeciesMatcher:
    def __init__(self, world_birds_path: Path):
        self.species = json.loads(world_birds_path.read_text(encoding="utf-8"))
        self.by_sci = {
            item.get("sci", "").lower(): item
            for item in self.species
            if item.get("sci")
        }
        self.by_en = {
            normalize_name(item.get("en", "")): item
            for item in self.species
            if item.get("en")
        }
        self.initials = [
            (initials, item)
            for item in self.species
            if (initials := pinyin_initials(item.get("zh", "")))
        ]

    def match(self, value: str, threshold: float = 0.88) -> tuple[dict[str, Any] | None, float]:
        normalized = normalize_name(value)
        if not normalized:
            return None, 0

        direct = self.by_sci.get(normalized) or self.by_en.get(normalized)
        if direct:
            return direct, 1

        for item in self.species:
            sci = item.get("sci", "")
            if normalized == normalize_name(sci) or normalized == species_key(sci).lower():
                return item, 1
            for name in candidate_names(item):
                if normalized == normalize_name(name):
                    return item, 1

        best: tuple[float, dict[str, Any] | None] = (0, None)
        for item in self.species:
            for name in candidate_names(item):
                score = SequenceMatcher(None, normalized, normalize_name(name)).ratio()
                if score > best[0]:
                    best = (score, item)
        return (best[1], best[0]) if best[0] >= threshold else (None, best[0])

    def by_scientific_or_label(self, label: str) -> tuple[dict[str, Any] | None, float]:
        text = label.strip()
        if "_" in text and " " not in text.split("_", 1)[0]:
            sci, _, common = text.partition("_")
            item = self.by_sci.get(sci.lower())
            if item:
                return item, 1
            if common:
                return self.match(common)
        item = self.by_sci.get(text.lower())
        if item:
            return item, 1
        return self.match(text)

    def search(self, value: str, limit: int = 12, allowed_codes: set[str] | None = None) -> list[tuple[dict[str, Any], float]]:
        normalized = normalize_name(value)
        if not normalized:
            return []
        scored: dict[str, tuple[dict[str, Any], float]] = {}
        species_pool = [
            item for item in self.species
            if allowed_codes is None or str(item.get("code") or "").lower() in allowed_codes
        ]
        for item in species_pool:
            sci = item.get("sci", "")
            for name in candidate_names(item):
                name_norm = normalize_name(name)
                if not name_norm:
                    continue
                if normalized == name_norm:
                    score = 1.0
                elif normalized in name_norm:
                    score = 0.92
                else:
                    score = SequenceMatcher(None, normalized, name_norm).ratio()
                if score >= 0.55:
                    old = scored.get(sci)
                    if old is None or score > old[1]:
                        scored[sci] = (item, score)
        for initials, item in self.initials:
            if allowed_codes is not None and str(item.get("code") or "").lower() not in allowed_codes:
                continue
            if initials.startswith(normalized) or normalized in initials:
                sci = item.get("sci", "")
                score = 0.95 if initials.startswith(normalized) else 0.75
                old = scored.get(sci)
                if old is None or score > old[1]:
                    scored[sci] = (item, score)
        return sorted(scored.values(), key=lambda row: row[1], reverse=True)[:limit]


def pinyin_initials(value: str) -> str:
    text = value.strip()
    if not text:
        return ""
    if lazy_pinyin is None or PinyinStyle is None:
        return ""
    try:
        return "".join(lazy_pinyin(text, style=PinyinStyle.FIRST_LETTER)).lower()
    except Exception:
        return ""


def country_code_from_option(option: str) -> str:
    text = option.strip()
    if not text or text == "全球":
        return ""
    return text.split()[-1].strip().upper()


def country_code_from_coordinates(lat_text: str, lon_text: str) -> str:
    try:
        lat = float(lat_text)
        lon = float(lon_text)
    except ValueError:
        return ""
    boxes = [
        ("NZ", -47.5, -34.0, 166.0, 179.5),
        ("AU", -44.0, -9.0, 112.0, 154.0),
        ("CN", 18.0, 54.0, 73.0, 135.0),
        ("JP", 24.0, 46.0, 122.0, 146.0),
        ("IN", 6.0, 36.0, 68.0, 98.0),
        ("NP", 26.0, 31.0, 80.0, 89.0),
        ("TH", 5.0, 21.0, 97.0, 106.0),
        ("VN", 8.0, 24.0, 102.0, 110.0),
        ("MY", 0.0, 8.0, 99.0, 120.0),
        ("ID", -11.5, 6.5, 95.0, 141.5),
        ("PH", 4.0, 22.0, 116.0, 127.0),
        ("SG", 1.0, 1.6, 103.5, 104.1),
        ("US", 24.0, 50.0, -125.0, -66.0),
        ("GB", 49.0, 61.0, -8.5, 2.0),
    ]
    for code, min_lat, max_lat, min_lon, max_lon in boxes:
        if min_lat <= lat <= max_lat and min_lon <= lon <= max_lon:
            return code
    return ""


def fetch_ebird_species_codes(region: str, token: str) -> set[str]:
    region = region.strip().upper()
    if not region:
        return set()
    EBIRD_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache_path = EBIRD_CACHE_DIR / f"spplist_{region}.json"
    if cache_path.exists() and time.time() - cache_path.stat().st_mtime < 30 * 86400:
        return {str(code).lower() for code in json.loads(cache_path.read_text(encoding="utf-8"))}

    request = urllib.request.Request(f"{EBIRD_API}/product/spplist/{region}")
    if token.strip():
        request.add_header("X-eBirdApiToken", token.strip())
    with urllib.request.urlopen(request, timeout=20) as response:
        codes = json.loads(response.read().decode("utf-8"))
    cache_path.write_text(json.dumps(codes, ensure_ascii=False), encoding="utf-8")
    return {str(code).lower() for code in codes}


def run_quiet(command: list[str]) -> bool:
    try:
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


def optimize_image(src: Path, dst: Path, max_image: int, jpeg_quality: int) -> Path:
    dst = dst.with_suffix(".jpg")
    dst.parent.mkdir(parents=True, exist_ok=True)
    if shutil.which("sips"):
        ok = run_quiet(
            [
                "sips",
                "-Z",
                str(max_image),
                "-s",
                "format",
                "jpeg",
                "-s",
                "formatOptions",
                str(jpeg_quality),
                str(src),
                "--out",
                str(dst),
            ]
        )
        if ok and dst.exists():
            return dst
    shutil.copy2(src, dst)
    return dst


def optimize_audio(src: Path, dst: Path, bitrate: str) -> Path:
    dst = dst.with_suffix(".m4a")
    dst.parent.mkdir(parents=True, exist_ok=True)
    if shutil.which("ffmpeg"):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp) / dst.name
            ok = run_quiet(
                [
                    "ffmpeg",
                    "-y",
                    "-i",
                    str(src),
                    "-vn",
                    "-ac",
                    "1",
                    "-b:a",
                    bitrate,
                    str(tmp_path),
                ]
            )
            if ok and tmp_path.exists():
                shutil.move(str(tmp_path), dst)
                return dst
    copied = dst.with_suffix(src.suffix.lower())
    shutil.copy2(src, copied)
    return copied


def safe_name(src: Path, sci: str, kind: str) -> str:
    stem = species_key(sci)
    audio_type = ""
    lowered = src.stem.lower()
    if kind == "audio":
        audio_type = "_song" if "song" in lowered else "_call" if "call" in lowered else "_audio"
    return f"{stem}{audio_type}_{abs(hash(str(src))) % 100000}"


def bundled_birdnet_engine_path() -> Path | None:
    names = ["birdnet_engine", "birdnet_engine.exe"]
    roots = [
        app_root(),
        Path(sys.executable).resolve().parent if getattr(sys, "frozen", False) else Path(__file__).resolve().parent,
        Path(getattr(sys, "_MEIPASS", "")) if getattr(sys, "_MEIPASS", None) else None,
        Path(__file__).resolve().parent,
        Path(__file__).resolve().parents[1] / "dist" / "birdnet_engine",
    ]
    for root in roots:
        if root is None:
            continue
        for name in names:
            for candidate in [
                root / name,
                root / "bin" / name,
                root / "MacOS" / name,
                root / "birdnet_engine" / name,
            ]:
                if candidate.is_file() and os.access(candidate, os.X_OK):
                    return candidate
    return None


def birdnet_available() -> bool:
    if bundled_birdnet_engine_path() is not None:
        return True
    if importlib.util.find_spec("birdnet_analyzer") is not None:
        return True
    conda_python = Path("/opt/anaconda3/bin/python")
    if conda_python.exists():
        result = subprocess.run(
            [
                str(conda_python),
                "-c",
                "import importlib.util; raise SystemExit(0 if importlib.util.find_spec('birdnet_analyzer') else 1)",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return result.returncode == 0
    return False


def birdnet_python() -> str:
    if importlib.util.find_spec("birdnet_analyzer") is not None:
        return sys.executable
    conda_python = Path("/opt/anaconda3/bin/python")
    if conda_python.exists():
        return str(conda_python)
    return sys.executable


def run_birdnet_engine(
    engine_path: Path,
    input_dir: Path,
    results_dir: Path,
    min_conf: float,
    threads: int,
    lat: str,
    lon: str,
    week: str,
    log: callable,
) -> dict[Path, tuple[str, float]]:
    command = [
        str(engine_path),
        str(input_dir),
        "--output-dir",
        str(results_dir),
        "--min-conf",
        str(min_conf),
        "--threads",
        str(max(1, threads)),
    ]
    if lat.strip() and lon.strip():
        command.extend(["--lat", lat.strip(), "--lon", lon.strip()])
    if week.strip():
        command.extend(["--week", week.strip()])

    log("BirdNET 内置引擎开始分析音频，第一次会比较慢...")
    process = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        payload = json.loads(process.stdout.strip().splitlines()[-1])
    except (IndexError, json.JSONDecodeError) as exc:
        log(process.stdout[-2000:])
        raise RuntimeError("BirdNET 内置引擎没有返回有效结果") from exc

    if process.returncode != 0 or not payload.get("ok"):
        if payload.get("log"):
            log(str(payload["log"])[-2000:])
        elif payload.get("error"):
            log(str(payload["error"]))
        raise RuntimeError("BirdNET 内置引擎分析失败")

    predictions: dict[Path, tuple[str, float]] = {}
    for item in payload.get("predictions", []):
        try:
            src = Path(str(item["file"])).resolve()
            label = str(item["label"])
            confidence = float(item.get("confidence", 0))
        except (KeyError, TypeError, ValueError):
            continue
        old = predictions.get(src)
        if old is None or confidence > old[1]:
            predictions[src] = (label, confidence)
    log(f"BirdNET 内置引擎输出候选：{len(predictions)} 个文件")
    return predictions


def run_birdnet(
    input_dir: Path,
    output_dir: Path,
    min_conf: float,
    threads: int,
    lat: str,
    lon: str,
    week: str,
    log: callable,
) -> dict[Path, tuple[str, float]]:
    results_dir = output_dir / "_birdnet_results"
    results_dir.mkdir(parents=True, exist_ok=True)

    engine_path = bundled_birdnet_engine_path()
    if engine_path is not None:
        return run_birdnet_engine(engine_path, input_dir, results_dir, min_conf, threads, lat, lon, week, log)

    command = [
        birdnet_python(),
        "-m",
        "birdnet_analyzer.analyze",
        str(input_dir),
        "-o",
        str(results_dir),
        "--rtype",
        "csv",
        "--top_n",
        "5",
        "--min_conf",
        str(min_conf),
        "--threads",
        str(max(1, threads)),
    ]
    if lat.strip() and lon.strip():
        command.extend(["--lat", lat.strip(), "--lon", lon.strip()])
    if week.strip():
        command.extend(["--week", week.strip()])

    log("BirdNET 开始分析音频，第一次会比较慢...")
    env = os.environ.copy()
    conda_site = Path("/opt/anaconda3/lib/python3.12/site-packages")
    if conda_site.exists() and command[0] == "/opt/anaconda3/bin/python":
        existing = env.get("PYTHONPATH", "")
        env["PYTHONPATH"] = f"{conda_site}{os.pathsep}{existing}" if existing else str(conda_site)

    process = subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=env,
    )
    if process.returncode != 0:
        log(process.stdout[-2000:])
        raise RuntimeError("BirdNET 分析失败，请确认 birdnet_analyzer 已正确安装")

    predictions: dict[Path, tuple[str, float]] = {}
    for csv_path in results_dir.rglob("*.csv"):
        parse_birdnet_csv(csv_path, input_dir, predictions)
    log(f"BirdNET 输出候选：{len(predictions)} 个文件")
    return predictions


def parse_float(value: str) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def pick_column(fieldnames: list[str], options: list[str]) -> str | None:
    lowered = {name.lower().strip(): name for name in fieldnames}
    for option in options:
        if option in lowered:
            return lowered[option]
    for name in fieldnames:
        low = name.lower()
        if any(option in low for option in options):
            return name
    return None


def parse_birdnet_csv(
    csv_path: Path,
    input_dir: Path,
    predictions: dict[Path, tuple[str, float]],
) -> None:
    try:
        with csv_path.open(newline="", encoding="utf-8-sig") as handle:
            reader = csv.DictReader(handle)
            fieldnames = reader.fieldnames or []
            if not fieldnames:
                return
            file_col = pick_column(fieldnames, ["file", "filename", "source", "input"])
            sci_col = pick_column(fieldnames, ["scientific name", "sci_name", "scientific"])
            common_col = pick_column(fieldnames, ["common name", "common", "label", "species"])
            conf_col = pick_column(fieldnames, ["confidence", "score", "conf"])
            for row in reader:
                label = ""
                if sci_col and row.get(sci_col):
                    label = row[sci_col]
                elif common_col and row.get(common_col):
                    label = row[common_col]
                if not label:
                    continue

                confidence = parse_float(row.get(conf_col, "0") if conf_col else "0")
                if file_col and row.get(file_col):
                    src = Path(row[file_col])
                    if not src.is_absolute():
                        src = input_dir / src
                else:
                    src = input_dir / csv_path.with_suffix("").name
                src = src.resolve()
                old = predictions.get(src)
                if old is None or confidence > old[1]:
                    predictions[src] = (label, confidence)
    except Exception:
        return


def osea_available(model_path: Path, info_path: Path) -> bool:
    if not model_path.exists() or not info_path.exists():
        return False
    return importlib.util.find_spec("onnxruntime") is not None and importlib.util.find_spec("PIL") is not None


def run_osea_images(
    image_files: list[Path],
    model_path: Path,
    info_path: Path,
    log: callable,
) -> dict[Path, list[dict[str, Any]]]:
    if not image_files:
        return {}
    try:
        from osea_batch_identifier import OseaIdentifier
    except Exception as exc:
        try:
            from packager.osea_batch_identifier import OseaIdentifier
        except Exception:
            log(f"OSEA 图片识别不可用：{exc}")
            return {}

    if not osea_available(model_path, info_path):
        log("OSEA 图片识别不可用：缺少模型/标签或 onnxruntime/pillow。")
        return {}

    log(f"OSEA 开始识别图片 {len(image_files)} 张...")
    identifier = OseaIdentifier(model_path, info_path, top_k=3)
    predictions: dict[Path, list[dict[str, Any]]] = {}
    ok = 0
    for image_path in image_files:
        result = identifier.predict(image_path)
        if result.status != "ok":
            if result.error:
                log(f"OSEA 跳过 {image_path.name}: {result.error}")
            continue
        candidates: list[dict[str, Any]] = []
        for pred in result.predictions:
            label = pred.sci or pred.en or pred.zh
            if not label:
                continue
            candidates.append(
                {
                    "sci": pred.sci,
                    "zh": pred.zh,
                    "en": pred.en,
                    "code": pred.code,
                    "score": pred.score,
                    "label": label,
                }
            )
        if candidates:
            predictions[image_path.resolve()] = candidates
            ok += 1
    log(f"OSEA 图片识别输出候选：{ok} 个文件")
    return predictions


def write_outputs(decisions: list[MediaDecision], output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    csv_path = output_dir / "review_manifest.csv"
    with csv_path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["active", "original", "kind", "status", "sci", "zh", "en", "score", "method", "output"],
        )
        writer.writeheader()
        for item in decisions:
            writer.writerow(
                {
                    "active": "yes" if item.active else "no",
                    "original": str(item.src),
                    "kind": item.kind,
                    "status": item.status,
                    "sci": item.sci,
                    "zh": item.zh,
                    "en": item.en,
                    "score": f"{item.score:.2f}",
                    "method": item.method,
                    "output": item.output,
                }
            )

    html = [
        "<!doctype html><meta charset='utf-8'><title>Birdaholic 审核清单</title>",
        "<style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:24px}table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid #ddd;padding:8px;text-align:left}.ok{color:#216e1f}.bad{color:#a33}</style>",
        "<h1>Birdaholic 上传审核清单</h1><table><tr><th>状态</th><th>物种</th><th>分数</th><th>方法</th><th>原文件</th><th>输出</th></tr>",
    ]
    for item in decisions:
        css = "ok" if item.status in {"confirmed", "uploaded"} else "bad"
        species = f"{item.zh or item.en} · {item.sci}" if item.sci else "未识别"
        html.append(
            f"<tr><td class='{css}'>{item.status}</td><td>{species}</td><td>{item.score:.2f}</td><td>{item.method}</td><td>{item.src.name}</td><td>{item.output}</td></tr>"
        )
    html.append("</table>")
    (output_dir / "review_manifest.html").write_text("\n".join(html), encoding="utf-8")
    save_state(decisions, output_dir)


def save_state(decisions: list[MediaDecision], output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "app_version": APP_VERSION,
        "saved_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "decisions": [item.to_dict() for item in decisions],
    }
    (output_dir / STATE_FILE).write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def load_state(output_dir: Path) -> list[MediaDecision]:
    state_path = output_dir / STATE_FILE
    if not state_path.exists():
        return []
    payload = json.loads(state_path.read_text(encoding="utf-8"))
    return [MediaDecision.from_dict(item) for item in payload.get("decisions", [])]


def load_upload_history(output_dir: Path) -> list[dict[str, Any]]:
    history_path = output_dir / HISTORY_FILE
    if not history_path.exists():
        return []
    return list(json.loads(history_path.read_text(encoding="utf-8")))


def append_upload_history(decisions: list[MediaDecision], uploaded_sources: set[Path], output_dir: Path) -> None:
    if not uploaded_sources:
        return
    output_dir.mkdir(parents=True, exist_ok=True)
    history = load_upload_history(output_dir)
    uploaded_at = time.strftime("%Y-%m-%d %H:%M:%S")
    for item in decisions:
        if item.src not in uploaded_sources:
            continue
        history.append(
            {
                "uploaded_at": uploaded_at,
                "sci": item.sci,
                "zh": item.zh,
                "en": item.en,
                "kind": item.kind,
                "score": item.score,
                "method": item.method,
                "original": str(item.src),
                "output": item.output,
                "server": "",
            }
        )
    (output_dir / HISTORY_FILE).write_text(json.dumps(history, ensure_ascii=False, indent=2), encoding="utf-8")


def upload_decisions(
    decisions: list[MediaDecision],
    token: str,
    server_url: str,
    log: callable,
) -> set[Path]:
    confirmed = [
        item
        for item in decisions
        if item.active and item.status == "confirmed" and item.output
    ]
    if not confirmed:
        log("没有可上传的已确认文件。请先在审核视图里确认记录。")
        return set()
    if not token.strip():
        raise RuntimeError("请先填写上传密钥。")

    total_saved = 0
    total_failed = 0
    uploaded_sources: set[Path] = set()
    grouped: dict[str, list[MediaDecision]] = {}
    for item in confirmed:
        grouped.setdefault(item.sci, []).append(item)

    for sci, items in grouped.items():
        log(f"上传 {sci}：{len(items)} 个文件...")
        response = upload_files_for_species(
            files=[Path(item.output) for item in items],
            sci=sci,
            token=token.strip(),
            server_url=server_url.rstrip("/"),
        )
        total_saved += len(response.get("saved", []))
        total_failed += len(response.get("failed", []))
        if response.get("saved"):
            uploaded_sources.update(item.src for item in items)
        if response.get("failed"):
            log(json.dumps(response.get("failed"), ensure_ascii=False))

    log(f"上传完成：成功 {total_saved}，失败 {total_failed}")
    return uploaded_sources


def move_uploaded_sources(paths: set[Path], uploaded_dir: Path, log: callable) -> dict[Path, Path]:
    uploaded_dir.mkdir(parents=True, exist_ok=True)
    moved: dict[Path, Path] = {}
    for src in paths:
        if not src.exists():
            continue
        target = uploaded_dir / src.name
        if target.exists():
            target = uploaded_dir / f"{src.stem}_{int(time.time())}{src.suffix}"
        shutil.move(str(src), str(target))
        moved[src] = target
    if moved:
        log(f"已移动 {len(moved)} 个原文件到：{uploaded_dir}")
    return moved


def upload_files_for_species(
    files: list[Path],
    sci: str,
    token: str,
    server_url: str,
) -> dict[str, Any]:
    boundary = f"----BirdaholicBoundary{os.getpid()}{abs(hash(sci))}"
    body = bytearray()

    def add_field(name: str, value: str) -> None:
        body.extend(f"--{boundary}\r\n".encode())
        body.extend(f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode())
        body.extend(value.encode("utf-8"))
        body.extend(b"\r\n")

    add_field("token", token)
    add_field("sci", sci)

    for path in files:
        body.extend(f"--{boundary}\r\n".encode())
        body.extend(
            (
                f'Content-Disposition: form-data; name="files"; '
                f'filename="{path.name}"\r\n'
            ).encode()
        )
        content_type = "audio/mp4" if path.suffix.lower() == ".m4a" else "application/octet-stream"
        if path.suffix.lower() in {".jpg", ".jpeg"}:
            content_type = "image/jpeg"
        body.extend(f"Content-Type: {content_type}\r\n\r\n".encode())
        body.extend(path.read_bytes())
        body.extend(b"\r\n")
    body.extend(f"--{boundary}--\r\n".encode())

    request = urllib.request.Request(
        f"{server_url}/api/upload",
        data=bytes(body),
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"上传失败 HTTP {error.code}: {detail}") from error


def read_audio_samples(path: Path, target_width: int) -> list[float]:
    if target_width <= 0:
        return []
    with tempfile.TemporaryDirectory() as tmp_dir:
        wav_path = Path(tmp_dir) / "waveform.wav"
        converted = False
        if shutil.which("ffmpeg"):
            converted = run_quiet(
                [
                    "ffmpeg",
                    "-y",
                    "-i",
                    str(path),
                    "-vn",
                    "-ac",
                    "1",
                    "-ar",
                    "16000",
                    "-sample_fmt",
                    "s16",
                    str(wav_path),
                ]
            )
        if not converted and shutil.which("afconvert"):
            converted = run_quiet(
                [
                    "afconvert",
                    str(path),
                    str(wav_path),
                    "-f",
                    "WAVE",
                    "-d",
                    "LEI16@16000",
                    "-c",
                    "1",
                ]
            )
        if not converted or not wav_path.exists():
            return []
        try:
            with wave.open(str(wav_path), "rb") as handle:
                frames = handle.readframes(handle.getnframes())
                sample_count = len(frames) // 2
                if sample_count <= 0:
                    return []
                values = struct.unpack(f"<{sample_count}h", frames)
        except Exception:
            return []

    bucket = max(1, math.ceil(len(values) / target_width))
    samples: list[float] = []
    for start in range(0, len(values), bucket):
        chunk = values[start : start + bucket]
        peak = max(abs(value) for value in chunk) if chunk else 0
        samples.append(min(1.0, peak / 32768.0))
    return samples[:target_width]


def process_media(
    input_dir: Path,
    output_dir: Path,
    world_birds: Path,
    use_birdnet: bool,
    use_osea: bool,
    min_conf: float,
    image_min_conf: float,
    threads: int,
    lat: str,
    lon: str,
    week: str,
    osea_model: Path,
    osea_info: Path,
    log: callable,
) -> list[MediaDecision]:
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    matcher = SpeciesMatcher(world_birds)
    media_files = [path for path in input_dir.rglob("*") if path.is_file() and media_kind(path)]
    audio_files = [path for path in media_files if media_kind(path) == "audio"]
    image_files = [path for path in media_files if media_kind(path) == "images"]
    log(f"找到媒体文件 {len(media_files)} 个，其中音频 {len(audio_files)} 个，图片 {len(image_files)} 张")

    birdnet_predictions: dict[Path, tuple[str, float]] = {}
    if use_birdnet and audio_files:
        if not birdnet_available():
            log("没有检测到 birdnet_analyzer，跳过 BirdNET。")
        else:
            birdnet_predictions = run_birdnet(input_dir, output_dir, min_conf, threads, lat, lon, week, log)

    osea_predictions: dict[Path, list[dict[str, Any]]] = {}
    if use_osea and image_files:
        osea_predictions = run_osea_images(image_files, osea_model, osea_info, log)

    decisions: list[MediaDecision] = []
    for src in media_files:
        kind = media_kind(src) or ""
        item, score = matcher.match(src.name)
        method = "filename"

        candidate_status = "candidate"
        candidate_active = False
        review_candidates: list[dict[str, Any]] = []
        if (item is None or score < 0.95) and src.resolve() in birdnet_predictions:
            label, confidence = birdnet_predictions[src.resolve()]
            bird_item, _ = matcher.by_scientific_or_label(label)
            if bird_item:
                item = bird_item
                score = confidence
                if confidence >= min_conf:
                    method = "birdnet"
                else:
                    method = "birdnet_candidate"

        if kind == "images" and (item is None or score < 0.95) and src.resolve() in osea_predictions:
            raw_candidates = osea_predictions[src.resolve()]
            for raw in raw_candidates:
                label = str(raw.get("label") or raw.get("sci") or raw.get("en") or raw.get("zh") or "")
                image_item, _ = matcher.by_scientific_or_label(label)
                if image_item:
                    review_candidates.append(
                        {
                            "sci": image_item.get("sci", ""),
                            "zh": image_item.get("zh", ""),
                            "en": image_item.get("en", ""),
                            "score": float(raw.get("score", 0)),
                            "method": "osea",
                        }
                    )
            if review_candidates:
                image_item = {
                    "sci": review_candidates[0]["sci"],
                    "zh": review_candidates[0]["zh"],
                    "en": review_candidates[0]["en"],
                }
                confidence = float(review_candidates[0]["score"])
                item = image_item
                score = confidence
                if confidence >= image_min_conf:
                    method = "osea"
                else:
                    method = "osea_candidate"

        if item is None:
            target_dir = output_dir / "_unrecognized" / kind
            target_dir.mkdir(parents=True, exist_ok=True)
            target = target_dir / src.name
            shutil.copy2(src, target)
            decisions.append(MediaDecision(src=src, kind=kind, status="unrecognized", score=score, method=method, output=str(target), active=False))
            continue

        sci = item["sci"]
        dst = output_dir / species_key(sci) / kind / safe_name(src, sci, kind)
        if kind == "images":
            output = optimize_image(src, dst, max_image=1600, jpeg_quality=70)
        else:
            output = optimize_audio(src, dst, bitrate="64k")
        decisions.append(
            MediaDecision(
                src=src,
                kind=kind,
                status=candidate_status,
                sci=sci,
                zh=item.get("zh", ""),
                en=item.get("en", ""),
                score=score,
                method=method,
                output=str(output),
                active=candidate_active,
                candidates=review_candidates,
            )
        )

    write_outputs(decisions, output_dir)
    recognized = sum(1 for item in decisions if item.sci)
    candidates = sum(1 for item in decisions if item.status == "candidate")
    log(f"完成：识别 {recognized}/{len(decisions)} 个文件，待人工审核 {candidates} 个")
    log(f"输出目录：{output_dir}")
    log(f"审核清单：{output_dir / 'review_manifest.html'}")
    return decisions


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title(f"Birdaholic 本地媒体助手 v{APP_VERSION}")
        self.geometry("1180x930")
        self.main_thread_id = threading.get_ident()
        self.ui_queue: queue.Queue[tuple[str, Any]] = queue.Queue()

        self.input_var = tk.StringVar(value="/Users/wuyang/Archive/bird_uploads/file")
        self.output_var = tk.StringVar(value=str(Path.home() / "BirdaholicUploadBatch"))
        self.world_var = tk.StringVar(value=str(bundled_world_birds_path()))
        self.server_var = tk.StringVar(value="http://124.223.101.188:8080")
        self.token_var = tk.StringVar(value="birdaholic_2026")
        self.birdnet_var = tk.BooleanVar(value=True)
        self.osea_var = tk.BooleanVar(value=True)
        self.auto_upload_var = tk.BooleanVar(value=False)
        self.move_uploaded_var = tk.BooleanVar(value=True)
        self.uploaded_dir_var = tk.StringVar(value="/Users/wuyang/Archive/bird_uploads/已上传")
        self.lat_var = tk.StringVar()
        self.lon_var = tk.StringVar()
        self.week_var = tk.StringVar()
        self.min_conf_var = tk.StringVar(value="0.30")
        self.image_min_conf_var = tk.StringVar(value="0.15")
        self.threads_var = tk.StringVar(value="2")
        self.osea_model_var = tk.StringVar(value=str(bundled_osea_model_path()))
        self.osea_info_var = tk.StringVar(value=str(bundled_osea_info_path()))
        self.edit_species_var = tk.StringVar()
        self.filter_var = tk.StringVar(value="全部")
        self.stats_var = tk.StringVar(value="尚未识别")
        self.decisions: list[MediaDecision] = []
        self.matcher: SpeciesMatcher | None = None
        self.map_server: socketserver.TCPServer | None = None
        self.review_win: tk.Toplevel | None = None
        self.review_index = 0
        self.review_canvas: tk.Canvas | None = None
        self.review_info_var = tk.StringVar()
        self.review_species_var = tk.StringVar()
        self.review_search_var = tk.StringVar()
        self.review_country_var = tk.StringVar(value="全球")
        self.ebird_token_var = tk.StringVar(value=os.environ.get("EBIRD_API_TOKEN", ""))
        self.region_status_var = tk.StringVar(value="搜索地区：全球")
        self.review_candidate_frame: ttk.Frame | None = None
        self.review_result_box: tk.Listbox | None = None
        self.review_search_results: list[dict[str, Any]] = []
        self.review_search_after_id: str | None = None
        self.review_allowed_codes: set[str] | None = None
        self.history_win: tk.Toplevel | None = None
        self.history_tree: ttk.Treeview | None = None
        self.server_stats_tree: ttk.Treeview | None = None
        self.server_stats_summary_var = tk.StringVar(value="尚未刷新服务器统计")
        self.server_stats_query_var = tk.StringVar()

        self._build()
        self.load_saved_state()
        self.after(80, self.drain_ui_queue)

    def _build(self):
        pad = {"padx": 12, "pady": 6}
        frm = ttk.Frame(self)
        frm.pack(fill="both", expand=True, padx=12, pady=12)

        self._path_row(frm, "输入文件夹", self.input_var, 0)
        self._path_row(frm, "输出文件夹", self.output_var, 1)
        self._path_row(frm, "世界鸟类名录", self.world_var, 2, file=True)

        upload = ttk.LabelFrame(frm, text="上传到服务器")
        upload.grid(row=3, column=0, columnspan=3, sticky="ew", padx=12, pady=6)
        ttk.Label(upload, text="服务器").grid(row=0, column=0, sticky="e", padx=8, pady=6)
        ttk.Entry(upload, textvariable=self.server_var, width=44).grid(row=0, column=1, sticky="ew", padx=8, pady=6)
        ttk.Label(upload, text="上传密钥").grid(row=0, column=2, sticky="e", padx=8, pady=6)
        ttk.Entry(upload, textvariable=self.token_var, show="*", width=18).grid(row=0, column=3, padx=8, pady=6)
        ttk.Checkbutton(upload, text="处理完成后自动上传", variable=self.auto_upload_var).grid(row=0, column=4, sticky="w", padx=8, pady=6)
        ttk.Checkbutton(upload, text="上传成功后移动原文件", variable=self.move_uploaded_var).grid(row=1, column=0, sticky="w", padx=8, pady=6)
        ttk.Entry(upload, textvariable=self.uploaded_dir_var).grid(row=1, column=1, columnspan=3, sticky="ew", padx=8, pady=6)
        ttk.Button(upload, text="选择", command=lambda: self.choose_dir(self.uploaded_dir_var)).grid(row=1, column=4, padx=8, pady=6)
        upload.columnconfigure(1, weight=1)

        opts = ttk.LabelFrame(frm, text="BirdNET 选项")
        opts.grid(row=4, column=0, columnspan=3, sticky="ew", **pad)
        ttk.Checkbutton(opts, text="对未识别音频启用 BirdNET", variable=self.birdnet_var).grid(row=0, column=0, sticky="w", padx=8, pady=6)
        ttk.Label(opts, text="最低置信度").grid(row=0, column=1, sticky="e")
        ttk.Entry(opts, textvariable=self.min_conf_var, width=8).grid(row=0, column=2, padx=6)
        ttk.Label(opts, text="线程").grid(row=0, column=3, sticky="e")
        ttk.Entry(opts, textvariable=self.threads_var, width=6).grid(row=0, column=4, padx=6)
        ttk.Label(opts, text="纬度").grid(row=1, column=0, sticky="e")
        ttk.Entry(opts, textvariable=self.lat_var, width=14).grid(row=1, column=1, padx=6, sticky="w")
        ttk.Label(opts, text="经度").grid(row=1, column=2, sticky="e")
        ttk.Entry(opts, textvariable=self.lon_var, width=14).grid(row=1, column=3, padx=6, sticky="w")
        ttk.Label(opts, text="周数(1-48)").grid(row=1, column=4, sticky="e")
        ttk.Entry(opts, textvariable=self.week_var, width=8).grid(row=1, column=5, padx=6, sticky="w")
        ttk.Button(opts, text="地图选点", command=self.open_map_picker).grid(row=1, column=6, padx=8, sticky="w")

        image_opts = ttk.LabelFrame(frm, text="图片识别 OSEA 选项")
        image_opts.grid(row=5, column=0, columnspan=3, sticky="ew", **pad)
        ttk.Checkbutton(image_opts, text="对未识别图片启用 OSEA", variable=self.osea_var).grid(row=0, column=0, sticky="w", padx=8, pady=6)
        ttk.Label(image_opts, text="最低置信度").grid(row=0, column=1, sticky="e")
        ttk.Entry(image_opts, textvariable=self.image_min_conf_var, width=8).grid(row=0, column=2, padx=6)
        ttk.Label(image_opts, text="模型").grid(row=1, column=0, sticky="e", padx=8, pady=4)
        ttk.Entry(image_opts, textvariable=self.osea_model_var).grid(row=1, column=1, columnspan=4, sticky="ew", padx=6, pady=4)
        ttk.Button(image_opts, text="选择", command=lambda: self.choose_file(self.osea_model_var)).grid(row=1, column=5, padx=6)
        ttk.Label(image_opts, text="标签").grid(row=2, column=0, sticky="e", padx=8, pady=4)
        ttk.Entry(image_opts, textvariable=self.osea_info_var).grid(row=2, column=1, columnspan=4, sticky="ew", padx=6, pady=4)
        ttk.Button(image_opts, text="选择", command=lambda: self.choose_file(self.osea_info_var)).grid(row=2, column=5, padx=6)
        image_opts.columnconfigure(1, weight=1)

        actions = ttk.Frame(frm)
        actions.grid(row=6, column=0, columnspan=3, sticky="ew", **pad)
        ttk.Button(actions, text="开始识别并压缩", command=self.start).pack(side="left")
        ttk.Button(actions, text="上传全部已确认", command=self.upload_all).pack(side="left", padx=8)
        ttk.Button(actions, text="上传选中已确认", command=self.upload_selected).pack(side="left")
        ttk.Button(actions, text="打开输出目录", command=self.open_output).pack(side="left", padx=8)
        ttk.Button(actions, text="打开上传网页", command=self.open_uploader).pack(side="left")
        ttk.Button(actions, text="上传历史/统计", command=self.open_history_window).pack(side="left", padx=8)

        review = ttk.LabelFrame(frm, text="审核记录")
        review.grid(row=7, column=0, columnspan=3, sticky="nsew", **pad)
        review_bar = ttk.Frame(review)
        review_bar.pack(fill="x", padx=8, pady=(8, 0))
        ttk.Label(review_bar, textvariable=self.stats_var).pack(side="left")
        ttk.Label(review_bar, text="筛选").pack(side="left", padx=(18, 6))
        filter_box = ttk.Combobox(
            review_bar,
            textvariable=self.filter_var,
            values=["全部", "待审核", "已确认", "未识别", "已上传", "已删除"],
            state="readonly",
            width=10,
        )
        filter_box.pack(side="left")
        filter_box.bind("<<ComboboxSelected>>", lambda _event: self.refresh_table())
        columns = ("active", "status", "species", "score", "method", "kind", "file")
        self.tree = ttk.Treeview(review, columns=columns, show="headings", height=10)
        for col, title, width in [
            ("active", "上传", 54),
            ("status", "状态", 82),
            ("species", "物种", 250),
            ("score", "分数", 70),
            ("method", "方法", 82),
            ("kind", "类型", 70),
            ("file", "文件", 420),
        ]:
            self.tree.heading(col, text=title)
            self.tree.column(col, width=width, anchor="w")
        self.tree.pack(side="left", fill="both", expand=True, padx=8, pady=8)
        scrollbar = ttk.Scrollbar(review, orient="vertical", command=self.tree.yview)
        scrollbar.pack(side="right", fill="y")
        self.tree.configure(yscrollcommand=scrollbar.set)
        self.tree.bind("<<TreeviewSelect>>", self.on_select_record)
        self.tree.bind("<Double-1>", self.open_review_view)
        review.rowconfigure(0, weight=1)

        edit = ttk.Frame(frm)
        edit.grid(row=8, column=0, columnspan=3, sticky="ew", **pad)
        ttk.Label(edit, text="改为物种").pack(side="left")
        ttk.Entry(edit, textvariable=self.edit_species_var, width=42).pack(side="left", padx=8)
        ttk.Button(edit, text="应用到选中", command=self.apply_species_to_selected).pack(side="left")
        ttk.Button(edit, text="删除选中", command=self.delete_selected).pack(side="left", padx=8)
        ttk.Button(edit, text="恢复选中", command=self.restore_selected).pack(side="left")
        ttk.Button(edit, text="打开原文件", command=self.open_selected_file).pack(side="left", padx=8)
        ttk.Button(edit, text="审核视图", command=self.open_review_view).pack(side="left")

        self.log_text = tk.Text(frm, height=8)
        self.log_text.grid(row=9, column=0, columnspan=3, sticky="nsew", **pad)
        frm.rowconfigure(7, weight=3)
        frm.rowconfigure(9, weight=1)
        frm.columnconfigure(1, weight=1)

        self.log(f"Birdaholic 本地媒体助手 v{APP_VERSION}")
        installed = "已安装（内置引擎）" if bundled_birdnet_engine_path() else "已安装" if birdnet_available() else "未安装"
        self.log(f"BirdNET 状态：{installed}")
        if not birdnet_available():
            self.log("安装命令：python3 -m pip install birdnet-analyzer")
        osea_status = "已安装" if osea_available(Path(self.osea_model_var.get()), Path(self.osea_info_var.get())) else "未安装"
        self.log(f"OSEA 图片识别状态：{osea_status}")
        if osea_status == "未安装":
            self.log("OSEA 需要 models/osea/bird_model.onnx、bird_info.json，以及 onnxruntime/pillow/numpy。")

    def _path_row(self, parent, label, variable, row, file=False):
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="w", padx=12, pady=6)
        ttk.Entry(parent, textvariable=variable).grid(row=row, column=1, sticky="ew", padx=12, pady=6)
        command = (lambda: self.choose_file(variable)) if file else (lambda: self.choose_dir(variable))
        ttk.Button(parent, text="选择", command=command).grid(row=row, column=2, padx=12, pady=6)

    def choose_dir(self, variable):
        path = filedialog.askdirectory()
        if path:
            variable.set(path)

    def choose_file(self, variable):
        path = filedialog.askopenfilename()
        if path:
            variable.set(path)

    def log(self, message: str):
        if threading.get_ident() != self.main_thread_id or not hasattr(self, "log_text"):
            self.ui_queue.put(("log", message))
            return
        self.log_text.insert("end", message + "\n")
        self.log_text.see("end")
        self.update_idletasks()

    def show_error(self, title: str, message: str):
        if threading.get_ident() != self.main_thread_id:
            self.ui_queue.put(("error", (title, message)))
            return
        messagebox.showerror(title, message)

    def post_ui(self, callback, *args):
        self.ui_queue.put(("call", (callback, args)))

    def drain_ui_queue(self):
        while True:
            try:
                kind, payload = self.ui_queue.get_nowait()
            except queue.Empty:
                break
            if kind == "log":
                self.log(str(payload))
            elif kind == "error":
                title, message = payload
                messagebox.showerror(title, message)
            elif kind == "call":
                callback, args = payload
                callback(*args)
        self.after(80, self.drain_ui_queue)

    def open_map_picker(self):
        if self.map_server is None:
            app = self

            class MapHandler(http.server.BaseHTTPRequestHandler):
                def log_message(self, _format, *args):
                    return

                def do_GET(self):
                    parsed = urllib.parse.urlparse(self.path)
                    if parsed.path == "/set":
                        query = urllib.parse.parse_qs(parsed.query)
                        lat = (query.get("lat") or [""])[0]
                        lon = (query.get("lon") or [""])[0]
                        app.after(0, lambda: app.set_map_coordinates(lat, lon))
                        self.send_response(200)
                        self.send_header("Content-Type", "text/plain; charset=utf-8")
                        self.end_headers()
                        self.wfile.write("坐标已写入 Birdaholic 本地媒体助手，可以回到 App。".encode("utf-8"))
                        return
                    html = app.map_html()
                    self.send_response(200)
                    self.send_header("Content-Type", "text/html; charset=utf-8")
                    self.end_headers()
                    self.wfile.write(html.encode("utf-8"))

            self.map_server = socketserver.TCPServer(("127.0.0.1", 0), MapHandler)
            threading.Thread(target=self.map_server.serve_forever, daemon=True).start()
        port = self.map_server.server_address[1]
        subprocess.run(["open", f"http://127.0.0.1:{port}/"])
        self.log("已打开地图选点；在地图上点击位置后，经纬度会自动填入。")

    def set_map_coordinates(self, lat: str, lon: str):
        try:
            self.lat_var.set(f"{float(lat):.6f}")
            self.lon_var.set(f"{float(lon):.6f}")
            self.log(f"地图选点：{self.lat_var.get()}, {self.lon_var.get()}")
        except ValueError:
            self.log("地图返回的坐标无效。")

    def map_html(self) -> str:
        lat = self.lat_var.get().strip() or "-43.5321"
        lon = self.lon_var.get().strip() or "172.6362"
        return f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Birdaholic 地图选点</title>
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
  <style>
    html, body, #map {{ height: 100%; margin: 0; }}
    .panel {{
      position: fixed; z-index: 1000; top: 12px; left: 12px;
      background: white; padding: 10px 12px; border-radius: 8px;
      box-shadow: 0 2px 14px rgba(0,0,0,.22); font: 14px -apple-system, BlinkMacSystemFont, sans-serif;
    }}
    .coords {{ margin-top: 6px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }}
  </style>
</head>
<body>
  <div class="panel">
    <b>点击地图选择录音地点</b>
    <div>坐标会自动回填到 Birdaholic 本地媒体助手。</div>
    <div class="coords" id="coords">等待点击...</div>
  </div>
  <div id="map"></div>
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <script>
    const map = L.map('map').setView([{lat}, {lon}], 7);
    L.tileLayer('https://tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png', {{
      maxZoom: 19,
      attribution: '&copy; OpenStreetMap'
    }}).addTo(map);
    let marker = L.marker([{lat}, {lon}]).addTo(map);
    async function choose(e) {{
      const lat = e.latlng.lat.toFixed(6);
      const lon = e.latlng.lng.toFixed(6);
      marker.setLatLng(e.latlng);
      document.getElementById('coords').textContent = lat + ', ' + lon + ' 已写入';
      await fetch('/set?lat=' + encodeURIComponent(lat) + '&lon=' + encodeURIComponent(lon));
    }}
    map.on('click', choose);
  </script>
</body>
</html>"""

    def start(self):
        self._run(should_upload=False)

    def start_upload(self):
        self._run(should_upload=True)

    def _run(self, should_upload: bool):
        def worker():
            try:
                matcher = SpeciesMatcher(Path(self.world_var.get()))
                decisions = process_media(
                    input_dir=Path(self.input_var.get()),
                    output_dir=Path(self.output_var.get()),
                    world_birds=Path(self.world_var.get()),
                    use_birdnet=self.birdnet_var.get(),
                    use_osea=self.osea_var.get(),
                    min_conf=float(self.min_conf_var.get() or 0.30),
                    image_min_conf=float(self.image_min_conf_var.get() or 0.15),
                    threads=int(self.threads_var.get() or 2),
                    lat=self.lat_var.get(),
                    lon=self.lon_var.get(),
                    week=self.week_var.get(),
                    osea_model=Path(self.osea_model_var.get()),
                    osea_info=Path(self.osea_info_var.get()),
                    log=self.log,
                )
                self.post_ui(self.after_process_success, decisions, matcher)
                if should_upload or self.auto_upload_var.get():
                    uploaded = upload_decisions(
                        decisions=decisions,
                        token=self.token_var.get(),
                        server_url=self.server_var.get(),
                        log=self.log,
                    )
                    self.post_ui(self.after_upload_success, uploaded)
            except Exception as exc:
                self.log(f"失败：{exc}")
                self.show_error("处理失败", str(exc))

        threading.Thread(target=worker, daemon=True).start()

    def after_process_success(self, decisions: list[MediaDecision], matcher: SpeciesMatcher):
        self.matcher = matcher
        self.decisions = decisions
        self.save_current_state()
        self.refresh_table()

    def refresh_table(self):
        for item_id in self.tree.get_children():
            self.tree.delete(item_id)
        selected_filter = self.filter_var.get()
        for index, item in enumerate(self.decisions):
            if not self.matches_filter(item, selected_filter):
                continue
            species = f"{item.zh or item.en} · {item.sci}" if item.sci else "未识别"
            self.tree.insert(
                "",
                "end",
                iid=str(index),
                values=(
                    "是" if item.active else "否",
                    item.status,
                    species,
                    f"{item.score:.2f}",
                    item.method,
                    "音频" if item.kind == "audio" else "图片",
                    item.src.name,
                ),
            )
        self.update_stats()

    def matches_filter(self, item: MediaDecision, selected_filter: str) -> bool:
        if selected_filter == "待审核":
            return item.status == "candidate"
        if selected_filter == "已确认":
            return item.status == "confirmed"
        if selected_filter == "未识别":
            return item.status == "unrecognized"
        if selected_filter == "已上传":
            return item.status == "uploaded"
        if selected_filter == "已删除":
            return item.status == "deleted"
        return True

    def update_stats(self):
        counts = {status: 0 for status in ["candidate", "confirmed", "unrecognized", "uploaded", "deleted"]}
        for item in self.decisions:
            counts[item.status] = counts.get(item.status, 0) + 1
        self.stats_var.set(
            f"共 {len(self.decisions)} 条｜待审核 {counts.get('candidate', 0)}｜已确认 {counts.get('confirmed', 0)}｜未识别 {counts.get('unrecognized', 0)}｜已上传 {counts.get('uploaded', 0)}"
        )

    def save_current_state(self):
        if self.decisions:
            write_outputs(self.decisions, Path(self.output_var.get()))

    def load_saved_state(self):
        try:
            decisions = load_state(Path(self.output_var.get()))
        except Exception as exc:
            self.log(f"恢复上次进度失败：{exc}")
            return
        if not decisions:
            return
        self.decisions = decisions
        self.refresh_table()
        self.log(f"已恢复上次审核进度：{len(decisions)} 条记录")

    def selected_indices(self) -> list[int]:
        return [int(item_id) for item_id in self.tree.selection()]

    def on_select_record(self, _event=None):
        indices = self.selected_indices()
        if not indices:
            return
        item = self.decisions[indices[0]]
        self.edit_species_var.set(item.sci or item.en or item.zh)

    def resolve_species_for_edit(self, text: str) -> dict[str, Any]:
        if self.matcher is None:
            self.matcher = SpeciesMatcher(Path(self.world_var.get()))
        item, score = self.matcher.by_scientific_or_label(text)
        if item is None:
            item, score = self.matcher.match(text, threshold=0.65)
        if item is None:
            raise RuntimeError(f"找不到物种：{text}")
        return item

    def apply_species_to_selected(self):
        indices = self.selected_indices()
        if not indices:
            messagebox.showinfo("没有选择", "请先在表格里选择一条或多条记录。")
            return
        try:
            species = self.resolve_species_for_edit(self.edit_species_var.get())
            for index in indices:
                self.reassign_decision(self.decisions[index], species)
            write_outputs(self.decisions, Path(self.output_var.get()))
            self.refresh_table()
            self.log(f"已把 {len(indices)} 条记录改为 {species.get('sci')}")
        except Exception as exc:
            self.log(f"修改失败：{exc}")
            messagebox.showerror("修改失败", str(exc))

    def reassign_decision(self, decision: MediaDecision, species: dict[str, Any]):
        sci = species["sci"]
        output_dir = Path(self.output_var.get())
        dst = output_dir / species_key(sci) / decision.kind / safe_name(
            decision.src,
            sci,
            decision.kind,
        )
        if decision.kind == "images":
            output = optimize_image(decision.src, dst, max_image=1600, jpeg_quality=70)
        else:
            output = optimize_audio(decision.src, dst, bitrate="64k")
        decision.status = "confirmed"
        decision.sci = sci
        decision.zh = species.get("zh", "")
        decision.en = species.get("en", "")
        decision.score = 1
        decision.method = "manual"
        decision.output = str(output)
        decision.active = True

    def delete_selected(self):
        indices = self.selected_indices()
        for index in indices:
            self.decisions[index].active = False
            self.decisions[index].status = "deleted"
        write_outputs(self.decisions, Path(self.output_var.get()))
        self.refresh_table()
        self.log(f"已删除 {len(indices)} 条记录，不会上传。")

    def restore_selected(self):
        indices = self.selected_indices()
        for index in indices:
            self.decisions[index].active = True
            if self.decisions[index].sci:
                self.decisions[index].status = "confirmed"
        write_outputs(self.decisions, Path(self.output_var.get()))
        self.refresh_table()

    def open_selected_file(self):
        indices = self.selected_indices()
        if not indices:
            return
        subprocess.run(["open", str(self.decisions[indices[0]].src)])

    def open_review_view(self, _event=None):
        indices = self.selected_indices()
        if indices:
            self.review_index = indices[0]
        else:
            for idx, item in enumerate(self.decisions):
                if item.status in {"candidate", "unrecognized"}:
                    self.review_index = idx
                    break
            else:
                self.review_index = 0
        if not self.decisions:
            messagebox.showinfo("没有选择", "请先选择一条记录。")
            return
        if self.review_win is None or not self.review_win.winfo_exists():
            self.build_review_window()
        self.review_win.deiconify()
        self.review_win.lift()
        self.render_review_record()

    def build_review_window(self):
        win = tk.Toplevel(self)
        self.review_win = win
        win.title("连续审核")
        win.geometry("1240x760")
        win.columnconfigure(0, weight=3)
        win.columnconfigure(1, weight=2)
        win.rowconfigure(0, weight=1)
        win.protocol("WM_DELETE_WINDOW", win.withdraw)

        left = ttk.Frame(win, padding=10)
        left.grid(row=0, column=0, sticky="nsew")
        left.rowconfigure(0, weight=1)
        left.columnconfigure(0, weight=1)
        self.review_canvas = tk.Canvas(left, bg="#171717", highlightthickness=0)
        self.review_canvas.grid(row=0, column=0, sticky="nsew")
        ttk.Label(left, textvariable=self.review_info_var, padding=(0, 8)).grid(row=1, column=0, sticky="ew")
        self.review_canvas.bind("<Configure>", lambda _event: self.render_review_preview())

        right = ttk.Frame(win, padding=10)
        right.grid(row=0, column=1, sticky="nsew")
        right.columnconfigure(0, weight=1)
        right.rowconfigure(8, weight=1)

        ttk.Label(right, textvariable=self.review_species_var, font=("TkDefaultFont", 15, "bold")).grid(row=0, column=0, sticky="ew")
        self.review_candidate_frame = ttk.LabelFrame(right, text="候选物种")
        self.review_candidate_frame.grid(row=1, column=0, sticky="ew", pady=(10, 8))

        control = ttk.Frame(right)
        control.grid(row=2, column=0, sticky="ew", pady=(0, 10))
        ttk.Button(control, text="确认并下一条", command=self.confirm_review_and_next).pack(side="left")
        ttk.Button(control, text="删除并下一条", command=self.delete_review_and_next).pack(side="left", padx=8)
        ttk.Button(control, text="跳过", command=lambda: self.move_review(1)).pack(side="left")

        nav = ttk.Frame(right)
        nav.grid(row=3, column=0, sticky="ew")
        ttk.Button(nav, text="上一条", command=lambda: self.move_review(-1)).pack(side="left")
        ttk.Button(nav, text="下一条", command=lambda: self.move_review(1)).pack(side="left", padx=8)
        ttk.Button(nav, text="打开原文件", command=self.open_review_source).pack(side="left")
        ttk.Button(nav, text="结束审核", command=self.finish_review).pack(side="right")

        ttk.Separator(right).grid(row=4, column=0, sticky="ew", pady=10)
        region = ttk.LabelFrame(right, text="地区筛选")
        region.grid(row=5, column=0, sticky="ew", pady=(0, 8))
        region.columnconfigure(1, weight=1)
        ttk.Label(region, text="国家").grid(row=0, column=0, sticky="w", padx=8, pady=4)
        country_box = ttk.Combobox(region, textvariable=self.review_country_var, values=COUNTRY_OPTIONS, state="readonly", width=16)
        country_box.grid(row=0, column=1, sticky="ew", padx=6, pady=4)
        country_box.bind("<<ComboboxSelected>>", lambda _event: self.apply_review_region_filter())
        ttk.Button(region, text="用地图坐标", command=self.apply_map_region_filter).grid(row=0, column=2, padx=6, pady=4)
        ttk.Button(region, text="全球", command=self.clear_review_region_filter).grid(row=0, column=3, padx=6, pady=4)
        ttk.Label(region, text="eBird Token").grid(row=1, column=0, sticky="w", padx=8, pady=4)
        ttk.Entry(region, textvariable=self.ebird_token_var, show="*", width=20).grid(row=1, column=1, sticky="ew", padx=6, pady=4)
        ttk.Label(region, textvariable=self.region_status_var).grid(row=2, column=0, columnspan=4, sticky="w", padx=8, pady=(0, 6))

        ttk.Label(right, text="手动搜索：中文 / English / Latin / eBird code / 拼音首字母").grid(row=6, column=0, sticky="w")
        entry = ttk.Entry(right, textvariable=self.review_search_var)
        entry.grid(row=7, column=0, sticky="ew", pady=6)
        entry.bind("<Return>", lambda _event: self.apply_review_search_result())
        self.review_search_var.trace_add("write", lambda *_args: self.schedule_review_search())
        self.review_result_box = tk.Listbox(right, height=11)
        self.review_result_box.grid(row=8, column=0, sticky="nsew")
        self.review_result_box.bind("<Double-1>", lambda _event: self.apply_review_search_result())
        ttk.Button(right, text="选用搜索结果并下一条", command=self.apply_review_search_result).grid(row=9, column=0, sticky="ew", pady=8)

    def current_review_decision(self) -> MediaDecision | None:
        if not self.decisions:
            return None
        self.review_index = max(0, min(self.review_index, len(self.decisions) - 1))
        return self.decisions[self.review_index]

    def render_review_record(self):
        decision = self.current_review_decision()
        if decision is None:
            return
        species = f"{decision.zh or decision.en or '未识别'} · {decision.sci}" if decision.sci else "未识别"
        self.review_species_var.set(species)
        self.review_info_var.set(
            f"{self.review_index + 1}/{len(self.decisions)}  {decision.src.name}\n"
            f"{decision.status} · {decision.method or '-'} · {decision.score:.3f} · {'音频' if decision.kind == 'audio' else '图片'}"
        )
        self.review_search_var.set(decision.sci or decision.en or decision.zh)
        self.render_review_candidates()
        self.render_review_preview()
        self.select_tree_index(self.review_index)

    def render_review_candidates(self):
        if self.review_candidate_frame is None:
            return
        for child in self.review_candidate_frame.winfo_children():
            child.destroy()
        decision = self.current_review_decision()
        if decision is None:
            return
        rows = decision.candidates or (
            [{"sci": decision.sci, "zh": decision.zh, "en": decision.en, "score": decision.score, "method": decision.method}]
            if decision.sci
            else []
        )
        if not rows:
            ttk.Label(self.review_candidate_frame, text="没有候选，请用下面搜索手动指定。").grid(row=0, column=0, sticky="w", padx=8, pady=8)
            return
        for row, candidate in enumerate(rows[:6]):
            ttk.Label(self.review_candidate_frame, text=self.format_candidate(candidate), wraplength=420).grid(row=row, column=0, sticky="w", padx=8, pady=4)
            ttk.Button(
                self.review_candidate_frame,
                text="选用并下一条",
                command=lambda c=candidate: self.apply_review_candidate(c),
            ).grid(row=row, column=1, padx=8, pady=4)

    def render_review_preview(self):
        decision = self.current_review_decision()
        canvas = self.review_canvas
        if decision is None or canvas is None:
            return
        if decision.kind == "images":
            self.draw_image_preview(canvas, decision.src)
        else:
            self.draw_audio_waveform(canvas, decision.src)

    def schedule_review_search(self):
        if self.review_search_after_id:
            self.after_cancel(self.review_search_after_id)
        self.review_search_after_id = self.after(250, self.refresh_review_search)

    def refresh_review_search(self):
        self.review_search_after_id = None
        box = self.review_result_box
        if box is None:
            return
        box.delete(0, "end")
        query = self.review_search_var.get()
        if len(query.strip()) < 1:
            self.review_search_results = []
            return
        if self.matcher is None:
            self.matcher = SpeciesMatcher(Path(self.world_var.get()))
        self.review_search_results = [
            item
            for item, _score in self.matcher.search(query, limit=20, allowed_codes=self.review_allowed_codes)
        ]
        for item in self.review_search_results:
            box.insert("end", f"{item.get('zh') or item.get('en')} · {item.get('en')} · {item.get('sci')}")

    def set_review_region(self, region: str):
        region = region.strip().upper()
        if not region:
            self.review_allowed_codes = None
            self.region_status_var.set("搜索地区：全球")
            self.schedule_review_search()
            return
        try:
            codes = fetch_ebird_species_codes(region, self.ebird_token_var.get())
        except Exception as exc:
            self.review_allowed_codes = None
            self.region_status_var.set(f"搜索地区：{region} 获取失败，已回退全球")
            self.log(f"地区筛选获取失败：{region} {exc}")
            self.schedule_review_search()
            return
        self.review_allowed_codes = codes or None
        self.region_status_var.set(f"搜索地区：{region}（{len(codes)} 种）")
        self.log(f"地区筛选：{region}，{len(codes)} 种")
        self.schedule_review_search()

    def apply_review_region_filter(self):
        self.set_review_region(country_code_from_option(self.review_country_var.get()))

    def clear_review_region_filter(self):
        self.review_country_var.set("全球")
        self.set_review_region("")

    def apply_map_region_filter(self):
        code = country_code_from_coordinates(self.lat_var.get(), self.lon_var.get())
        if not code:
            messagebox.showinfo("无法判断地区", "当前经纬度没有匹配到内置国家范围，请手动选择国家。")
            return
        for option in COUNTRY_OPTIONS:
            if option.endswith(f" {code}"):
                self.review_country_var.set(option)
                break
        self.set_review_region(code)

    def select_tree_index(self, index: int):
        item_id = str(index)
        if item_id in self.tree.get_children():
            self.tree.selection_set(item_id)
            self.tree.see(item_id)

    def mark_review_confirmed(self):
        decision = self.current_review_decision()
        if decision is None:
            return False
        if not decision.sci:
            messagebox.showinfo("不能确认", "这条还没有物种，请先选候选或手动搜索。")
            return False
        decision.status = "confirmed"
        decision.active = True
        if decision.method and not decision.method.endswith("_confirmed"):
            decision.method = f"{decision.method}_confirmed"
        write_outputs(self.decisions, Path(self.output_var.get()))
        self.refresh_table()
        return True

    def confirm_review_and_next(self):
        if self.mark_review_confirmed():
            self.log(f"已确认：{self.current_review_decision().sci}")
            self.move_review(1)

    def delete_review_and_next(self):
        if not self.decisions:
            return
        self.mark_deleted(self.review_index)
        self.move_review(1)

    def apply_review_candidate(self, candidate: dict[str, Any]):
        decision = self.current_review_decision()
        if decision is None:
            return
        if self.matcher is None:
            self.matcher = SpeciesMatcher(Path(self.world_var.get()))
        item, _score = self.matcher.by_scientific_or_label(str(candidate.get("sci") or candidate.get("en") or candidate.get("zh") or ""))
        if item is None:
            messagebox.showerror("无法选用", "这个候选没有匹配到世界鸟类名录。")
            return
        self.reassign_decision(decision, item)
        decision.score = float(candidate.get("score", 1))
        decision.method = f"{candidate.get('method') or 'candidate'}_confirmed"
        write_outputs(self.decisions, Path(self.output_var.get()))
        self.refresh_table()
        self.log(f"已确认：{item.get('sci')}")
        self.move_review(1)

    def apply_review_search_result(self):
        box = self.review_result_box
        decision = self.current_review_decision()
        if box is None or decision is None:
            return
        selection = box.curselection()
        if not selection:
            return
        self.reassign_decision(decision, self.review_search_results[selection[0]])
        decision.method = "manual_confirmed"
        write_outputs(self.decisions, Path(self.output_var.get()))
        self.refresh_table()
        self.log(f"已手动确认：{decision.sci}")
        self.move_review(1)

    def move_review(self, step: int):
        if not self.decisions:
            return
        index = self.review_index + step
        while 0 <= index < len(self.decisions):
            if self.decisions[index].status not in {"uploaded", "deleted"}:
                self.review_index = index
                self.render_review_record()
                return
            index += step
        if step > 0:
            self.finish_review(completed=True)
            return
        messagebox.showinfo("已经到第一条", "前面没有更多可审核记录。")
        self.render_review_record()

    def finish_review(self, completed: bool = False):
        pending = sum(1 for item in self.decisions if item.status in {"candidate", "unrecognized"})
        confirmed = sum(1 for item in self.decisions if item.status == "confirmed")
        if self.review_win is not None and self.review_win.winfo_exists():
            self.review_win.withdraw()
        self.refresh_table()
        if completed:
            messagebox.showinfo("审核到末尾", f"已到最后一条。\n已确认 {confirmed} 条，待处理 {pending} 条。")
        else:
            self.log(f"已结束审核：已确认 {confirmed} 条，待处理 {pending} 条。")

    def open_review_source(self):
        decision = self.current_review_decision()
        if decision is not None:
            subprocess.run(["open", str(decision.src)])

    def open_image_review(self, index: int):
        decision = self.decisions[index]
        win = tk.Toplevel(self)
        win.title("图片审核")
        win.geometry("1180x760")
        win.columnconfigure(0, weight=3)
        win.columnconfigure(1, weight=2)
        win.rowconfigure(0, weight=1)

        left = ttk.Frame(win, padding=10)
        left.grid(row=0, column=0, sticky="nsew")
        left.rowconfigure(0, weight=1)
        left.columnconfigure(0, weight=1)
        canvas = tk.Canvas(left, bg="#202020", highlightthickness=0)
        canvas.grid(row=0, column=0, sticky="nsew")
        info = ttk.Label(left, text=f"{decision.src.name}\n{decision.status} · {decision.method} · {decision.score:.3f}")
        info.grid(row=1, column=0, sticky="ew", pady=(8, 0))

        self.draw_image_preview(canvas, decision.src)
        canvas.bind("<Configure>", lambda _event: self.draw_image_preview(canvas, decision.src))

        right = ttk.Frame(win, padding=10)
        right.grid(row=0, column=1, sticky="nsew")
        right.columnconfigure(0, weight=1)
        ttk.Label(right, text="候选物种").grid(row=0, column=0, sticky="w")
        candidates = ttk.Frame(right)
        candidates.grid(row=1, column=0, sticky="ew", pady=(8, 12))
        candidates.columnconfigure(0, weight=1)

        rows = decision.candidates or (
            [{"sci": decision.sci, "zh": decision.zh, "en": decision.en, "score": decision.score, "method": decision.method}]
            if decision.sci
            else []
        )
        for row, candidate in enumerate(rows[:6]):
            text = self.format_candidate(candidate)
            ttk.Label(candidates, text=text, wraplength=390).grid(row=row, column=0, sticky="w", pady=3)
            ttk.Button(
                candidates,
                text="选用",
                command=lambda c=candidate, w=win: self.apply_candidate(index, c, w),
            ).grid(row=row, column=1, padx=8, pady=3)

        ttk.Separator(right).grid(row=2, column=0, sticky="ew", pady=8)
        ttk.Label(right, text="手动搜索：中文 / English / Latin / eBird code / 拼音首字母").grid(row=3, column=0, sticky="w")
        query_var = tk.StringVar(value=decision.sci or decision.en or decision.zh)
        ttk.Entry(right, textvariable=query_var).grid(row=4, column=0, sticky="ew", pady=6)
        result_box = tk.Listbox(right, height=10)
        result_box.grid(row=5, column=0, sticky="nsew")
        right.rowconfigure(5, weight=1)
        search_results: list[dict[str, Any]] = []

        def refresh_search(_event=None):
            nonlocal search_results
            result_box.delete(0, "end")
            if self.matcher is None:
                self.matcher = SpeciesMatcher(Path(self.world_var.get()))
            search_results = [item for item, _score in self.matcher.search(query_var.get(), limit=20)]
            for item in search_results:
                result_box.insert("end", f"{item.get('zh') or item.get('en')} · {item.get('en')} · {item.get('sci')}")

        def apply_manual():
            selection = result_box.curselection()
            if not selection:
                return
            self.reassign_decision(decision, search_results[selection[0]])
            write_outputs(self.decisions, Path(self.output_var.get()))
            self.refresh_table()
            win.destroy()
            self.log(f"图片已手动确认：{decision.sci}")

        query_var.trace_add("write", lambda *_args: refresh_search())
        refresh_search()
        buttons = ttk.Frame(right)
        buttons.grid(row=6, column=0, sticky="ew", pady=8)
        ttk.Button(buttons, text="选用搜索结果", command=apply_manual).pack(side="left")
        ttk.Button(buttons, text="删除这张", command=lambda: (self.mark_deleted(index), win.destroy())).pack(side="left", padx=8)
        ttk.Button(buttons, text="打开原图", command=lambda: subprocess.run(["open", str(decision.src)])).pack(side="left")

    def draw_image_preview(self, canvas: tk.Canvas, path: Path):
        try:
            from PIL import Image, ImageOps, ImageTk

            width = max(canvas.winfo_width(), 640)
            height = max(canvas.winfo_height(), 480)
            img = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
            img.thumbnail((width - 20, height - 20), Image.Resampling.LANCZOS)
            photo = ImageTk.PhotoImage(img)
            canvas.delete("all")
            canvas.create_image(width // 2, height // 2, image=photo)
            canvas.image = photo
        except Exception as exc:
            canvas.delete("all")
            canvas.create_text(20, 20, anchor="nw", fill="white", text=f"无法预览图片：{exc}")

    def format_candidate(self, candidate: dict[str, Any]) -> str:
        names = [candidate.get("zh", ""), candidate.get("en", ""), candidate.get("sci", "")]
        label = " / ".join([str(name) for name in names if name])
        return f"{label}\n可信度 {float(candidate.get('score', 0)):.3f}"

    def apply_candidate(self, index: int, candidate: dict[str, Any], win: tk.Toplevel):
        if self.matcher is None:
            self.matcher = SpeciesMatcher(Path(self.world_var.get()))
        item, _score = self.matcher.by_scientific_or_label(str(candidate.get("sci") or candidate.get("en") or candidate.get("zh") or ""))
        if item is None:
            messagebox.showerror("无法选用", "这个候选没有匹配到世界鸟类名录。")
            return
        self.reassign_decision(self.decisions[index], item)
        self.decisions[index].score = float(candidate.get("score", 1))
        self.decisions[index].method = "osea_confirmed"
        write_outputs(self.decisions, Path(self.output_var.get()))
        self.refresh_table()
        win.destroy()
        self.log(f"已确认图片：{item.get('sci')}")

    def mark_deleted(self, index: int):
        self.decisions[index].active = False
        self.decisions[index].status = "deleted"
        write_outputs(self.decisions, Path(self.output_var.get()))
        self.refresh_table()

    def open_audio_review(self, index: int):
        decision = self.decisions[index]
        win = tk.Toplevel(self)
        win.title("音频审核")
        win.geometry("1000x520")
        win.columnconfigure(0, weight=1)
        win.rowconfigure(1, weight=1)
        ttk.Label(win, text=f"{decision.src.name} · {decision.status} · {decision.method} · {decision.score:.3f}", padding=10).grid(row=0, column=0, sticky="ew")
        canvas = tk.Canvas(win, bg="#151515", highlightthickness=0)
        canvas.grid(row=1, column=0, sticky="nsew", padx=10, pady=6)
        buttons = ttk.Frame(win, padding=10)
        buttons.grid(row=2, column=0, sticky="ew")
        ttk.Button(buttons, text="播放/打开音频", command=lambda: subprocess.run(["open", str(decision.src)])).pack(side="left")
        ttk.Button(buttons, text="确认当前物种", command=lambda: self.confirm_current_audio(index, win)).pack(side="left", padx=8)
        ttk.Button(buttons, text="删除这条", command=lambda: (self.mark_deleted(index), win.destroy())).pack(side="left")
        self.draw_audio_waveform(canvas, decision.src)
        canvas.bind("<Configure>", lambda _event: self.draw_audio_waveform(canvas, decision.src))

    def confirm_current_audio(self, index: int, win: tk.Toplevel):
        decision = self.decisions[index]
        if not decision.sci:
            messagebox.showinfo("不能确认", "这条音频还没有物种，请先手动指定。")
            return
        decision.status = "confirmed"
        decision.active = True
        write_outputs(self.decisions, Path(self.output_var.get()))
        self.refresh_table()
        win.destroy()

    def draw_audio_waveform(self, canvas: tk.Canvas, path: Path):
        canvas.delete("all")
        width = max(canvas.winfo_width(), 800)
        height = max(canvas.winfo_height(), 320)
        samples = read_audio_samples(path, width)
        if not samples:
            canvas.create_text(20, 20, anchor="nw", fill="white", text="无法生成波形；可点击播放/打开音频试听。")
            return
        mid = height // 2
        canvas.create_line(0, mid, width, mid, fill="#444")
        for x, amp in enumerate(samples):
            y = max(1, int(amp * (height * 0.45)))
            color = "#7fd1ff" if amp < 0.75 else "#ffcc66"
            canvas.create_line(x, mid - y, x, mid + y, fill=color)


    def upload_all(self):
        self._upload_decisions(self.decisions)

    def upload_selected(self):
        indices = self.selected_indices()
        if not indices:
            messagebox.showinfo("没有选择", "请先选择要上传的记录。")
            return
        self._upload_decisions([self.decisions[index] for index in indices])

    def _upload_decisions(self, decisions: list[MediaDecision]):
        def worker():
            try:
                uploaded = upload_decisions(
                    decisions=decisions,
                    token=self.token_var.get(),
                    server_url=self.server_var.get(),
                    log=self.log,
                )
                self.post_ui(self.after_upload_success, uploaded)
            except Exception as exc:
                self.log(f"上传失败：{exc}")
                self.show_error("上传失败", str(exc))

        threading.Thread(target=worker, daemon=True).start()

    def after_upload_success(self, uploaded_sources: set[Path]):
        if not uploaded_sources:
            return
        append_upload_history(self.decisions, uploaded_sources, Path(self.output_var.get()))
        moved: dict[Path, Path] = {}
        if self.move_uploaded_var.get():
            moved = move_uploaded_sources(
                uploaded_sources,
                Path(self.uploaded_dir_var.get()),
                self.log,
            )
        for item in self.decisions:
            if item.src in uploaded_sources:
                item.status = "uploaded"
                item.active = False
                if item.src in moved:
                    item.src = moved[item.src]
        write_outputs(self.decisions, Path(self.output_var.get()))
        self.refresh_table()
        if self.history_win is not None and self.history_win.winfo_exists():
            self.refresh_local_history()

    def open_history_window(self):
        if self.history_win is not None and self.history_win.winfo_exists():
            self.history_win.deiconify()
            self.history_win.lift()
            self.refresh_local_history()
            return
        win = tk.Toplevel(self)
        self.history_win = win
        win.title("上传历史 / 服务器统计")
        win.geometry("1120x720")
        win.protocol("WM_DELETE_WINDOW", win.withdraw)

        notebook = ttk.Notebook(win)
        notebook.pack(fill="both", expand=True, padx=10, pady=10)

        local_tab = ttk.Frame(notebook, padding=8)
        server_tab = ttk.Frame(notebook, padding=8)
        notebook.add(local_tab, text="本地上传历史")
        notebook.add(server_tab, text="服务器统计")

        local_tab.rowconfigure(0, weight=1)
        local_tab.columnconfigure(0, weight=1)
        self.history_tree = ttk.Treeview(
            local_tab,
            columns=("time", "species", "kind", "method", "file"),
            show="headings",
            height=18,
        )
        for col, title, width in [
            ("time", "上传时间", 150),
            ("species", "物种", 280),
            ("kind", "类型", 70),
            ("method", "方法", 120),
            ("file", "原文件", 480),
        ]:
            self.history_tree.heading(col, text=title)
            self.history_tree.column(col, width=width, anchor="w")
        self.history_tree.grid(row=0, column=0, sticky="nsew")
        local_scroll = ttk.Scrollbar(local_tab, orient="vertical", command=self.history_tree.yview)
        local_scroll.grid(row=0, column=1, sticky="ns")
        self.history_tree.configure(yscrollcommand=local_scroll.set)
        local_buttons = ttk.Frame(local_tab)
        local_buttons.grid(row=1, column=0, columnspan=2, sticky="ew", pady=8)
        ttk.Button(local_buttons, text="刷新本地历史", command=self.refresh_local_history).pack(side="left")
        ttk.Button(local_buttons, text="打开输出目录", command=self.open_output).pack(side="left", padx=8)

        top = ttk.Frame(server_tab)
        top.pack(fill="x")
        ttk.Label(top, textvariable=self.server_stats_summary_var).pack(side="left")
        ttk.Label(top, text="搜索").pack(side="left", padx=(18, 6))
        search_entry = ttk.Entry(top, textvariable=self.server_stats_query_var, width=28)
        search_entry.pack(side="left")
        search_entry.bind("<Return>", lambda _event: self.refresh_server_stats())
        ttk.Button(top, text="刷新服务器统计", command=self.refresh_server_stats).pack(side="left", padx=8)

        table_frame = ttk.Frame(server_tab)
        table_frame.pack(fill="both", expand=True, pady=(8, 0))
        table_frame.rowconfigure(0, weight=1)
        table_frame.columnconfigure(0, weight=1)
        self.server_stats_tree = ttk.Treeview(
            table_frame,
            columns=("species", "images", "audio", "dir"),
            show="headings",
            height=18,
        )
        for col, title, width in [
            ("species", "物种", 420),
            ("images", "图片", 80),
            ("audio", "音频", 80),
            ("dir", "服务器目录", 380),
        ]:
            self.server_stats_tree.heading(col, text=title)
            self.server_stats_tree.column(col, width=width, anchor="w")
        self.server_stats_tree.grid(row=0, column=0, sticky="nsew")
        server_scroll = ttk.Scrollbar(table_frame, orient="vertical", command=self.server_stats_tree.yview)
        server_scroll.grid(row=0, column=1, sticky="ns")
        self.server_stats_tree.configure(yscrollcommand=server_scroll.set)
        self.server_stats_tree.bind("<Double-1>", self.open_selected_server_manifest)

        self.refresh_local_history()
        self.refresh_server_stats()

    def refresh_local_history(self):
        if self.history_tree is None:
            return
        for item_id in self.history_tree.get_children():
            self.history_tree.delete(item_id)
        try:
            history = load_upload_history(Path(self.output_var.get()))
        except Exception as exc:
            self.log(f"读取上传历史失败：{exc}")
            history = []
        for index, row in enumerate(reversed(history)):
            species = f"{row.get('zh') or row.get('en') or ''} · {row.get('sci') or ''}".strip(" ·")
            kind = "音频" if row.get("kind") == "audio" else "图片"
            self.history_tree.insert(
                "",
                "end",
                iid=str(index),
                values=(
                    row.get("uploaded_at", ""),
                    species,
                    kind,
                    row.get("method", ""),
                    Path(str(row.get("original", ""))).name,
                ),
            )

    def refresh_server_stats(self):
        def worker():
            try:
                payload = self.fetch_server_stats(self.server_stats_query_var.get())
                self.post_ui(self.render_server_stats, payload)
            except Exception as exc:
                self.log(f"服务器统计刷新失败：{exc}")
                self.show_error("服务器统计失败", str(exc))

        threading.Thread(target=worker, daemon=True).start()

    def fetch_server_stats(self, query: str) -> dict[str, Any]:
        base = self.server_var.get().rstrip("/")
        url = f"{base}/api/stats"
        if query.strip():
            url += "?" + urllib.parse.urlencode({"q": query.strip()})
        try:
            with urllib.request.urlopen(url, timeout=30) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code != 404:
                raise
        index_url = f"{base}/indexes/species_media_index.json"
        with urllib.request.urlopen(index_url, timeout=30) as response:
            rows = json.loads(response.read().decode("utf-8"))
        q = normalize_name(query)
        if q:
            rows = [
                row
                for row in rows
                if q in normalize_name(f"{row.get('sci', '')} {row.get('cn', '')} {row.get('en', '')}")
            ]
        return {
            "species_count": len(rows),
            "image_count": sum(int(row.get("image_count", 0)) for row in rows),
            "audio_count": sum(int(row.get("audio_count", 0)) for row in rows),
            "rows": rows,
        }

    def render_server_stats(self, payload: dict[str, Any]):
        if self.server_stats_tree is None:
            return
        for item_id in self.server_stats_tree.get_children():
            self.server_stats_tree.delete(item_id)
        rows = list(payload.get("rows") or [])
        self.server_stats_summary_var.set(
            f"服务器：{payload.get('species_count', len(rows))} 种｜图片 {payload.get('image_count', 0)}｜音频 {payload.get('audio_count', 0)}"
        )
        for index, row in enumerate(rows):
            species = f"{row.get('cn') or row.get('en') or ''} · {row.get('en') or ''} · {row.get('sci') or ''}".strip(" ·")
            self.server_stats_tree.insert(
                "",
                "end",
                iid=str(index),
                values=(
                    species,
                    row.get("image_count", 0),
                    row.get("audio_count", 0),
                    row.get("species_dir", ""),
                ),
            )
        self.server_stats_tree.server_rows = rows

    def open_selected_server_manifest(self, _event=None):
        if self.server_stats_tree is None:
            return
        selection = self.server_stats_tree.selection()
        rows = getattr(self.server_stats_tree, "server_rows", [])
        if not selection:
            return
        index = int(selection[0])
        if index >= len(rows):
            return
        url = rows[index].get("manifest_url")
        if url:
            subprocess.run(["open", str(url)])

    def open_output(self):
        path = Path(self.output_var.get())
        path.mkdir(parents=True, exist_ok=True)
        subprocess.run(["open", str(path)])

    def open_uploader(self):
        subprocess.run(["open", "http://124.223.101.188:8080/uploader"])


if __name__ == "__main__":
    App().mainloop()
