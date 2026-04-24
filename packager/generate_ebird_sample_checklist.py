#!/usr/bin/env python3
"""Merge eBird hotspot HTML exports into a lightweight sample checklist CSV."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

from bs4 import BeautifulSoup

MANUAL_CHINESE_ALIASES_BY_ENGLISH = {
    "Asian Tit": "大山雀",
    "Black Swan": "黑天鹅",
    "Black-crested Bulbul": "黑冠黄鹎",
    "Blue-eared Barbet": "蓝耳拟啄木鸟",
    "Blue-throated Barbet": "蓝喉拟啄木鸟",
    "Blue-winged Leafbird": "蓝翅叶鹎",
    "Brown-winged Parrotbill": "褐翅鸦雀",
    "Coppersmith Barbet": "赤胸拟啄木鸟",
    "Eastern Cattle-Egret": "牛背鹭",
    "Gray-headed Parrotbill": "灰头鸦雀",
    "Himalayan Buzzard": "喜山鵟",
    "Indian Peafowl": "蓝孔雀",
    "Little Heron": "绿鹭",
    "Muscovy Duck": "番鸭",
    "Oriental Cuckooshrike": "东方鹃鵙",
    "Pale-billed Parrotbill": "淡嘴鸦雀",
    "Red-billed Scimitar-Babbler": "红嘴钩嘴鹛",
    "Rusty-capped Fulvetta": "褐胁雀鹛",
    "Spot-bellied Eagle-Owl": "林雕鸮",
    "Streak-breasted Scimitar-Babbler": "纹胸钩嘴鹛",
    "Thick-billed Flowerpecker": "厚嘴啄花鸟",
    "White-browed Scimitar-Babbler": "白眉钩嘴鹛",
    "Yellow-bellied Fairy-Fantail": "黄腹扇尾鹟",
    "Yellow-bellied Flowerpecker": "黄腹啄花鸟",
    "Yellow-bellied Tit": "黄腹山雀",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Merge eBird hotspot HTML exports and write a deduped CSV."
    )
    parser.add_argument(
        "--input",
        action="append",
        nargs=2,
        metavar=("HTML_PATH", "PLACE"),
        required=True,
        help="Input HTML file path and its place label. Repeat for multiple files.",
    )
    parser.add_argument("--output", required=True, help="Output CSV path.")
    parser.add_argument(
        "--china-birds-json",
        help="Optional china_birds.json path used to fill Chinese names.",
    )
    return parser.parse_args()


def is_species_level_name(scientific_name: str) -> bool:
    sci = scientific_name.strip()
    sci_lower = sci.lower()
    if not sci:
        return False
    if "sp." in sci_lower or "(" in sci or "/" in sci or "×" in sci or " x " in sci_lower:
        return False
    parts = sci.split()
    return len(parts) == 2 and all(parts)


def extract_species(html_path: Path, place: str) -> list[tuple[str, str, str]]:
    soup = BeautifulSoup(html_path.read_text(encoding="utf-8"), "html.parser")
    entries: list[tuple[str, str, str]] = []
    for node in soup.select("div.subitem"):
        sci_node = node.select_one("em.sci")
        scientific_name = sci_node.get_text(" ", strip=True) if sci_node else ""
        if not is_species_level_name(scientific_name):
            continue
        raw_text = node.get_text(" ", strip=True)
        english_name = raw_text.replace(scientific_name, "").strip(" -\u00a0")
        if not english_name:
            continue
        entries.append((english_name, scientific_name, place))
    return entries


def main() -> None:
    args = parse_args()
    merged: dict[str, dict[str, object]] = {}
    chinese_names_by_sci: dict[str, str] = {}
    chinese_names_by_english: dict[str, str] = {}

    if args.china_birds_json:
        china_birds = json.loads(Path(args.china_birds_json).read_text(encoding="utf-8"))
        chinese_names_by_sci = {
            (item.get("sci") or "").strip().lower(): (item.get("zh") or "").strip()
            for item in china_birds
            if (item.get("sci") or "").strip()
        }
        chinese_names_by_english = {
            (item.get("en") or "").strip().lower(): (item.get("zh") or "").strip()
            for item in china_birds
            if (item.get("en") or "").strip()
        }

    for html_path_str, place in args.input:
        html_path = Path(html_path_str)
        for english_name, scientific_name, found_place in extract_species(html_path, place):
            key = scientific_name.lower()
            current = merged.setdefault(
                key,
                {
                    "english_name": english_name,
                    "scientific_name": scientific_name,
                    "places": [],
                },
            )
            places = current["places"]
            if found_place not in places:
                places.append(found_place)

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["中文名", "English name", "Scientific name", "发现地点"])
        for item in sorted(merged.values(), key=lambda row: str(row["english_name"]).lower()):
            scientific_name = str(item["scientific_name"])
            english_name = str(item["english_name"])
            writer.writerow(
                [
                    chinese_names_by_sci.get(scientific_name.lower(), "")
                    or chinese_names_by_english.get(english_name.lower(), "")
                    or MANUAL_CHINESE_ALIASES_BY_ENGLISH.get(english_name, ""),
                    english_name,
                    scientific_name,
                    "、".join(item["places"]),
                ]
            )

    print(f"Wrote {len(merged)} species to {output_path}")


if __name__ == "__main__":
    main()
