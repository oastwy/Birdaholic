#!/usr/bin/env python3
"""Build a resumable China birds data pack workspace and optional ZIP package.

Features:
1. Generate a skeleton pack from `china_birds.json`
2. Optionally download audio from Xeno-Canto and images from Wikimedia
3. Persist progress after every species for safe resume
4. Optionally export the current workspace as a ZIP package for the Flutter app
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


SUPPORTED_IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
DEFAULT_HEADERS = {
    "User-Agent": "BirdaholicPackBuilder/1.0 (https://birding.today)",
    "Accept": "*/*",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate China birds pack workspace")
    parser.add_argument(
        "--china-birds-json",
        default=str(
            Path(__file__).resolve().parent.parent / "assets" / "data" / "china_birds.json"
        ),
        help="Input china_birds.json path",
    )
    parser.add_argument(
        "--filter-codes-file",
        default="",
        help="Optional text/json file of eBird species codes used to filter the source list",
    )
    parser.add_argument(
        "--workspace",
        required=True,
        help="Output workspace directory used for resumable generation",
    )
    parser.add_argument("--pack-name", default="中国鸟类名录")
    parser.add_argument("--region", default="中国")
    parser.add_argument("--version", default="1.0")
    parser.add_argument(
        "--with-media",
        action="store_true",
        help="Attempt to download audio/images into the workspace",
    )
    parser.add_argument("--xeno-key", default="", help="Xeno-Canto API key")
    parser.add_argument("--max-species", type=int, default=0, help="Limit species count for testing")
    parser.add_argument(
        "--zip-output",
        default="",
        help="Optional ZIP output path. If set, exports current workspace as a data pack ZIP.",
    )
    parser.add_argument(
        "--request-delay",
        type=float,
        default=0.5,
        help="Delay between remote requests in seconds",
    )
    parser.add_argument(
        "--max-downloads",
        type=int,
        default=0,
        help="Optional cap on how many species to attempt downloading in this run",
    )
    return parser.parse_args()


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def dump_json(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def normalize_cons(value: str) -> str:
    return {"一级": "1", "二级": "2", "1": "1", "2": "2"}.get(value.strip(), "")


def create_species_entry(item: dict[str, str]) -> dict[str, object]:
    entry = {
        "cn": (item.get("zh") or "").strip() or (item.get("en") or "").strip() or item["sci"],
        "en": (item.get("en") or "").strip() or item["sci"],
        "sci": item["sci"].strip(),
        "audios": [],
    }
    cons = normalize_cons(item.get("protection") or "")
    if cons:
        entry["cons"] = cons
    return entry


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
      raw_species = load_json(Path(args.china_birds_json).expanduser().resolve())
      allowed_codes = load_filter_codes(args.filter_codes_file)
      if allowed_codes:
          raw_species = [
              item for item in raw_species
              if ((item.get("code") or "").strip().lower() in allowed_codes)
          ]
      if args.max_species > 0:
          raw_species = raw_species[: args.max_species]
      species_map = {
          item["sci"].strip(): create_species_entry(item)
          for item in raw_species
          if (item.get("sci") or "").strip()
      }
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
            "species_total": len(species_map),
            "success_audio_species": 0,
            "success_image_species": 0,
            "processed_species": 0,
            "errors": {},
            "media_mode": args.with_media,
        }
        dump_json(state_path, state)

    return species_map, state


def load_filter_codes(path_str: str) -> set[str]:
    if not path_str:
        return set()
    path = Path(path_str).expanduser().resolve()
    if not path.exists():
        raise FileNotFoundError(f"filter codes file not found: {path}")
    text = path.read_text(encoding="utf-8").strip()
    if not text:
        return set()
    if path.suffix.lower() == ".json":
        data = json.loads(text)
        if isinstance(data, list):
            return {str(item).strip().lower() for item in data if str(item).strip()}
    return {line.strip().lower() for line in text.splitlines() if line.strip()}


def write_workspace(workspace: Path, species_map: dict[str, dict[str, object]], state: dict[str, object]) -> None:
    species_list = sorted(species_map.values(), key=lambda item: item["cn"])
    serializable_species = [
        {key: value for key, value in item.items() if not key.startswith("_")}
        for item in species_list
    ]
    dump_json(workspace / "species.json", serializable_species)

    audio_count = sum(len(item.get("audios", [])) for item in serializable_species)
    image_count = sum(1 for item in serializable_species if item.get("image"))
    manifest = {
        "name": state["pack_name"],
        "region": state["region"],
        "version": state["version"],
        "created": state["created"],
        "species_count": len(serializable_species),
        "audio_count": audio_count,
        "image_count": image_count,
        "source": "china_birds.json + Xeno-Canto + Wikimedia Commons",
    }
    dump_json(workspace / "manifest.json", manifest)

    state["updated"] = datetime.now().isoformat(timespec="seconds")
    state["success_audio_species"] = sum(1 for item in species_list if item.get("audios"))
    state["success_image_species"] = sum(1 for item in species_list if item.get("image"))
    state["processed_species"] = sum(
        1
        for item in species_list
        if item.get("audios") or item.get("image") or item.get("_attempted")
    )
    dump_json(workspace / ".download_state.json", state)


def http_json(url: str) -> dict | list:
    request = urllib.request.Request(url, headers=DEFAULT_HEADERS)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def http_bytes(url: str) -> bytes:
    request = urllib.request.Request(url, headers=DEFAULT_HEADERS)
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def pick_best_recordings(recordings: list[dict]) -> list[dict]:
    allowed = [r for r in recordings if r.get("file")]
    allowed.sort(key=lambda r: ((r.get("q") or "Z"), parse_length_seconds(r.get("length") or "")))
    result: list[dict] = []
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


def parse_length_seconds(value: str) -> int:
    parts = value.split(":")
    if len(parts) == 2 and all(part.isdigit() for part in parts):
        return int(parts[0]) * 60 + int(parts[1])
    return int(value) if value.isdigit() else 0


def download_xeno_audio(sci: str, save_dir: Path, api_key: str) -> list[dict[str, str]]:
    parts = sci.split()
    if len(parts) < 2 or not api_key:
        return []
    query = urllib.parse.quote(f'gen:{parts[0]} sp:{parts[1]} grp:birds q:">C"')
    url = f"https://xeno-canto.org/api/3/recordings?query={query}&key={api_key}&per_page=20"
    data = http_json(url)
    recordings = data.get("recordings", []) if isinstance(data, dict) else []
    selected = pick_best_recordings(recordings)
    results: list[dict[str, str]] = []

    for record in selected:
        record_type = (record.get("type") or "").lower()
        normalized = "song" if "song" in record_type else "call" if "call" in record_type else "other"
        file_url = record.get("file") or ""
        if file_url.startswith("//"):
            file_url = f"https:{file_url}"
        if not file_url:
            continue
        filename = f'{record.get("id","unknown")}_{normalized}.mp3'
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


def search_wikimedia_urls(sci: str) -> list[str]:
    query = sci.replace(" ", "_")
    url = (
        "https://commons.wikimedia.org/w/api.php?"
        f"action=query&generator=categorymembers&gcmtitle=Category:{urllib.parse.quote(query)}"
        "&gcmtype=file&gcmlimit=5&prop=imageinfo&iiprop=url|size&iiurlwidth=640&format=json"
    )
    data = http_json(url)
    pages = (((data or {}).get("query") or {}).get("pages") or {}) if isinstance(data, dict) else {}
    urls: list[str] = []
    for page in pages.values():
        infos = page.get("imageinfo") or []
        if not infos:
            continue
        info = infos[0]
        thumb = info.get("thumburl") or info.get("url") or ""
        if thumb:
            urls.append(thumb)
    return urls


def download_wikimedia_image(sci: str, save_dir: Path) -> str:
    urls = search_wikimedia_urls(sci)
    if not urls:
        return ""
    for url in urls:
        suffix = Path(urllib.parse.urlparse(url).path).suffix.lower()
        ext = suffix if suffix in SUPPORTED_IMAGE_EXTS else ".jpg"
        filename = f'{sci.replace(" ", "_")}{ext}'
        file_path = save_dir / filename
        if not file_path.exists():
            file_path.write_bytes(http_bytes(url))
        return f"images/{filename}"
    return ""


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
                image = download_wikimedia_image(sci, workspace / "images")
                if image:
                    entry["image"] = image

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
        if not args.xeno_key:
            print("❌ 使用 --with-media 时必须提供 --xeno-key", file=sys.stderr)
            return 1
        refresh_media(workspace, species_map, state, args)

    if args.zip_output:
        zip_output = Path(args.zip_output).expanduser().resolve()
        zip_output.parent.mkdir(parents=True, exist_ok=True)
        export_zip(workspace, zip_output)
        print(f"✅ ZIP exported to {zip_output}")

    print(f"✅ Workspace ready: {workspace}")
    print(f"   species: {len(species_map)}")
    print(f"   audio species: {sum(1 for item in species_map.values() if item.get('audios'))}")
    print(f"   image species: {sum(1 for item in species_map.values() if item.get('image'))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
