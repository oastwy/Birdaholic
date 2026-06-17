#!/usr/bin/env python3
"""Build the App built-in China-common-100 pack from the *curated* review pack.

Source of truth = the human-curated review pack at
`birdaholic_inat_top100_review/extracted_pack/` (the one edited via the 8787
review server: deletions, re-ordering, difficulty stars, species swaps, and
user-image-first merges). We deliberately do NOT re-pull from the server here,
so all manual curation is preserved. Image entries already carry
contributor/location/date, so the flashcard `@作者 · 地点 · 时间` line lights up.

Output is a normal App pack zip (no `review_only`), ready to wire into
`pubspec.yaml` + `pack_manager.dart`.
"""

from __future__ import annotations

import io
import json
import zipfile
from datetime import date
from pathlib import Path

from PIL import Image

MAX_LONG_EDGE = 1280
JPEG_QUALITY = 80


REVIEW_DIR = Path(
    "/Users/wuyang/Documents/New project/birdaholic_inat_top100_review/extracted_pack"
)
REPO = Path("/Users/wuyang/Documents/bird_flashcard_repo")
OUT_ZIP = REPO / "data_packs" / "china_common_100_v2.0_opt.zip"
OUT_NAMES = REPO / "assets" / "data" / "china_common_100.json"
PACK_VERSION = "2.0"


def main() -> None:
    species = json.loads((REVIEW_DIR / "species.json").read_text(encoding="utf-8"))
    if not isinstance(species, list) or not species:
        raise SystemExit(f"bad/empty species.json in {REVIEW_DIR}")

    image_count = sum(len(s.get("images") or []) for s in species)
    audio_count = sum(len(s.get("audios") or []) for s in species)
    located = sum(
        1
        for s in species
        for im in (s.get("images") or [])
        if isinstance(im, dict) and str(im.get("location") or "").strip()
    )

    manifest = {
        "name": "中国常见鸟 100",
        "short_name": "中国常见鸟 100",
        "region": "中国",
        "version": PACK_VERSION,
        "created": date.today().isoformat(),
        "species_count": len(species),
        "image_count": image_count,
        "audio_count": audio_count,
        "max_images_per_species": 3,
        "source": "Birdaholic review-curated（iNat 常见100 + 用户上传图优先 + 人工删选/排序/打星）",
        "server_refreshed": True,
        "review_curated": True,
    }

    # only ship media actually referenced by species.json (drops orphans)
    referenced: set[str] = set()
    for s in species:
        for im in s.get("images") or []:
            if isinstance(im, dict) and im.get("file"):
                referenced.add(str(im["file"]))
        for a in s.get("audios") or []:
            if not isinstance(a, dict):
                continue
            if a.get("file"):
                referenced.add(str(a["file"]))
            if a.get("spectrogram"):
                referenced.add(str(a["spectrogram"]))

    def compressed_image(path: Path) -> bytes | None:
        """Downscale to <=MAX_LONG_EDGE and re-encode JPEG; None to copy as-is."""
        if path.suffix.lower() not in (".jpg", ".jpeg"):
            return None
        try:
            with Image.open(path) as im:
                im = im.convert("RGB")
                if max(im.size) > MAX_LONG_EDGE:
                    im.thumbnail((MAX_LONG_EDGE, MAX_LONG_EDGE), Image.LANCZOS)
                buf = io.BytesIO()
                im.save(buf, "JPEG", quality=JPEG_QUALITY, optimize=True, progressive=True)
            data = buf.getvalue()
            # keep whichever is smaller (avoid bloating already-tiny files)
            return data if len(data) < path.stat().st_size else None
        except Exception:
            return None

    OUT_ZIP.parent.mkdir(parents=True, exist_ok=True)
    written: set[str] = set()
    img_saved = 0
    with zipfile.ZipFile(OUT_ZIP, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as out:
        for path in sorted(REVIEW_DIR.rglob("*")):
            if not path.is_file():
                continue
            rel = path.relative_to(REVIEW_DIR).as_posix()
            if rel not in referenced:
                continue  # skip species.json/manifest.json/dotfiles/orphans
            data = compressed_image(path) if rel.startswith("images/") else None
            if data is not None:
                img_saved += path.stat().st_size - len(data)
                out.writestr(rel, data)
            else:
                out.write(path, rel)
            written.add(rel)
        out.writestr("species.json", json.dumps(species, ensure_ascii=False, indent=2))
        out.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))

    # regenerate the bundled names index so it matches the new 100-species list
    names = [
        {
            "cn": s.get("cn") or s.get("zh") or "",
            "en": s.get("en") or "",
            "sci": s.get("sci") or "",
            "order": s.get("order", ""),
            "family": s.get("family", ""),
            "code": s.get("code", ""),
            "description": s.get("description", ""),
            "description_source": s.get("description_source", ""),
        }
        for s in species
    ]
    OUT_NAMES.write_text(
        json.dumps(names, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    size_mb = OUT_ZIP.stat().st_size / 1024 / 1024
    print(f"PACK   {OUT_ZIP}  ({size_mb:.1f} MB)")
    print(f"NAMES  {OUT_NAMES}")
    print(
        f"species={len(species)} images={image_count} (带地点 {located}) audio={audio_count} media_files={len(written)}"
    )
    print(f"图片压缩省下 {img_saved / 1024 / 1024:.1f} MB（只打引用文件，已去孤儿）")


if __name__ == "__main__":
    main()
