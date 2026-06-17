#!/usr/bin/env python3
"""Remove backfilled iNaturalist photos whose license is NOT in the
open-source-safe set (CC0 / CC-BY / CC-BY-SA).

Only touches entries this backfill tool created (source == "inaturalist" AND
filename contains "_inat_"); original pre-existing images are left alone.
Deletes the orphaned image files and rewrites the manifest preserving order,
then regenerates species_media_index.json in the same list format the upload
server uses.
"""
from __future__ import annotations

import glob
import json
from pathlib import Path

ALLOWED = {"cc0", "cc-by", "cc-by-sa"}
SPECIES_GLOB = "/data/species/*/manifest.json"
INDEX_PATH = Path("/data/indexes/species_media_index.json")
BASE_URL = "http://124.223.101.188:8080"


def main() -> None:
    removed = files_deleted = species_changed = 0
    for mp in glob.glob(SPECIES_GLOB):
        manifest = json.loads(Path(mp).read_text(encoding="utf-8"))
        imgs = manifest.get("images")
        if not isinstance(imgs, list):
            continue
        kept = []
        changed = False
        for e in imgs:
            src = str(e.get("source") or "").strip().lower()
            f = str(e.get("file") or "")
            lic = str(e.get("license") or "").strip().lower()
            backfilled = src == "inaturalist" and "_inat_" in f
            if backfilled and lic not in ALLOWED:
                fp = Path(mp).parent / f
                try:
                    if fp.exists():
                        fp.unlink()
                        files_deleted += 1
                except OSError:
                    pass
                removed += 1
                changed = True
                print(f"  remove {manifest.get('sci')} <- {lic or 'no-license'} {f}")
                continue
            kept.append(e)
        if changed:
            manifest["images"] = kept
            Path(mp).write_text(
                json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            species_changed += 1

    # Regenerate index (bare list; counts exclude pending) so stats stay accurate.
    rows = []
    for mp in sorted(glob.glob(SPECIES_GLOB)):
        m = json.loads(Path(mp).read_text(encoding="utf-8"))
        sci = str(m.get("sci") or "").strip()
        if not sci:
            continue
        key = Path(mp).parent.name
        images = m.get("images") or []
        audio = m.get("audio") or []
        rows.append({
            "sci": sci,
            "cn": m.get("cn") or "",
            "en": m.get("en") or "",
            "order": m.get("order") or "",
            "family": m.get("family") or "",
            "species_dir": key,
            "manifest_url": f"{BASE_URL}/species/{key}/manifest.json",
            "image_count": sum(1 for x in images if isinstance(x, dict) and not x.get("pending")),
            "audio_count": sum(1 for x in audio if isinstance(x, dict) and not x.get("pending")),
            "source_packs": m.get("source_packs") or [],
        })
    INDEX_PATH.parent.mkdir(parents=True, exist_ok=True)
    INDEX_PATH.write_text(
        json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Done. removed_entries={removed} files_deleted={files_deleted} "
          f"species_changed={species_changed} index_rows={len(rows)}")


if __name__ == "__main__":
    main()
