#!/usr/bin/env python3
"""Generate the China common 100 list from sampled eBird recent observations.

The eBird country recent-observations endpoint is a species list, not an
abundance ranking. This script samples geo-recent observations around a set of
representative China locations, then ranks species by how many sample locations
reported them. Media and Chinese names still come from the existing full China
pack so the bundled pack remains compatible with Birdaholic.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import time
import urllib.parse
import urllib.request
import zipfile
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
FULL_CHINA_PACK = ROOT / "data_packs" / "china_birds_v1.0_opt.zip"
OUTPUT_LIST = ROOT / "assets" / "data" / "china_common_100.json"
BUILDER = ROOT / "packager" / "build_china_common_100_pack.py"
DEFAULT_CACHE = Path.home() / ".cache" / "birdaholic_ebird_common_100"

SAMPLE_POINTS = [
    ("Beijing", 39.9042, 116.4074),
    ("Tianjin", 39.3434, 117.3616),
    ("Shijiazhuang", 38.0428, 114.5149),
    ("Taiyuan", 37.8706, 112.5489),
    ("Hohhot", 40.8426, 111.7492),
    ("Shenyang", 41.8057, 123.4315),
    ("Changchun", 43.8171, 125.3235),
    ("Harbin", 45.8038, 126.5350),
    ("Shanghai", 31.2304, 121.4737),
    ("Nanjing", 32.0603, 118.7969),
    ("Hangzhou", 30.2741, 120.1551),
    ("Hefei", 31.8206, 117.2272),
    ("Fuzhou", 26.0745, 119.2965),
    ("Xiamen", 24.4798, 118.0894),
    ("Nanchang", 28.6820, 115.8579),
    ("Jinan", 36.6512, 117.1201),
    ("Qingdao", 36.0671, 120.3826),
    ("Zhengzhou", 34.7466, 113.6254),
    ("Wuhan", 30.5928, 114.3055),
    ("Changsha", 28.2282, 112.9388),
    ("Guangzhou", 23.1291, 113.2644),
    ("Shenzhen", 22.5431, 114.0579),
    ("Nanning", 22.8170, 108.3669),
    ("Haikou", 20.0440, 110.1999),
    ("Chengdu", 30.5728, 104.0668),
    ("Chongqing", 29.5630, 106.5516),
    ("Guiyang", 26.6470, 106.6302),
    ("Kunming", 25.0389, 102.7183),
    ("Dali", 25.6065, 100.2676),
    ("Lhasa", 29.6500, 91.1000),
    ("Xian", 34.3416, 108.9398),
    ("Lanzhou", 36.0611, 103.8343),
    ("Xining", 36.6171, 101.7782),
    ("Yinchuan", 38.4872, 106.2309),
    ("Urumqi", 43.8256, 87.6168),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--back", type=int, default=30)
    parser.add_argument("--dist", type=int, default=50)
    parser.add_argument("--limit", type=int, default=100)
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE)
    parser.add_argument("--output", type=Path, default=OUTPUT_LIST)
    parser.add_argument("--source-pack", type=Path, default=FULL_CHINA_PACK)
    parser.add_argument("--update-builder", action="store_true")
    parser.add_argument("--sleep", type=float, default=0.2)
    return parser.parse_args()


def fetch_geo_recent(
    *,
    token: str,
    lat: float,
    lng: float,
    back: int,
    dist: int,
    cache_path: Path,
) -> list[dict]:
    if cache_path.exists():
        return json.loads(cache_path.read_text(encoding="utf-8"))

    params = urllib.parse.urlencode(
        {
            "lat": lat,
            "lng": lng,
            "dist": dist,
            "back": back,
            "includeProvisional": "false",
            "maxResults": 10000,
        }
    )
    url = f"https://api.ebird.org/v2/data/obs/geo/recent?{params}"
    request = urllib.request.Request(url, headers={"X-eBirdApiToken": token})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = json.loads(response.read().decode("utf-8"))
    cache_path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    return data


def load_pack_species(source_pack: Path) -> dict[str, dict]:
    with zipfile.ZipFile(source_pack) as zf:
        species = json.loads(zf.read("species.json").decode("utf-8"))
    return {item["sci"].strip().lower(): item for item in species}


def rank_species(args: argparse.Namespace, token: str) -> list[tuple[str, dict]]:
    args.cache_dir.mkdir(parents=True, exist_ok=True)
    point_counter: Counter[str] = Counter()
    record_counter: Counter[str] = Counter()
    individual_counter: Counter[str] = Counter()
    latest_common_name: dict[str, str] = {}
    latest_code: dict[str, str] = {}
    point_names: dict[str, set[str]] = defaultdict(set)

    for name, lat, lng in SAMPLE_POINTS:
        cache_name = f"{name}_{args.back}d_{args.dist}km.json"
        observations = fetch_geo_recent(
            token=token,
            lat=lat,
            lng=lng,
            back=args.back,
            dist=args.dist,
            cache_path=args.cache_dir / cache_name,
        )
        seen_here: set[str] = set()
        for obs in observations:
            sci = (obs.get("sciName") or "").strip()
            if not sci:
                continue
            seen_here.add(sci)
            record_counter[sci] += 1
            how_many = obs.get("howMany")
            if isinstance(how_many, int):
                individual_counter[sci] += how_many
            latest_common_name[sci] = obs.get("comName") or ""
            latest_code[sci] = obs.get("speciesCode") or ""
        for sci in seen_here:
            point_counter[sci] += 1
            point_names[sci].add(name)
        print(f"{name}: {len(seen_here)} species")
        time.sleep(args.sleep)

    ranked = []
    for sci, point_count in point_counter.items():
        ranked.append(
            (
                sci,
                {
                    "ebird_common_name": latest_common_name.get(sci, ""),
                    "ebird_code": latest_code.get(sci, ""),
                    "sample_points": point_count,
                    "record_count": record_counter[sci],
                    "individual_count": individual_counter[sci],
                    "points": sorted(point_names[sci]),
                },
            )
        )
    ranked.sort(
        key=lambda item: (
            item[1]["sample_points"],
            item[1]["record_count"],
            item[1]["individual_count"],
            item[0],
        ),
        reverse=True,
    )
    return ranked


def write_common_list(
    ranked: list[tuple[str, dict]],
    by_sci: dict[str, dict],
    output: Path,
    limit: int,
) -> list[str]:
    selected: list[dict] = []
    selected_sci: list[str] = []
    skipped = []
    for sci, score in ranked:
        item = by_sci.get(sci.lower())
        if item is None:
            skipped.append(sci)
            continue
        selected_sci.append(item.get("sci", sci))
        selected.append(
            {
                "cn": item.get("cn", ""),
                "en": item.get("en", "") or score["ebird_common_name"],
                "sci": item.get("sci", sci),
                "order": item.get("order", ""),
                "family": item.get("family", ""),
                "code": score["ebird_code"],
                "ebird_sample_points": score["sample_points"],
                "ebird_record_count": score["record_count"],
            }
        )
        if len(selected) >= limit:
            break

    output.write_text(json.dumps(selected, ensure_ascii=False, indent=2), encoding="utf-8")
    if skipped:
        print(f"Skipped {len(skipped)} eBird species not in source pack.")
    print(f"Wrote {output} ({len(selected)} species)")
    return selected_sci


def update_builder_list(builder: Path, sci_names: list[str]) -> None:
    text = builder.read_text(encoding="utf-8")
    replacement = "COMMON_100 = [\n" + "".join(
        f'    "{sci}",\n' for sci in sci_names
    ) + "]"
    new_text, count = re.subn(
        r"COMMON_100 = \[\n(?:    \".*\",\n)*\]",
        replacement,
        text,
        count=1,
    )
    if count != 1:
        raise SystemExit("Could not update COMMON_100 in builder script")
    builder.write_text(new_text, encoding="utf-8")
    print(f"Updated {builder}")


def main() -> None:
    args = parse_args()
    token = os.environ.get("EBIRD_API_TOKEN", "").strip()
    if not token:
        raise SystemExit("Set EBIRD_API_TOKEN before running this script.")

    by_sci = load_pack_species(args.source_pack)
    ranked = rank_species(args, token)
    selected_sci = write_common_list(ranked, by_sci, args.output, args.limit)
    if args.update_builder:
        update_builder_list(BUILDER, selected_sci)


if __name__ == "__main__":
    main()
