#!/usr/bin/env python3
"""Split a Birdaholic ZIP data pack into smaller valid ZIP packs."""

from __future__ import annotations

import argparse
import copy
import json
import math
import zipfile
from pathlib import Path
from typing import Any


def referenced_files(species: dict[str, Any]) -> list[str]:
    files: list[str] = []
    image = species.get("image")
    if isinstance(image, str) and image:
        files.append(image)
    for audio in species.get("audios", []) or []:
        if isinstance(audio, dict):
            file_name = audio.get("file")
            if isinstance(file_name, str) and file_name:
                files.append(file_name)
    return files


def build_member_lookup(pack: zipfile.ZipFile) -> dict[str, str]:
    lookup: dict[str, str] = {}
    for name in pack.namelist():
        path = Path(name)
        lookup[f"{path.parent.as_posix()}/{path.stem}".lstrip("./")] = name
    return lookup


def resolve_member(pack: zipfile.ZipFile, lookup: dict[str, str], file_name: str) -> str | None:
    try:
        pack.getinfo(file_name)
        return file_name
    except KeyError:
        pass
    path = Path(file_name)
    key = f"{path.parent.as_posix()}/{path.stem}".lstrip("./")
    return lookup.get(key)


def normalize_species_files(
    pack: zipfile.ZipFile,
    lookup: dict[str, str],
    species: dict[str, Any],
) -> dict[str, Any]:
    row = copy.deepcopy(species)
    image = row.get("image")
    if isinstance(image, str) and image:
        resolved = resolve_member(pack, lookup, image)
        if resolved:
            row["image"] = resolved
    for audio in row.get("audios", []) or []:
        if not isinstance(audio, dict):
            continue
        file_name = audio.get("file")
        if isinstance(file_name, str) and file_name:
            resolved = resolve_member(pack, lookup, file_name)
            if resolved:
                audio["file"] = resolved
    return row


def species_size(pack: zipfile.ZipFile, species: dict[str, Any]) -> int:
    total = len(json.dumps(species, ensure_ascii=False).encode("utf-8"))
    for file_name in referenced_files(species):
        try:
            total += pack.getinfo(file_name).compress_size
        except KeyError:
            continue
    return total


def write_part(
    source: zipfile.ZipFile,
    output_path: Path,
    base_manifest: dict[str, Any],
    species_rows: list[dict[str, Any]],
    part_index: int,
    part_count: int,
) -> None:
    manifest = dict(base_manifest)
    manifest["name"] = f"{base_manifest.get('name', 'Birdaholic Pack')} Part {part_index:02d}"
    manifest["part"] = part_index
    manifest["part_count"] = part_count
    manifest["species_count"] = len(species_rows)
    manifest["audio_count"] = sum(len(row.get("audios", []) or []) for row in species_rows)
    manifest["image_count"] = sum(1 for row in species_rows if row.get("image"))
    manifest["split_from"] = output_path.name.rsplit("_part", 1)[0] + ".zip"

    written: set[str] = set()
    with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as out:
        out.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
        out.writestr("species.json", json.dumps(species_rows, ensure_ascii=False, indent=2) + "\n")
        for row in species_rows:
            for file_name in referenced_files(row):
                if file_name in written:
                    continue
                try:
                    data = source.read(file_name)
                except KeyError:
                    continue
                out.writestr(file_name, data)
                written.add(file_name)


def split_pack(input_zip: Path, output_dir: Path, max_mb: int) -> list[Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    max_bytes = max_mb * 1024 * 1024
    soft_limit = int(max_bytes * 0.95)
    stem = input_zip.stem

    with zipfile.ZipFile(input_zip) as pack:
        manifest = json.loads(pack.read("manifest.json").decode("utf-8"))
        raw_species_rows: list[dict[str, Any]] = json.loads(pack.read("species.json").decode("utf-8"))
        lookup = build_member_lookup(pack)
        species_rows = [
            normalize_species_files(pack, lookup, row)
            for row in raw_species_rows
        ]

        parts: list[list[dict[str, Any]]] = []
        current: list[dict[str, Any]] = []
        current_size = 0
        for row in species_rows:
            row_size = species_size(pack, row)
            if current and current_size + row_size > soft_limit:
                parts.append(current)
                current = []
                current_size = 0
            current.append(row)
            current_size += row_size
        if current:
            parts.append(current)

        digits = max(2, int(math.log10(len(parts))) + 1 if parts else 2)
        outputs: list[Path] = []
        for index, rows in enumerate(parts, start=1):
            output_path = output_dir / f"{stem}_part{index:0{digits}d}.zip"
            write_part(pack, output_path, manifest, rows, index, len(parts))
            outputs.append(output_path)

    index_rows = [
        {
            "file": path.name,
            "bytes": path.stat().st_size,
            "mb": round(path.stat().st_size / 1024 / 1024, 1),
        }
        for path in outputs
    ]
    (output_dir / f"{stem}_parts.json").write_text(
        json.dumps(
            {
                "source": input_zip.name,
                "max_mb": max_mb,
                "part_count": len(outputs),
                "parts": index_rows,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    return outputs


def main() -> None:
    parser = argparse.ArgumentParser(description="Split Birdaholic data pack ZIP into smaller ZIP packs.")
    parser.add_argument("input_zip", type=Path)
    parser.add_argument("--output-dir", type=Path, default=Path("data_packs/split_100mb"))
    parser.add_argument("--max-mb", type=int, default=100)
    args = parser.parse_args()

    outputs = split_pack(args.input_zip, args.output_dir, args.max_mb)
    for path in outputs:
        print(f"{path}\t{path.stat().st_size / 1024 / 1024:.1f} MB")
    print(f"Created {len(outputs)} parts in {args.output_dir}")


if __name__ == "__main__":
    main()
