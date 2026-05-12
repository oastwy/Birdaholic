#!/usr/bin/env python3
"""
Small BirdNET sidecar for BirdaholicMediaAssistant.

The GUI calls this executable first when it is bundled into the app. Keeping
BirdNET in a separate process makes it easier to package and easier to replace
when a local Python environment is broken.
"""

from __future__ import annotations

import argparse
import csv
import contextlib
import importlib.util
import io
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


AUDIO_EXTS = {".mp3", ".m4a", ".aac", ".wav", ".flac", ".ogg"}


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


def parse_float(value: str | None) -> float:
    try:
        return float(value or "0")
    except ValueError:
        return 0.0


def parse_results(results_dir: Path, input_dir: Path) -> list[dict[str, object]]:
    predictions: dict[str, dict[str, object]] = {}
    for csv_path in results_dir.rglob("*.csv"):
        with csv_path.open(newline="", encoding="utf-8-sig") as handle:
            reader = csv.DictReader(handle)
            fieldnames = reader.fieldnames or []
            if not fieldnames:
                continue
            file_col = pick_column(fieldnames, ["file", "filename", "source", "input"])
            sci_col = pick_column(fieldnames, ["scientific name", "sci_name", "scientific"])
            common_col = pick_column(fieldnames, ["common name", "common", "label", "species"])
            conf_col = pick_column(fieldnames, ["confidence", "score", "conf"])
            for row in reader:
                label = ""
                if sci_col and row.get(sci_col):
                    label = row[sci_col].strip()
                elif common_col and row.get(common_col):
                    label = row[common_col].strip()
                if not label:
                    continue

                confidence = parse_float(row.get(conf_col) if conf_col else None)
                if file_col and row.get(file_col):
                    src = Path(row[file_col])
                    if not src.is_absolute():
                        src = input_dir / src
                else:
                    src = input_dir / csv_path.with_suffix("").name

                key = str(src.resolve())
                old = predictions.get(key)
                if old is None or confidence > float(old.get("confidence", 0)):
                    predictions[key] = {
                        "file": key,
                        "label": label,
                        "confidence": confidence,
                    }
    return list(predictions.values())


def convert_to_wav(src: Path, dst: Path) -> bool:
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg:
        command = [
            ffmpeg,
            "-y",
            "-i",
            str(src),
            "-vn",
            "-ac",
            "1",
            "-ar",
            "48000",
            "-sample_fmt",
            "s16",
            str(dst),
        ]
        try:
            subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return dst.exists() and dst.stat().st_size > 0
        except (OSError, subprocess.CalledProcessError):
            pass

    afconvert = shutil.which("afconvert")
    if afconvert:
        command = [
            afconvert,
            str(src),
            str(dst),
            "-f",
            "WAVE",
            "-d",
            "LEI16@48000",
            "-c",
            "1",
        ]
        try:
            subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return dst.exists() and dst.stat().st_size > 0
        except (OSError, subprocess.CalledProcessError):
            pass
    return False


def prepare_audio_input(input_dir: Path) -> tuple[tempfile.TemporaryDirectory[str], Path, dict[str, str]]:
    temp = tempfile.TemporaryDirectory(prefix="birdaholic_birdnet_")
    prepared_dir = Path(temp.name)
    source_map: dict[str, str] = {}
    counter = 0
    for src in input_dir.rglob("*"):
        if not src.is_file() or src.suffix.lower() not in AUDIO_EXTS:
            continue
        counter += 1
        safe_stem = f"audio_{counter:05d}"
        dst = prepared_dir / f"{safe_stem}.wav"
        if src.suffix.lower() == ".wav":
            shutil.copy2(src, dst)
        elif not convert_to_wav(src, dst):
            dst = prepared_dir / f"{safe_stem}{src.suffix.lower()}"
            shutil.copy2(src, dst)
        source_map[str(dst.resolve())] = str(src.resolve())
    return temp, prepared_dir, source_map


def main() -> int:
    parser = argparse.ArgumentParser(description="Run BirdNET and print JSON predictions.")
    parser.add_argument("input_dir")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--min-conf", default="0.45")
    parser.add_argument("--threads", default="1")
    parser.add_argument("--lat", default="")
    parser.add_argument("--lon", default="")
    parser.add_argument("--week", default="")
    args = parser.parse_args()

    if importlib.util.find_spec("birdnet_analyzer") is None:
        print(json.dumps({"ok": False, "error": "birdnet_analyzer is not installed"}, ensure_ascii=False))
        return 2

    input_dir = Path(args.input_dir).expanduser().resolve()
    results_dir = Path(args.output_dir).expanduser().resolve()
    results_dir.mkdir(parents=True, exist_ok=True)
    temp_input, prepared_input_dir, source_map = prepare_audio_input(input_dir)

    birdnet_args = [
        str(prepared_input_dir),
        "-o",
        str(results_dir),
        "--rtype",
        "csv",
        "--top_n",
        "5",
        "--min_conf",
        str(args.min_conf),
        "--threads",
        str(max(1, int(args.threads or "1"))),
    ]
    if args.lat.strip() and args.lon.strip():
        birdnet_args.extend(["--lat", args.lat.strip(), "--lon", args.lon.strip()])
    if args.week.strip():
        birdnet_args.extend(["--week", args.week.strip()])

    log_buffer = io.StringIO()
    old_argv = sys.argv[:]
    try:
        from birdnet_analyzer.analyze.cli import main as birdnet_main

        sys.argv = ["birdnet_analyzer.analyze", *birdnet_args]
        with contextlib.redirect_stdout(log_buffer), contextlib.redirect_stderr(log_buffer):
            birdnet_main()
    except SystemExit as exc:
        code = int(exc.code or 0) if isinstance(exc.code, int) else 1
        if code != 0:
            print(
                json.dumps(
                    {
                        "ok": False,
                        "error": "BirdNET analyze failed",
                        "returncode": code,
                        "log": log_buffer.getvalue()[-4000:],
                    },
                    ensure_ascii=False,
                )
            )
            return code
    except Exception as exc:
        print(
            json.dumps(
                {
                    "ok": False,
                    "error": "BirdNET analyze failed",
                    "returncode": 1,
                    "log": f"{log_buffer.getvalue()[-3500:]}\n{type(exc).__name__}: {exc}",
                },
                ensure_ascii=False,
            )
        )
        return 1
    finally:
        sys.argv = old_argv

    print(
        json.dumps(
            {
                "ok": True,
                "predictions": [
                    {**item, "file": source_map.get(str(item["file"]), str(item["file"]))}
                    for item in parse_results(results_dir, prepared_input_dir)
                ],
                "log": log_buffer.getvalue()[-4000:],
            },
            ensure_ascii=False,
        )
    )
    temp_input.cleanup()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
