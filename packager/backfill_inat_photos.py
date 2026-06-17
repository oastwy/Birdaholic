#!/usr/bin/env python3
"""Backfill extra iNaturalist photos into server species manifests.

This tool is intended to run on the media server. It scans
`/data/species/*/manifest.json`, finds species with fewer than three images,
downloads licensed research-grade iNaturalist photos, compresses them, and
updates the manifest in place. It is resumable through a small state file.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


INAT_OBS_URL = "https://api.inaturalist.org/v1/observations"
DEFAULT_BASE_URL = "http://124.223.101.188:8080"

# Free Cultural Works / Wikimedia-compatible licenses only. We deliberately
# exclude NC (non-commercial: incompatible with an open-source app that may be
# distributed commercially or forked) and ND (no-derivatives: we resize/recompress
# the photo, which is itself a derivative). A null/empty code means
# "all rights reserved" and must NOT be re-hosted.
OPEN_LICENSES = {"cc0", "cc-by", "cc-by-sa"}


def is_open_license(code: str) -> bool:
    return (code or "").strip().lower() in OPEN_LICENSES


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


def _compress_with_pil(path: Path, max_image: int, jpeg_quality: int) -> bool:
    """Resize+re-encode as JPEG using Pillow (available on the Linux server)."""
    try:
        from PIL import Image, ImageOps
    except Exception:
        return False
    try:
        with Image.open(path) as im:
            im = ImageOps.exif_transpose(im)
            if im.mode != "RGB":
                im = im.convert("RGB")
            w, h = im.size
            scale = min(1.0, max_image / max(w, h))
            if scale < 1.0:
                im = im.resize((int(w * scale), int(h * scale)), Image.LANCZOS)
            im.save(path, format="JPEG", quality=jpeg_quality, optimize=True, progressive=True)
        return True
    except Exception:
        return False


def compress_jpeg(path: Path, max_image: int, jpeg_quality: int) -> None:
    # Prefer Pillow (cross-platform); fall back to macOS `sips` for local runs.
    if _compress_with_pil(path, max_image, jpeg_quality):
        return
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
        place = str(obs.get("place_guess") or "").strip()
        coords = str(obs.get("location") or "").strip()  # "lat,lng"
        observed_on = str(obs.get("observed_on") or "").strip()
        for photo in obs.get("photos") or []:
            raw_url = photo.get("url") or photo.get("large_url") or ""
            url = photo_url(str(raw_url))
            if not url:
                continue
            photo_id = str(photo.get("id") or hashlib.sha1(url.encode()).hexdigest()[:10])
            license_code = str(photo.get("license_code") or "").strip().lower()
            # Skip "all rights reserved" / non-CC photos; we only re-host open licenses.
            if not is_open_license(license_code):
                continue
            candidates.append(
                {
                    "url": url,
                    "photo_id": photo_id,
                    "obs_id": obs_id,
                    "contributor": str(contributor).strip(),
                    "contributor_url": obs_url,
                    "license": license_code,
                    "location": place,
                    "coords": coords,
                    "observed_on": observed_on,
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
                # Match upload_server.update_index(): count only non-pending media.
                "image_count": sum(1 for x in images if isinstance(x, dict) and not x.get("pending")),
                "audio_count": sum(1 for x in audio if isinstance(x, dict) and not x.get("pending")),
                "source_packs": manifest.get("source_packs") or [],
            }
        )
    # IMPORTANT: write a bare JSON list (same shape as the upload server's
    # update_index()); clients iterate this file as a list of rows.
    write_json(index_dir / "species_media_index.json", rows)


def ensure_compressed(path: Path, max_image: int, jpeg_quality: int, target_kb: int = 600) -> bool:
    """Compress an existing image only if it exceeds size/dimension bounds.
    Idempotent: already-small images are left untouched (no needless re-encode)."""
    if not path.exists():
        return False
    try:
        from PIL import Image
        with Image.open(path) as im:
            w, h = im.size
        too_big = max(w, h) > max_image or path.stat().st_size > target_kb * 1024
    except Exception:
        too_big = path.stat().st_size > target_kb * 1024
    if not too_big:
        return False
    compress_jpeg(path, max_image=max_image, jpeg_quality=jpeg_quality)
    return True


def _fix_main_image_fields(manifest: dict[str, Any], images: list[dict[str, Any]]) -> None:
    """Keep an optional top-level main-image pointer valid after edits."""
    if "image" not in manifest and "image_credit" not in manifest and "image_license" not in manifest:
        return
    files = {str(e.get("file") or "") for e in images if isinstance(e, dict)}
    cur = str(manifest.get("image") or "")
    if cur and cur in files:
        return
    first = next((e for e in images if isinstance(e, dict) and not e.get("pending")), None)
    if first:
        manifest["image"] = first.get("file", "")
        manifest["image_credit"] = first.get("credit") or first.get("contributor", "")
        manifest["image_license"] = first.get("license", "")
    else:
        for field in ("image", "image_credit", "image_license"):
            manifest.pop(field, None)


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
    purge_nonopen: bool = False,
    compress_existing: bool = False,
) -> tuple[str, int, str]:
    manifest = load_json(manifest_path, {})
    sci = str(manifest.get("sci") or "").strip()
    if not sci:
        return ("skipped", 0, "missing scientific name")
    images = manifest.get("images")
    if not isinstance(images, list):
        images = []
        manifest["images"] = images

    key = manifest_path.parent.name
    image_dir = manifest_path.parent / "images"
    changed = False
    purged = compressed = added = 0
    # 被管理员清空过的物种：自动补图只能进待审核队列，需人工审核后才发布
    review_mode = bool(manifest.get("backfill_review"))

    # 1) Classify existing images. When purging, non-open iNaturalist photos are
    #    *removal candidates* — but we don't delete them yet. User uploads
    #    (source != inaturalist) and already-open images are always kept.
    removal_candidates: list[dict[str, Any]] = []
    keep: list[Any] = []
    if purge_nonopen:
        for e in images:
            if (
                isinstance(e, dict)
                and str(e.get("source") or "").strip().lower() == "inaturalist"
                and not is_open_license(str(e.get("license") or "").strip().lower())
            ):
                removal_candidates.append(e)
            else:
                keep.append(e)
    else:
        keep = list(images)

    # 2) Top up `keep` toward max_images with NEW open-licensed photos.
    #    Track whether the API call actually succeeded — a network failure must
    #    NOT be mistaken for "no open photos exist".
    new_entries: list[dict[str, Any]] = []
    candidates: list[dict[str, str]] = []
    api_ok = True
    if len(keep) < max_images:
        try:
            candidates = inat_candidates(sci, per_page=per_page, timeout=timeout)
        except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError):
            api_ok = False
        seen = existing_image_keys([img for img in images if isinstance(img, dict)])
        for candidate in candidates:
            if len(keep) + len(new_entries) >= max_images:
                break
            url = candidate["url"]
            basename = Path(urllib.parse.urlparse(url).path).name
            if url in seen or basename in seen or candidate["contributor_url"] in seen:
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
                try:
                    target.write_bytes(download_bytes(url, timeout=timeout))
                except (urllib.error.URLError, TimeoutError, OSError):
                    # One stalled/broken photo host must not block the species;
                    # drop the partial file and try the next candidate.
                    try:
                        if target.exists():
                            target.unlink()
                    except OSError:
                        pass
                    continue
                compress_jpeg(target, max_image=max_image, jpeg_quality=jpeg_quality)
            entry = {
                "file": rel_path,
                "url": f"{base_url.rstrip('/')}/species/{key}/{rel_path}",
                "contributor": candidate["contributor"],
                "contributor_url": candidate["contributor_url"],
                "license": candidate["license"],
                "source": "inaturalist",
            }
            if candidate.get("location"):
                entry["location"] = candidate["location"]
            if candidate.get("coords"):
                entry["coords"] = candidate["coords"]
            if candidate.get("observed_on"):
                entry["observed_on"] = candidate["observed_on"]
            if review_mode:
                entry["pending"] = True
                entry["pending_reason"] = "backfill_review"
            new_entries.append(entry)
            seen.add(url)
            seen.add(filename)
            seen.add(rel_path)
            seen.add(candidate["contributor_url"])

    # 3) Decide removal — NON-LOSSY: only drop a non-open original when we have a
    #    replacement (an existing open/user image or a freshly downloaded one),
    #    OR the API positively confirmed there are zero open photos for this taxon.
    #    A network failure leaves the originals in place to retry next pass.
    removed: list[dict[str, Any]] = []
    if purge_nonopen and removal_candidates:
        have_replacement = bool(keep) or bool(new_entries)
        confirmed_none = api_ok and not candidates
        if have_replacement or confirmed_none:
            removed = removal_candidates
            if not dry_run:
                for e in removed:
                    fp = manifest_path.parent / str(e.get("file") or "")
                    try:
                        if fp.exists():
                            fp.unlink()
                    except OSError:
                        pass
        else:
            keep = keep + removal_candidates  # keep as fallback; retry later

    images[:] = keep + new_entries
    added = len(new_entries)
    purged = len(removed)
    if added or purged:
        changed = True

    # 4) Compress kept images that exceed bounds (new downloads are already compressed).
    if compress_existing and not dry_run:
        for e in images:
            if not isinstance(e, dict) or e in new_entries:
                continue
            fp = manifest_path.parent / str(e.get("file") or "")
            if ensure_compressed(fp, max_image, jpeg_quality):
                compressed += 1
                changed = True

    if changed:
        # Defensive ordering: iNaturalist photos rank BELOW user-uploaded /
        # openly-licensed images. Stable sort preserves relative order within
        # each group, so an admin-approved upload at index 0 stays on top.
        images.sort(key=lambda img: 1 if str(img.get("source") or "").strip().lower() == "inaturalist" else 0)
        _fix_main_image_fields(manifest, images)
    if changed and not dry_run:
        write_json(manifest_path, manifest)

    if added or purged or compressed:
        return ("updated", added, f"added {added}, purged {purged}, compressed {compressed}, now {len(images)} imgs")
    return ("skipped", 0, "nothing to do")


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
    parser.add_argument(
        "--purge-nonopen-inat",
        action="store_true",
        help="Remove iNaturalist images whose license is not CC0/BY/SA (and delete the files).",
    )
    parser.add_argument(
        "--compress-existing",
        action="store_true",
        help="Re-compress already-stored images that exceed the size/dimension bounds.",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=1,
        help="Concurrent species workers. >1 parallelizes the (network-bound) "
        "downloads — important when per-connection bandwidth is throttled.",
    )
    args = parser.parse_args()

    # Bound EVERY network operation (connect + read), so a trickling or
    # half-open photo host can't hang the run indefinitely.
    socket.setdefaulttimeout(args.timeout)

    data_dir = Path(args.data_dir)
    species_dir = Path(args.species_dir) if args.species_dir else data_dir / "species"
    index_dir = Path(args.index_dir) if args.index_dir else data_dir / "indexes"
    state_path = data_dir / ".inat_photo_backfill_state.json"
    state = load_json(state_path, {"updated_at": "", "species": {}})
    state_species = state.setdefault("species", {})

    manifest_paths = sorted(species_dir.glob("*/manifest.json"))
    if args.per_run:
        manifest_paths = manifest_paths[: args.per_run]

    def process(manifest_path: Path) -> tuple[str, str, int, str]:
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
                purge_nonopen=args.purge_nonopen_inat,
                compress_existing=args.compress_existing,
            )
        except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
            return (key, "failed", 0, str(exc))
        if args.sleep > 0:
            time.sleep(args.sleep)  # politeness jitter toward the iNat API
        return (key, status, added, reason)

    processed = 0
    added_total = 0
    state_lock = threading.Lock()

    def record(key: str, status: str, added: int, reason: str) -> None:
        nonlocal processed, added_total
        with state_lock:
            added_total += added
            if status == "failed":
                print(f"{key}: failed ({reason})", file=sys.stderr)
            else:
                print(f"{key}: {status} ({reason})", flush=True)
            state_species[key] = {
                "status": status,
                "added": added,
                "reason": reason,
                "updated_at": now_iso(),
            }
            state["updated_at"] = now_iso()
            processed += 1
            # Persist state periodically (every species in serial mode; batched in parallel).
            if not args.dry_run and (args.workers <= 1 or processed % 25 == 0):
                write_json(state_path, state)

    if args.workers > 1:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as ex:
            futures = [ex.submit(process, mp) for mp in manifest_paths]
            for fut in concurrent.futures.as_completed(futures):
                record(*fut.result())
    else:
        for mp in manifest_paths:
            record(*process(mp))

    if not args.dry_run:
        write_json(state_path, state)
        refresh_index(species_dir, index_dir, args.base_url)
    print(f"Done. processed={processed}, added_photos={added_total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
