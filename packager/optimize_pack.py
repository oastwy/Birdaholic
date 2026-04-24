#!/usr/bin/env python3
"""
压缩并重打鸟类数据包 ZIP，适合移动端内置或分发。

功能：
1. 解压原始 ZIP
2. 批量压缩图片
3. 批量转码 MP3 -> M4A（失败则保留原文件）
4. 自动重写 species.json 中的音频后缀
5. 重新打包为优化版 ZIP

依赖：
- macOS 自带 `sips`
- `/usr/bin/swift`
- 同目录下 `transcode_audio.swift`
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent
TRANSCODER = ROOT / "transcode_audio.swift"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="优化鸟类数据包 ZIP")
    parser.add_argument("--input", required=True, help="输入 ZIP 路径")
    parser.add_argument("--output", required=True, help="输出 ZIP 路径")
    parser.add_argument("--max-image", type=int, default=1600, help="图片最长边")
    parser.add_argument("--jpeg-quality", type=int, default=70, help="JPEG 质量 0-100")
    parser.add_argument(
        "--keep-mp3-on-failure",
        action="store_true",
        help="音频转码失败时保留原始 mp3（默认开启）",
    )
    return parser.parse_args()


def run(cmd: list[str], *, quiet: bool = False) -> None:
    kwargs = {}
    if quiet:
        kwargs["stdout"] = subprocess.DEVNULL
        kwargs["stderr"] = subprocess.DEVNULL
    subprocess.run(cmd, check=True, **kwargs)


def optimize_images(images_dir: Path, *, max_image: int, jpeg_quality: int) -> tuple[int, int]:
    before = 0
    after = 0
    for path in sorted(images_dir.iterdir()):
        if not path.is_file():
            continue
        if path.suffix.lower() not in {".jpg", ".jpeg", ".png"}:
            continue

        before += path.stat().st_size
        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
            tmp_path = Path(tmp.name)

        try:
            run(
                [
                    "sips",
                    "-Z",
                    str(max_image),
                    "--setProperty",
                    "formatOptions",
                    str(jpeg_quality),
                    str(path),
                    "--out",
                    str(tmp_path),
                ],
                quiet=True,
            )
            shutil.copyfile(tmp_path, path)
        finally:
            tmp_path.unlink(missing_ok=True)

        after += path.stat().st_size
    return before, after


def optimize_audio(sounds_dir: Path, species_json: Path) -> tuple[int, int, int]:
    with species_json.open("r", encoding="utf-8") as f:
        species = json.load(f)

    before = 0
    after = 0
    converted = 0
    renamed: dict[str, str] = {}

    for path in sorted(sounds_dir.iterdir()):
        if not path.is_file() or path.suffix.lower() != ".mp3":
            continue

        before += path.stat().st_size
        target = path.with_suffix(".m4a")

        try:
          run(["/usr/bin/swift", str(TRANSCODER), str(path), str(target)], quiet=True)
          path.unlink(missing_ok=True)
          renamed[path.name] = target.name
          converted += 1
          after += target.stat().st_size
        except subprocess.CalledProcessError:
          # 某些损坏或特殊编码文件可能转码失败，保留原文件
          after += path.stat().st_size

    if renamed:
        for item in species:
            for audio in item.get("audios", []):
                file_path = audio.get("file", "")
                if not file_path:
                    continue
                filename = os.path.basename(file_path)
                if filename in renamed:
                    audio["file"] = f"sounds/{renamed[filename]}"
        with species_json.open("w", encoding="utf-8") as f:
            json.dump(species, f, ensure_ascii=False, indent=2)

    return before, after, converted


def repack(source_dir: Path, output_zip: Path) -> None:
    output_zip.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for root, _, files in os.walk(source_dir):
            for name in files:
                full = Path(root) / name
                rel = full.relative_to(source_dir)
                zf.write(full, rel.as_posix())


def main() -> int:
    args = parse_args()
    input_zip = Path(args.input).expanduser().resolve()
    output_zip = Path(args.output).expanduser().resolve()

    if not input_zip.exists():
        print(f"❌ 输入文件不存在: {input_zip}", file=sys.stderr)
        return 1

    if not TRANSCODER.exists():
        print(f"❌ 找不到音频转码脚本: {TRANSCODER}", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix="bird_pack_opt_") as tmp:
        extracted = Path(tmp) / "extracted"
        extracted.mkdir(parents=True, exist_ok=True)

        with zipfile.ZipFile(input_zip) as zf:
            zf.extractall(extracted)

        images_dir = extracted / "images"
        sounds_dir = extracted / "sounds"
        species_json = extracted / "species.json"

        img_before, img_after = optimize_images(
            images_dir,
            max_image=args.max_image,
            jpeg_quality=args.jpeg_quality,
        )
        audio_before, audio_after, converted = optimize_audio(sounds_dir, species_json)

        repack(extracted, output_zip)

    original_mb = input_zip.stat().st_size / 1024 / 1024
    output_mb = output_zip.stat().st_size / 1024 / 1024
    print(f"✅ 优化完成")
    print(f"   输入包: {input_zip}")
    print(f"   输出包: {output_zip}")
    print(f"   原始 ZIP: {original_mb:.1f} MB")
    print(f"   优化 ZIP: {output_mb:.1f} MB")
    print(f"   图片: {img_before / 1024 / 1024:.1f} -> {img_after / 1024 / 1024:.1f} MB")
    print(f"   音频: {audio_before / 1024 / 1024:.1f} -> {audio_after / 1024 / 1024:.1f} MB")
    print(f"   成功转码音频: {converted} 个")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
