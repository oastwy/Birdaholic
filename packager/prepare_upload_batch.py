#!/usr/bin/env python3
"""Prepare a local media folder before uploading to Birdaholic server.

This script runs on the Mac. It:
  - scans image/audio files recursively
  - recognizes species from filenames using world_birds.json
  - optimizes images with sips and audio with ffmpeg when available
  - writes a review CSV
  - places files under upload_batch/{species}/images or audio
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import shutil
import subprocess
import tempfile
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any


IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".heic"}
AUDIO_EXTS = {".mp3", ".m4a", ".aac", ".wav", ".flac", ".ogg"}
ALIASES = {
    "common chaffinch": "eurasian chaffinch",
}


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


def match_species(filename: str, species: list[dict[str, Any]]) -> tuple[dict[str, Any] | None, float]:
    normalized = normalize_name(filename)
    if not normalized:
        return None, 0

    for item in species:
        sci = item.get("sci", "")
        if normalized == normalize_name(sci) or normalized == species_key(sci).lower():
            return item, 1
        for name in candidate_names(item):
            if normalized == normalize_name(name):
                return item, 1

    best: tuple[float, dict[str, Any] | None] = (0, None)
    for item in species:
        for name in candidate_names(item):
            score = SequenceMatcher(None, normalized, normalize_name(name)).ratio()
            if score > best[0]:
                best = (score, item)
    return (best[1], best[0]) if best[0] >= 0.88 else (None, best[0])


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
    shutil.copy2(src, dst.with_suffix(src.suffix.lower()))
    return dst.with_suffix(src.suffix.lower())


def media_kind(path: Path) -> str | None:
    suffix = path.suffix.lower()
    if suffix in IMAGE_EXTS:
        return "images"
    if suffix in AUDIO_EXTS:
        return "audio"
    return None


def safe_name(src: Path, sci: str, kind: str) -> str:
    stem = species_key(sci)
    audio_type = ""
    lowered = src.stem.lower()
    if kind == "audio":
        audio_type = "_song" if "song" in lowered else "_call" if "call" in lowered else "_audio"
    return f"{stem}{audio_type}_{abs(hash(src.name)) % 100000}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prepare media for batch upload.")
    parser.add_argument("input", help="Folder containing images/audio")
    parser.add_argument("--output", default="upload_batch", help="Output folder")
    parser.add_argument("--world-birds", default="assets/data/world_birds.json")
    parser.add_argument("--max-image", type=int, default=1600)
    parser.add_argument("--jpeg-quality", type=int, default=70)
    parser.add_argument("--audio-bitrate", default="64k")
    parser.add_argument("--clean", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    input_dir = Path(args.input)
    output_dir = Path(args.output)
    if args.clean and output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    species = json.loads(Path(args.world_birds).read_text(encoding="utf-8"))
    rows: list[dict[str, str]] = []

    files = [path for path in input_dir.rglob("*") if path.is_file()]
    for src in files:
        kind = media_kind(src)
        if kind is None:
            continue
        item, score = match_species(src.name, species)
        if item is None:
            target_dir = output_dir / "_unrecognized" / kind
            target_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, target_dir / src.name)
            rows.append(
                {
                    "original": str(src),
                    "status": "unrecognized",
                    "sci": "",
                    "zh": "",
                    "en": "",
                    "score": f"{score:.2f}",
                    "output": str(target_dir / src.name),
                }
            )
            continue

        sci = item["sci"]
        base = safe_name(src, sci, kind)
        dst = output_dir / species_key(sci) / kind / base
        if kind == "images":
            output = optimize_image(src, dst, args.max_image, args.jpeg_quality)
        else:
            output = optimize_audio(src, dst, args.audio_bitrate)
        rows.append(
            {
                "original": str(src),
                "status": "recognized",
                "sci": sci,
                "zh": item.get("zh", ""),
                "en": item.get("en", ""),
                "score": f"{score:.2f}",
                "output": str(output),
            }
        )

    csv_path = output_dir / "review_manifest.csv"
    with csv_path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["original", "status", "sci", "zh", "en", "score", "output"],
        )
        writer.writeheader()
        writer.writerows(rows)

    recognized = sum(1 for row in rows if row["status"] == "recognized")
    print(f"Done. Recognized {recognized}/{len(rows)} media files.")
    print(f"Review CSV: {csv_path}")
    print(f"Upload folder: {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
