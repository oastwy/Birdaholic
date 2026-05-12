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
import os
import re
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading
import tkinter as tk
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from difflib import SequenceMatcher
from pathlib import Path
from tkinter import filedialog, messagebox, ttk
from typing import Any


IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".heic"}
AUDIO_EXTS = {".mp3", ".m4a", ".aac", ".wav", ".flac", ".ogg"}
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


def write_outputs(decisions: list[MediaDecision], output_dir: Path) -> None:
    csv_path = output_dir / "review_manifest.csv"
    with csv_path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["active", "original", "status", "sci", "zh", "en", "score", "method", "output"],
        )
        writer.writeheader()
        for item in decisions:
            writer.writerow(
                {
                    "active": "yes" if item.active else "no",
                    "original": str(item.src),
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
        css = "ok" if item.status == "recognized" else "bad"
        species = f"{item.zh or item.en} · {item.sci}" if item.sci else "未识别"
        html.append(
            f"<tr><td class='{css}'>{item.status}</td><td>{species}</td><td>{item.score:.2f}</td><td>{item.method}</td><td>{item.src.name}</td><td>{item.output}</td></tr>"
        )
    html.append("</table>")
    (output_dir / "review_manifest.html").write_text("\n".join(html), encoding="utf-8")


def upload_decisions(
    decisions: list[MediaDecision],
    token: str,
    server_url: str,
    log: callable,
) -> set[Path]:
    recognized = [
        item
        for item in decisions
        if item.active and item.status == "recognized" and item.output
    ]
    if not recognized:
        log("没有可上传的已识别文件。")
        return set()
    if not token.strip():
        raise RuntimeError("请先填写上传密钥。")

    total_saved = 0
    total_failed = 0
    uploaded_sources: set[Path] = set()
    grouped: dict[str, list[MediaDecision]] = {}
    for item in recognized:
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


def process_media(
    input_dir: Path,
    output_dir: Path,
    world_birds: Path,
    use_birdnet: bool,
    min_conf: float,
    threads: int,
    lat: str,
    lon: str,
    week: str,
    log: callable,
) -> list[MediaDecision]:
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    matcher = SpeciesMatcher(world_birds)
    media_files = [path for path in input_dir.rglob("*") if path.is_file() and media_kind(path)]
    audio_files = [path for path in media_files if media_kind(path) == "audio"]
    log(f"找到媒体文件 {len(media_files)} 个，其中音频 {len(audio_files)} 个")

    birdnet_predictions: dict[Path, tuple[str, float]] = {}
    if use_birdnet and audio_files:
        if not birdnet_available():
            log("没有检测到 birdnet_analyzer，跳过 BirdNET。")
        else:
            birdnet_predictions = run_birdnet(input_dir, output_dir, min_conf, threads, lat, lon, week, log)

    decisions: list[MediaDecision] = []
    for src in media_files:
        kind = media_kind(src) or ""
        item, score = matcher.match(src.name)
        method = "filename"

        candidate_status = "recognized"
        candidate_active = True
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
                    candidate_status = "candidate"
                    candidate_active = False

        if item is None:
            target_dir = output_dir / "_unrecognized" / kind
            target_dir.mkdir(parents=True, exist_ok=True)
            target = target_dir / src.name
            shutil.copy2(src, target)
            decisions.append(MediaDecision(src=src, kind=kind, status="unrecognized", score=score, method=method, output=str(target)))
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
            )
        )

    write_outputs(decisions, output_dir)
    recognized = sum(1 for item in decisions if item.status == "recognized")
    candidates = sum(1 for item in decisions if item.status == "candidate")
    log(f"完成：识别 {recognized}/{len(decisions)} 个文件，待审核候选 {candidates} 个")
    log(f"输出目录：{output_dir}")
    log(f"审核清单：{output_dir / 'review_manifest.html'}")
    return decisions


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Birdaholic 本地媒体助手")
        self.geometry("1180x820")

        self.input_var = tk.StringVar(value="/Users/wuyang/Archive/bird_uploads/file")
        self.output_var = tk.StringVar(value=str(Path.home() / "BirdaholicUploadBatch"))
        self.world_var = tk.StringVar(value=str(bundled_world_birds_path()))
        self.server_var = tk.StringVar(value="http://124.223.101.188:8080")
        self.token_var = tk.StringVar(value="")
        self.birdnet_var = tk.BooleanVar(value=True)
        self.auto_upload_var = tk.BooleanVar(value=False)
        self.move_uploaded_var = tk.BooleanVar(value=True)
        self.uploaded_dir_var = tk.StringVar(value="/Users/wuyang/Archive/bird_uploads/已上传")
        self.lat_var = tk.StringVar()
        self.lon_var = tk.StringVar()
        self.week_var = tk.StringVar()
        self.min_conf_var = tk.StringVar(value="0.30")
        self.threads_var = tk.StringVar(value="2")
        self.edit_species_var = tk.StringVar()
        self.decisions: list[MediaDecision] = []
        self.matcher: SpeciesMatcher | None = None
        self.map_server: socketserver.TCPServer | None = None

        self._build()

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

        actions = ttk.Frame(frm)
        actions.grid(row=5, column=0, columnspan=3, sticky="ew", **pad)
        ttk.Button(actions, text="开始识别并压缩", command=self.start).pack(side="left")
        ttk.Button(actions, text="上传全部保留记录", command=self.upload_all).pack(side="left", padx=8)
        ttk.Button(actions, text="上传选中记录", command=self.upload_selected).pack(side="left")
        ttk.Button(actions, text="打开输出目录", command=self.open_output).pack(side="left", padx=8)
        ttk.Button(actions, text="打开上传网页", command=self.open_uploader).pack(side="left")

        review = ttk.LabelFrame(frm, text="审核记录")
        review.grid(row=6, column=0, columnspan=3, sticky="nsew", **pad)
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
        review.rowconfigure(0, weight=1)

        edit = ttk.Frame(frm)
        edit.grid(row=7, column=0, columnspan=3, sticky="ew", **pad)
        ttk.Label(edit, text="改为物种").pack(side="left")
        ttk.Entry(edit, textvariable=self.edit_species_var, width=42).pack(side="left", padx=8)
        ttk.Button(edit, text="应用到选中", command=self.apply_species_to_selected).pack(side="left")
        ttk.Button(edit, text="删除选中", command=self.delete_selected).pack(side="left", padx=8)
        ttk.Button(edit, text="恢复选中", command=self.restore_selected).pack(side="left")
        ttk.Button(edit, text="打开原文件", command=self.open_selected_file).pack(side="left", padx=8)

        self.log_text = tk.Text(frm, height=8)
        self.log_text.grid(row=8, column=0, columnspan=3, sticky="nsew", **pad)
        frm.rowconfigure(6, weight=3)
        frm.rowconfigure(8, weight=1)
        frm.columnconfigure(1, weight=1)

        installed = "已安装（内置引擎）" if bundled_birdnet_engine_path() else "已安装" if birdnet_available() else "未安装"
        self.log(f"BirdNET 状态：{installed}")
        if not birdnet_available():
            self.log("安装命令：python3 -m pip install birdnet-analyzer")

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
        self.log_text.insert("end", message + "\n")
        self.log_text.see("end")
        self.update_idletasks()

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
                self.matcher = SpeciesMatcher(Path(self.world_var.get()))
                decisions = process_media(
                    input_dir=Path(self.input_var.get()),
                    output_dir=Path(self.output_var.get()),
                    world_birds=Path(self.world_var.get()),
                    use_birdnet=self.birdnet_var.get(),
                    min_conf=float(self.min_conf_var.get() or 0.30),
                    threads=int(self.threads_var.get() or 2),
                    lat=self.lat_var.get(),
                    lon=self.lon_var.get(),
                    week=self.week_var.get(),
                    log=self.log,
                )
                self.decisions = decisions
                self.after(0, self.refresh_table)
                if should_upload or self.auto_upload_var.get():
                    uploaded = upload_decisions(
                        decisions=decisions,
                        token=self.token_var.get(),
                        server_url=self.server_var.get(),
                        log=self.log,
                    )
                    self.after(0, lambda: self.after_upload_success(uploaded))
            except Exception as exc:
                self.log(f"失败：{exc}")
                messagebox.showerror("处理失败", str(exc))

        threading.Thread(target=worker, daemon=True).start()

    def refresh_table(self):
        for item_id in self.tree.get_children():
            self.tree.delete(item_id)
        for index, item in enumerate(self.decisions):
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
        decision.status = "recognized"
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
                self.decisions[index].status = "recognized"
        write_outputs(self.decisions, Path(self.output_var.get()))
        self.refresh_table()

    def open_selected_file(self):
        indices = self.selected_indices()
        if not indices:
            return
        subprocess.run(["open", str(self.decisions[indices[0]].src)])

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
                self.after(0, lambda: self.after_upload_success(uploaded))
            except Exception as exc:
                self.log(f"上传失败：{exc}")
                messagebox.showerror("上传失败", str(exc))

        threading.Thread(target=worker, daemon=True).start()

    def after_upload_success(self, uploaded_sources: set[Path]):
        if not uploaded_sources:
            return
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

    def open_output(self):
        path = Path(self.output_var.get())
        path.mkdir(parents=True, exist_ok=True)
        subprocess.run(["open", str(path)])

    def open_uploader(self):
        subprocess.run(["open", "http://124.223.101.188:8080/uploader"])


if __name__ == "__main__":
    App().mainloop()
