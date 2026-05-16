#!/usr/bin/env python3
"""Backfill extra iNaturalist photos into server species manifests.

This tool is intended to run on the media server. It scans
`/data/species/*/manifest.json`, finds species with fewer than three images,
downloads licensed research-grade iNaturalist photos, compresses them, and
updates the manifest in place. It is resumable through a small state file.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


INAT_OBS_URL = "https://api.inaturalist.org/v1/observations"
DEFAULT_BASE_URL = "http://124.223.101.188:8080"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def load_json(path: Path, fallback: Any) -> Any:
    if not path.exists():
        return fallback
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def fetch_json(url: str, timeout: int) -> dict[str, Any]:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "BirdaholicMediaBackfill/1.0",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def download_bytes(url: str, timeout: int) -> bytes:
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "BirdaholicMediaBackfill/1.0"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def photo_url(raw_url: str) -> str:
    if not raw_url:
        return ""
    # iNaturalist commonly returns square thumbnail URLs. Prefer a larger file,
    # then compress locally to keep server transfer predictable.
    return (
        raw_url.replace("square.", "large.")
        .replace("small.", "large.")
        .replace("medium.", "large.")
    )


def species_key(sci: str) -> str:
    return "_".join(sci.strip().split())


def safe_stem(value: str) -> str:
    cleaned = "".join(ch if ch.isalnum() else "_" for ch in value.strip())
    while "__" in cleaned:
        cleaned = cleaned.replace("__", "_")
    return cleaned.strip("_") or "species"


def existing_image_keys(images: list[dict[str, Any]]) -> set[str]:
    keys: set[str] = set()
    for image in images:
        for field in ("url", "contributor_url", "file"):
            value = str(image.get(field) or "").strip()
            if value:
                keys.add(value)
                keys.add(Path(urllib.parse.urlparse(value).path).name)
    return keys


def compress_jpeg(path: Path, max_image: int, jpeg_quality: int) -> None:
    if shutil.which("sips") is None:
        return
    subprocess.run(
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
            str(path),
        ],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def inat_candidates(sci: str, per_page: int, timeout: int) -> list[dict[str, str]]:
    query = urllib.parse.urlencode(
        {
            "taxon_name": sci,
            "photos": "true",
            "quality_grade": "research",
            "order_by": "votes",
            "per_page": str(per_page),
        }
    )
    data = fetch_json(f"{INAT_OBS_URL}?{query}", timeout=timeout)
    candidates: list[dict[str, str]] = []
    for obs in data.get("results", []):
        obs_id = str(obs.get("id") or "")
        observer = obs.get("user") or {}
        contributor = (
            observer.get("name")
            or observer.get("login")
            or obs.get("user_login")
            or "iNaturalist observer"
        )
        obs_url = f"https://www.inaturalist.org/observations/{obs_id}"
        for photo in obs.get("photos") or []:
            raw_url = photo.get("url") or photo.get("large_url") or ""
            url = photo_url(str(raw_url))
            if not url:
                continue
            photo_id = str(photo.get("id") or hashlib.sha1(url.encode()).hexdigest()[:10])
            license_code = str(photo.get("license_code") or "").strip()
            candidates.append(
                {
                    "url": url,
                    "photo_id": photo_id,
                    "obs_id": obs_id,
                    "contributor": str(contributor).strip(),
                    "contributor_url": obs_url,
                    "license": license_code,
                }
            )
    return candidates


def refresh_index(species_dir: Path, index_dir: Path, base_url: str) -> None:
    rows: list[dict[str, Any]] = []
    for manifest_path in sorted(species_dir.glob("*/manifest.json")):
        try:
            manifest = load_json(manifest_path, {})
        except json.JSONDecodeError:
            continue
        sci = str(manifest.get("sci") or "").strip()
        if not sci:
            continue
        images = manifest.get("images") or []
        audio = manifest.get("audio") or []
        key = manifest_path.parent.name
        rows.append(
            {
                "sci": sci,
                "cn": manifest.get("cn") or "",
                "en": manifest.get("en") or "",
                "order": manifest.get("order") or "",
                "family": manifest.get("family") or "",
                "species_dir": key,
                "manifest_url": f"{base_url.rstrip('/')}/species/{key}/manifest.json",
                "image_count": len(images) if isinstance(images, list) else 0,
                "audio_count": len(audio) if isinstance(audio, list) else 0,
                "source_packs": manifest.get("source_packs") or [],
            }
        )
    write_json(
        index_dir / "species_media_index.json",
        {
            "generated_at": now_iso(),
            "species_count": len(rows),
            "species": rows,
        },
    )


def backfill_one(
    manifest_path: Path,
    *,
    base_url: str,
    max_images: int,
    per_page: int,
    timeout: int,
    dry_run: bool,
    max_image: int,
    jpeg_quality: int,
) -> tuple[str, int, str]:
    manifest = load_json(manifest_path, {})
    sci = str(manifest.get("sci") or "").strip()
    if not sci:
        return ("skipped", 0, "missing scientific name")
    images = manifest.get("images")
    if not isinstance(images, list):
        images = []
        manifest["images"] = images
    if len(images) >= max_images:
        return ("skipped", 0, f"already has {len(images)} images")

    key = manifest_path.parent.name
    image_dir = manifest_path.parent / "images"
    seen = existing_image_keys([img for img in images if isinstance(img, dict)])
    added = 0
    candidates = inat_candidates(sci, per_page=per_page, timeout=timeout)
    for candidate in candidates:
        if len(images) >= max_images:
            break
        url = candidate["url"]
        basename = Path(urllib.parse.urlparse(url).path).name
        if (
            url in seen
            or basename in seen
            or candidate["contributor_url"] in seen
        ):
            continue
        filename = (
            f"{safe_stem(sci)}_inat_{candidate['obs_id']}_"
            f"{candidate['photo_id']}.jpg"
        )
        rel_path = f"images/{filename}"
        if rel_path in seen or filename in seen:
            continue
        if not dry_run:
            image_dir.mkdir(parents=True, exist_ok=True)
            target = image_dir / filename
            target.write_bytes(download_bytes(url, timeout=timeout))
            compress_jpeg(target, max_image=max_image, jpeg_quality=jpeg_quality)
        images.append(
            {
                "file": rel_path,
                "url": f"{base_url.rstrip('/')}/species/{key}/{rel_path}",
                "contributor": candidate["contributor"],
                "contributor_url": candidate["contributor_url"],
                "license": candidate["license"],
                "source": "inaturalist",
            }
        )
        seen.add(url)
        seen.add(filename)
        seen.add(rel_path)
        seen.add(candidate["contributor_url"])
        added += 1

    if added and not dry_run:
        write_json(manifest_path, manifest)
    status = "updated" if added else "skipped"
    reason = f"added {added}" if added else "no usable new photos"
    return (status, added, reason)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", default="/data")
    parser.add_argument("--species-dir")
    parser.add_argument("--index-dir")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--max-images", type=int, default=3)
    parser.add_argument("--per-page", type=int, default=20)
    parser.add_argument("--per-run", type=int, default=0)
    parser.add_argument("--sleep", type=float, default=0.3)
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--max-image", type=int, default=1600)
    parser.add_argument("--jpeg-quality", type=int, default=70)
    args = parser.parse_args()

    data_dir = Path(args.data_dir)
    species_dir = Path(args.species_dir) if args.species_dir else data_dir / "species"
    index_dir = Path(args.index_dir) if args.index_dir else data_dir / "indexes"
    state_path = data_dir / ".inat_photo_backfill_state.json"
    state = load_json(state_path, {"updated_at": "", "species": {}})
    state_species = state.setdefault("species", {})

    processed = 0
    added_total = 0
    for manifest_path in sorted(species_dir.glob("*/manifest.json")):
        if args.per_run and processed >= args.per_run:
            break
        key = manifest_path.parent.name
        try:
            status, added, reason = backfill_one(
                manifest_path,
                base_url=args.base_url,
                max_images=args.max_images,
                per_page=args.per_page,
                timeout=args.timeout,
                dry_run=args.dry_run,
                max_image=args.max_image,
                jpeg_quality=args.jpeg_quality,
            )
            added_total += added
            print(f"{key}: {status} ({reason})")
        except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
            status, added, reason = "failed", 0, str(exc)
            print(f"{key}: failed ({exc})", file=sys.stderr)
        state_species[key] = {
            "status": status,
            "added": added,
            "reason": reason,
            "updated_at": now_iso(),
        }
        state["updated_at"] = now_iso()
        if not args.dry_run:
            write_json(state_path, state)
        processed += 1
        if args.sleep > 0:
            time.sleep(args.sleep)

    if not args.dry_run:
        refresh_index(species_dir, index_dir, args.base_url)
    print(f"Done. processed={processed}, added_photos={added_total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
