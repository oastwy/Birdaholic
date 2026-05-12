#!/usr/bin/env python3
"""Export ZIP data packs into a per-species server media library.

Input packs are Birdaholic ZIP files containing:
  manifest.json
  species.json
  images/...
  sounds/...

Output layout:
  server_media_library/
    species/{Scientific_name_with_underscores}/
      manifest.json
      images/...
      audio/...
    indexes/
      species_media_index.json
      pack_index.json
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import zipfile
from collections import OrderedDict
from pathlib import Path
from typing import Any


def species_key(scientific_name: str) -> str:
    return "_".join(scientific_name.strip().split())


def read_json_from_zip(pack: zipfile.ZipFile, name: str) -> Any:
    with pack.open(name) as handle:
        return json.load(handle)


def resolve_zip_member(pack: zipfile.ZipFile, member_name: str) -> str | None:
    if not member_name:
        return None

    normalized = member_name.replace("\\", "/").lstrip("/")
    try:
        pack.getinfo(normalized)
        return normalized
    except KeyError:
        pass

    path = Path(normalized)
    parent = path.parent.as_posix()
    stem = path.stem
    for candidate in pack.namelist():
        candidate_path = Path(candidate)
        if candidate_path.parent.as_posix() == parent and candidate_path.stem == stem:
            return candidate
    return None


def run_quiet(command: list[str]) -> bool:
    try:
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


def optimize_image(path: Path, max_image: int, jpeg_quality: int) -> None:
    if shutil.which("sips") is None:
        return
    if path.suffix.lower() not in {".jpg", ".jpeg", ".png", ".heic", ".webp"}:
        return

    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = Path(tmp_dir) / f"{path.stem}.jpg"
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
                str(path),
                "--out",
                str(tmp_path),
            ]
        )
        if ok and tmp_path.exists() and tmp_path.stat().st_size < path.stat().st_size:
            path.unlink()
            shutil.move(str(tmp_path), path.with_suffix(".jpg"))


def optimize_audio(path: Path, bitrate: str) -> Path:
    if shutil.which("ffmpeg") is None:
        return path
    if path.suffix.lower() not in {".mp3", ".m4a", ".aac", ".wav", ".flac"}:
        return path

    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = Path(tmp_dir) / f"{path.stem}.m4a"
        ok = run_quiet(
            [
                "ffmpeg",
                "-y",
                "-i",
                str(path),
                "-vn",
                "-ac",
                "1",
                "-b:a",
                bitrate,
                str(tmp_path),
            ]
        )
        if ok and tmp_path.exists() and tmp_path.stat().st_size < path.stat().st_size:
            output_path = path.with_suffix(".m4a")
            path.unlink()
            shutil.move(str(tmp_path), output_path)
            return output_path
    return path


def copy_zip_member(pack: zipfile.ZipFile, member_name: str, destination_dir: Path) -> Path | None:
    resolved = resolve_zip_member(pack, member_name)
    if resolved is None:
        return None

    filename = Path(resolved).name
    destination = destination_dir / filename
    try:
        info = pack.getinfo(resolved)
    except KeyError:
        return None

    destination.parent.mkdir(parents=True, exist_ok=True)
    with pack.open(info) as src, destination.open("wb") as dst:
        shutil.copyfileobj(src, dst)
    return destination


def media_url(base_url: str, species_dir: str, kind: str, filename: str) -> str:
    base = base_url.rstrip("/")
    path = f"/species/{species_dir}/{kind}/{filename}"
    return f"{base}{path}" if base else path


def export_pack(
    zip_path: Path,
    output_dir: Path,
    base_url: str,
    optimize_media: bool,
    max_image: int,
    jpeg_quality: int,
    audio_bitrate: str,
) -> dict[str, Any]:
    with zipfile.ZipFile(zip_path) as pack:
        pack_manifest = read_json_from_zip(pack, "manifest.json")
        species_list = read_json_from_zip(pack, "species.json")

        species_count = 0
        image_count = 0
        audio_count = 0

        for source_species in species_list:
            sci = source_species.get("sci", "").strip()
            if not sci:
                continue

            species_count += 1
            key = species_key(sci)
            species_dir = output_dir / "species" / key
            images_dir = species_dir / "images"
            audio_dir = species_dir / "audio"

            image_entries: list[dict[str, Any]] = []
            image_file = source_species.get("image")
            if image_file:
                copied_image = copy_zip_member(pack, image_file, images_dir)
                if copied_image:
                    if optimize_media:
                        optimize_image(copied_image, max_image, jpeg_quality)
                        copied_image = copied_image.with_suffix(".jpg")
                    filename = copied_image.name
                    image_count += 1
                    image_entries.append(
                        {
                            "file": f"images/{filename}",
                            "url": media_url(base_url, key, "images", filename),
                            "contributor": source_species.get("image_contributor", ""),
                            "contributor_url": source_species.get("image_contributor_url", ""),
                            "license": source_species.get("image_license", ""),
                            "source": source_species.get("image_source", ""),
                        }
                    )

            audio_entries: list[dict[str, Any]] = []
            for audio in source_species.get("audios", []) or []:
                audio_file = audio.get("file", "")
                copied_audio = copy_zip_member(pack, audio_file, audio_dir)
                if copied_audio:
                    if optimize_media:
                        copied_audio = optimize_audio(copied_audio, audio_bitrate)
                    filename = copied_audio.name
                    audio_count += 1
                    audio_entries.append(
                        {
                            "file": f"audio/{filename}",
                            "url": media_url(base_url, key, "audio", filename),
                            "type": audio.get("type", ""),
                            "contributor": audio.get("contributor", ""),
                            "contributor_url": audio.get("contributor_url", ""),
                            "license": audio.get("license", ""),
                            "date": audio.get("date", ""),
                            "location": audio.get("location", ""),
                            "source": "xeno-canto" if "xeno-canto" in audio.get("contributor_url", "") else "",
                        }
                    )

            manifest = OrderedDict(
                [
                    ("sci", sci),
                    ("cn", source_species.get("cn", "")),
                    ("en", source_species.get("en", "")),
                    ("order", source_species.get("order", "")),
                    ("family", source_species.get("family", "")),
                    ("cons", source_species.get("cons", "")),
                    ("habitat", source_species.get("habitat", "")),
                    ("images", image_entries),
                    ("audio", audio_entries),
                    ("source_packs", [zip_path.name]),
                ]
            )

            species_dir.mkdir(parents=True, exist_ok=True)
            manifest_path = species_dir / "manifest.json"
            if manifest_path.exists():
                existing = json.loads(manifest_path.read_text(encoding="utf-8"))
                existing_packs = set(existing.get("source_packs", []))
                existing_packs.add(zip_path.name)
                existing["source_packs"] = sorted(existing_packs)
                if not existing.get("images"):
                    existing["images"] = image_entries
                if not existing.get("audio"):
                    existing["audio"] = audio_entries
                manifest_path.write_text(
                    json.dumps(existing, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8",
                )
            else:
                manifest_path.write_text(
                    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8",
                )

        return {
            "file": zip_path.name,
            "name": pack_manifest.get("name", ""),
            "region": pack_manifest.get("region", ""),
            "version": pack_manifest.get("version", ""),
            "species_count": species_count,
            "image_count": image_count,
            "audio_count": audio_count,
        }


def build_indexes(output_dir: Path, base_url: str, pack_summaries: list[dict[str, Any]]) -> None:
    index_dir = output_dir / "indexes"
    index_dir.mkdir(parents=True, exist_ok=True)

    species_index: list[dict[str, Any]] = []
    for manifest_path in sorted((output_dir / "species").glob("*/manifest.json")):
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        key = manifest_path.parent.name
        species_index.append(
            {
                "sci": manifest.get("sci", ""),
                "cn": manifest.get("cn", ""),
                "en": manifest.get("en", ""),
                "order": manifest.get("order", ""),
                "family": manifest.get("family", ""),
                "species_dir": key,
                "manifest_url": media_url(base_url, key, "", "manifest.json").replace("//manifest.json", "/manifest.json"),
                "image_count": len(manifest.get("images", [])),
                "audio_count": len(manifest.get("audio", [])),
                "source_packs": manifest.get("source_packs", []),
            }
        )

    (index_dir / "species_media_index.json").write_text(
        json.dumps(species_index, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (index_dir / "pack_index.json").write_text(
        json.dumps(pack_summaries, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export Birdaholic ZIP packs into per-species folders."
    )
    parser.add_argument("packs", nargs="+", help="ZIP data packs to export")
    parser.add_argument(
        "--output",
        default="server_media_library",
        help="Output directory, default: server_media_library",
    )
    parser.add_argument(
        "--base-url",
        default="",
        help="Optional public server base URL, for example http://124.223.101.188:8080",
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="Delete the output directory before generating it again",
    )
    parser.add_argument(
        "--no-optimize-media",
        action="store_true",
        help="Copy media as-is instead of optimizing images and audio for server upload",
    )
    parser.add_argument(
        "--max-image",
        type=int,
        default=1600,
        help="Maximum image width/height when optimizing, default: 1600",
    )
    parser.add_argument(
        "--jpeg-quality",
        type=int,
        default=70,
        help="JPEG quality used by sips when optimizing images, default: 70",
    )
    parser.add_argument(
        "--audio-bitrate",
        default="64k",
        help="AAC audio bitrate used by ffmpeg when optimizing, default: 64k",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output_dir = Path(args.output)

    if args.clean and output_dir.exists():
        shutil.rmtree(output_dir)

    output_dir.mkdir(parents=True, exist_ok=True)

    pack_summaries: list[dict[str, Any]] = []
    for pack_arg in args.packs:
        zip_path = Path(pack_arg)
        if not zip_path.exists():
            print(f"Missing pack: {zip_path}", file=sys.stderr)
            return 1
        print(f"Exporting {zip_path} ...")
        pack_summaries.append(
            export_pack(
                zip_path,
                output_dir,
                args.base_url,
                not args.no_optimize_media,
                args.max_image,
                args.jpeg_quality,
                args.audio_bitrate,
            )
        )

    build_indexes(output_dir, args.base_url, pack_summaries)
    species_count = len(list((output_dir / "species").glob("*")))
    print(f"Done. Exported {species_count} species folders to {output_dir}")
    print(f"Index: {output_dir / 'indexes' / 'species_media_index.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
