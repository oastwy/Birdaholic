#!/usr/bin/env python3
"""Build resumable world bird media packs in batches.

This is the global version of generate_china_pack.py. It reads
assets/data/world_birds.json and can download:
  - audio from Xeno-Canto
  - photos from iNaturalist

Run in small batches, then export each batch as a Birdaholic ZIP.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.parse
import urllib.request
import zipfile
from datetime import datetime
from pathlib import Path
from typing import Any


SUPPORTED_IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
DEFAULT_HEADERS = {
    "User-Agent": "BirdaholicWorldPackBuilder/1.0 (https://birding.today)",
    "Accept": "*/*",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate world birds pack workspace")
    parser.add_argument(
        "--world-birds-json",
        default=str(Path(__file__).resolve().parent.parent / "assets" / "data" / "world_birds.json"),
        help="Input world_birds.json path",
    )
    parser.add_argument("--workspace", required=True, help="Output workspace directory")
    parser.add_argument("--pack-name", default="World Birds")
    parser.add_argument("--region", default="World")
    parser.add_argument("--version", default="1.0")
    parser.add_argument("--start", type=int, default=0, help="Start offset in world list, default: 0")
    parser.add_argument("--limit", type=int, default=0, help="Species count for this batch, default: all")
    parser.add_argument("--with-media", action="store_true", help="Download audio/photos")
    parser.add_argument("--xeno-key", default="", help="Xeno-Canto API key for audio")
    parser.add_argument("--request-delay", type=float, default=0.8, help="Delay between species")
    parser.add_argument("--max-downloads", type=int, default=0, help="Cap species attempts in this run")
    parser.add_argument("--zip-output", default="", help="Optional ZIP output path")
    return parser.parse_args()


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def dump_json(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def http_json(url: str) -> dict | list:
    request = urllib.request.Request(url, headers=DEFAULT_HEADERS)
    with urllib.request.urlopen(request, timeout=40) as response:
        return json.loads(response.read().decode("utf-8"))


def http_bytes(url: str) -> bytes:
    request = urllib.request.Request(url, headers=DEFAULT_HEADERS)
    with urllib.request.urlopen(request, timeout=90) as response:
        return response.read()


def create_species_entry(item: dict[str, Any]) -> dict[str, object]:
    return {
        "cn": (item.get("zh") or "").strip() or (item.get("en") or "").strip() or item["sci"],
        "en": (item.get("en") or "").strip() or item["sci"],
        "sci": item["sci"].strip(),
        "order": item.get("order", ""),
        "family": item.get("family", ""),
        "audios": [],
    }


def load_or_init_workspace(args: argparse.Namespace) -> tuple[dict[str, dict[str, object]], dict[str, object]]:
    workspace = Path(args.workspace).expanduser().resolve()
    workspace.mkdir(parents=True, exist_ok=True)
    (workspace / "sounds").mkdir(exist_ok=True)
    (workspace / "images").mkdir(exist_ok=True)

    species_path = workspace / "species.json"
    state_path = workspace / ".download_state.json"

    if species_path.exists():
        species_list = load_json(species_path)
        species_map = {item["sci"]: item for item in species_list}
    else:
        raw_species = [item for item in load_json(Path(args.world_birds_json).expanduser()) if (item.get("sci") or "").strip()]
        end = None if args.limit <= 0 else args.start + args.limit
        raw_species = raw_species[args.start:end]
        species_map = {item["sci"].strip(): create_species_entry(item) for item in raw_species}
        dump_json(species_path, list(species_map.values()))

    if state_path.exists():
        state = load_json(state_path)
    else:
        state = {
            "pack_name": args.pack_name,
            "region": args.region,
            "version": args.version,
            "created": datetime.now().strftime("%Y-%m-%d"),
            "updated": "",
            "start": args.start,
            "limit": args.limit,
            "species_total": len(species_map),
            "success_audio_species": 0,
            "success_image_species": 0,
            "processed_species": 0,
            "errors": {},
            "media_mode": args.with_media,
        }
        dump_json(state_path, state)
    return species_map, state


def write_workspace(workspace: Path, species_map: dict[str, dict[str, object]], state: dict[str, object]) -> None:
    species_list = sorted(species_map.values(), key=lambda item: str(item["sci"]))
    serializable_species = [
        {key: value for key, value in item.items() if not key.startswith("_")}
        for item in species_list
    ]
    dump_json(workspace / "species.json", serializable_species)

    audio_count = sum(len(item.get("audios", [])) for item in serializable_species)
    image_count = sum(1 for item in serializable_species if item.get("image"))
    dump_json(
        workspace / "manifest.json",
        {
            "name": state["pack_name"],
            "region": state["region"],
            "version": state["version"],
            "created": state["created"],
            "species_count": len(serializable_species),
            "audio_count": audio_count,
            "image_count": image_count,
            "source": "world_birds.json + Xeno-Canto + iNaturalist",
        },
    )
    state["updated"] = datetime.now().isoformat(timespec="seconds")
    state["success_audio_species"] = sum(1 for item in species_list if item.get("audios"))
    state["success_image_species"] = sum(1 for item in species_list if item.get("image"))
    state["processed_species"] = sum(1 for item in species_list if item.get("audios") or item.get("image") or item.get("_attempted"))
    dump_json(workspace / ".download_state.json", state)


def parse_length_seconds(value: str) -> int:
    parts = value.split(":")
    if len(parts) == 2 and all(part.isdigit() for part in parts):
        return int(parts[0]) * 60 + int(parts[1])
    return int(value) if value.isdigit() else 0


def pick_best_recordings(recordings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    allowed = [r for r in recordings if r.get("file")]
    allowed.sort(key=lambda r: ((r.get("q") or "Z"), parse_length_seconds(r.get("length") or "")))
    result: list[dict[str, Any]] = []
    seen_types: set[str] = set()
    for record in allowed:
        record_type = (record.get("type") or "").lower()
        normalized = "song" if "song" in record_type else "call" if "call" in record_type else "other"
        if normalized in seen_types:
            continue
        seen_types.add(normalized)
        result.append(record)
        if len(result) >= 2:
            break
    return result


def download_xeno_audio(sci: str, save_dir: Path, api_key: str) -> list[dict[str, str]]:
    parts = sci.split()
    if len(parts) < 2 or not api_key:
        return []
    query = urllib.parse.quote(f'gen:{parts[0]} sp:{parts[1]} grp:birds q:">C"')
    url = f"https://xeno-canto.org/api/3/recordings?query={query}&key={api_key}&per_page=20"
    data = http_json(url)
    recordings = data.get("recordings", []) if isinstance(data, dict) else []
    results: list[dict[str, str]] = []
    for record in pick_best_recordings(recordings):
        record_type = (record.get("type") or "").lower()
        normalized = "song" if "song" in record_type else "call" if "call" in record_type else "other"
        file_url = record.get("file") or ""
        if file_url.startswith("//"):
            file_url = f"https:{file_url}"
        if not file_url:
            continue
        filename = f'{record.get("id", "unknown")}_{normalized}.mp3'
        file_path = save_dir / filename
        if not file_path.exists():
            file_path.write_bytes(http_bytes(file_url))
        results.append(
            {
                "type": normalized,
                "file": f"sounds/{filename}",
                "contributor": record.get("rec", ""),
                "contributor_url": f'https://www.xeno-canto.org/{record.get("id", "")}',
                "license": record.get("lic", ""),
                "date": record.get("date", ""),
                "location": record.get("loc", ""),
            }
        )
    return results


def download_inaturalist_image(sci: str, save_dir: Path) -> tuple[str, dict[str, str]]:
    url = "https://api.inaturalist.org/v1/observations?" + urllib.parse.urlencode(
        {
            "taxon_name": sci,
            "photos": "true",
            "quality_grade": "research",
            "per_page": "8",
            "order_by": "votes",
        }
    )
    data = http_json(url)
    results = data.get("results", []) if isinstance(data, dict) else []
    for observation in results:
        photos = observation.get("photos") or []
        if not photos:
            continue
        photo = photos[0]
        raw_url = photo.get("url") or ""
        if not raw_url:
            continue
        image_url = raw_url.replace("square.", "medium.")
        suffix = Path(urllib.parse.urlparse(image_url).path).suffix.lower()
        ext = suffix if suffix in SUPPORTED_IMAGE_EXTS else ".jpg"
        filename = f'{sci.replace(" ", "_")}{ext}'
        file_path = save_dir / filename
        if not file_path.exists():
            file_path.write_bytes(http_bytes(image_url))
        user = observation.get("user") or {}
        author = (user.get("name") or user.get("login") or "").strip()
        obs_id = observation.get("id", "")
        license_code = (photo.get("license_code") or observation.get("license_code") or "").strip()
        return (
            f"images/{filename}",
            {
                "image_contributor": author,
                "image_contributor_url": f"https://www.inaturalist.org/observations/{obs_id}" if obs_id else "",
                "image_source": "inaturalist",
                "image_license": license_code.upper() if license_code else "",
            },
        )
    return "", {}


def refresh_media(workspace: Path, species_map: dict[str, dict[str, object]], state: dict[str, object], args: argparse.Namespace) -> None:
    errors = state.setdefault("errors", {})
    attempted_this_run = 0
    for index, sci in enumerate(sorted(species_map), start=1):
        entry = species_map[sci]
        if entry.get("audios") and entry.get("image"):
            entry["_attempted"] = True
            continue
        if args.max_downloads > 0 and attempted_this_run >= args.max_downloads:
            break
        print(f"[{index}/{len(species_map)}] {entry['cn']} | {sci}")
        try:
            if not entry.get("audios"):
                audios = download_xeno_audio(sci, workspace / "sounds", args.xeno_key)
                if audios:
                    entry["audios"] = audios
            if not entry.get("image"):
                image, meta = download_inaturalist_image(sci, workspace / "images")
                if image:
                    entry["image"] = image
                    entry.update(meta)
            errors.pop(sci, None)
        except Exception as exc:  # noqa: BLE001
            errors[sci] = str(exc)
            print(f"  !! {exc}")
        finally:
            entry["_attempted"] = True
            attempted_this_run += 1
            write_workspace(workspace, species_map, state)
            time.sleep(max(args.request_delay, 0))


def export_zip(workspace: Path, zip_output: Path) -> None:
    with zipfile.ZipFile(zip_output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for relative in ["manifest.json", "species.json"]:
            path = workspace / relative
            if path.exists():
                zf.write(path, relative)
        for folder in ["sounds", "images"]:
            folder_path = workspace / folder
            if not folder_path.exists():
                continue
            for file_path in folder_path.rglob("*"):
                if file_path.is_file():
                    zf.write(file_path, file_path.relative_to(workspace).as_posix())


def main() -> int:
    args = parse_args()
    workspace = Path(args.workspace).expanduser().resolve()
    species_map, state = load_or_init_workspace(args)
    write_workspace(workspace, species_map, state)

    if args.with_media:
        refresh_media(workspace, species_map, state, args)

    if args.zip_output:
        zip_output = Path(args.zip_output).expanduser().resolve()
        zip_output.parent.mkdir(parents=True, exist_ok=True)
        export_zip(workspace, zip_output)
        print(f"ZIP exported to {zip_output}")

    print(f"Workspace ready: {workspace}")
    print(f"species: {len(species_map)}")
    print(f"audio species: {sum(1 for item in species_map.values() if item.get('audios'))}")
    print(f"image species: {sum(1 for item in species_map.values() if item.get('image'))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
