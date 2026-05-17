#!/usr/bin/env python3
"""Build the bundled China common 100 bird pack from the full China pack."""

from __future__ import annotations

import json
import zipfile
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCE_ZIP = ROOT / "data_packs" / "china_birds_v1.0_opt.zip"
OUTPUT_ZIP = ROOT / "data_packs" / "china_common_100_v1.0_opt.zip"
OUTPUT_LIST = ROOT / "assets" / "data" / "china_common_100.json"
CHINA_CHECKLIST = ROOT / "assets" / "data" / "china_birds_zheng.json"
WORLD_CHECKLIST = ROOT / "assets" / "data" / "world_birds.json"

EBIRD_CODE_OVERRIDES = {
    "Cecropis daurica": "y00621",
    "Saxicola stejnegeri": "stonec7",
}

DESCRIPTION_SOURCE = "Birdaholic 根据中国鸟类名录与 Wikidata CC0 名称数据生成"

COMMON_100 = [
    "Passer montanus",
    "Spilopelia chinensis",
    "Motacilla alba",
    "Nycticorax nycticorax",
    "Hirundo rustica",
    "Ardeola bacchus",
    "Tachybaptus ruficollis",
    "Gallinula chloropus",
    "Pica serica",
    "Egretta garzetta",
    "Anas platyrhynchos",
    "Ardea cinerea",
    "Pycnonotus sinensis",
    "Alcedo atthis",
    "Chloris sinica",
    "Anas zonorhyncha",
    "Spodiopsar cineraceus",
    "Phylloscopus inornatus",
    "Cuculus canorus",
    "Upupa epops",
    "Phylloscopus fuscatus",
    "Himantopus himantopus",
    "Acrocephalus orientalis",
    "Cyanopica cyanus",
    "Streptopelia orientalis",
    "Turdus mandarinus",
    "Anthus hodgsoni",
    "Lanius cristatus",
    "Fulica atra",
    "Dicrurus macrocercus",
    "Actitis hypoleucos",
    "Muscicapa dauurica",
    "Ficedula albicilla",
    "Columba livia",
    "Ardea alba",
    "Phasianus colchicus",
    "Phylloscopus proregulus",
    "Motacilla cinerea",
    "Emberiza pusilla",
    "Podiceps cristatus",
    "Acridotheres cristatellus",
    "Vanellus cinereus",
    "Phoenicurus auroreus",
    "Falco tinnunculus",
    "Tringa glareola",
    "Cecropis daurica",
    "Zosterops simplex",
    "Lanius schach",
    "Phylloscopus borealis",
    "Spodiopsar sericeus",
    "Cuculus micropterus",
    "Eophona migratoria",
    "Urocissa erythroryncha",
    "Oriolus chinensis",
    "Tringa ochropus",
    "Dendrocopos major",
    "Ficedula zanthopygia",
    "Hierococcyx sparverioides",
    "Acrocephalus bistrigiceps",
    "Motacilla tschutschensis",
    "Gallinago gallinago",
    "Eudynamys scolopaceus",
    "Chlidonias hybrida",
    "Sterna hirundo",
    "Emberiza spodocephala",
    "Motacilla citreola",
    "Aegithalos concinnus",
    "Copsychus saularis",
    "Picus canus",
    "Tringa nebularia",
    "Prinia inornata",
    "Saxicola stejnegeri",
    "Dicrurus hottentottus",
    "Chroicocephalus ridibundus",
    "Spatula querquedula",
    "Aegithalos glaucogularis",
    "Ardea intermedia",
    "Cisticola juncidis",
    "Otus sunia",
    "Muscicapa sibirica",
    "Falco peregrinus",
    "Larvivora cyane",
    "Calliope calliope",
    "Phalacrocorax carbo",
    "Tringa totanus",
    "Streptopelia decaocto",
    "Lonchura punctulata",
    "Tringa erythropus",
    "Anas crecca",
    "Turdus obscurus",
    "Anthus richardi",
    "Dicrurus leucophaeus",
    "Phylloscopus coronatus",
    "Phylloscopus tenellipes",
    "Riparia riparia",
    "Apus nipalensis",
    "Lonchura striata",
    "Gracupica nigricollis",
    "Calidris temminckii",
    "Hypsipetes leucocephalus",
]


def media_refs(item: dict) -> set[str]:
    refs: set[str] = set()
    image = (item.get("image") or "").strip()
    if image:
        refs.add(image)
    for image_item in item.get("images") or []:
        if isinstance(image_item, str):
            refs.add(image_item)
        elif isinstance(image_item, dict) and image_item.get("file"):
            refs.add(str(image_item["file"]))
    for audio in item.get("audios") or []:
        if isinstance(audio, dict) and audio.get("file"):
            refs.add(str(audio["file"]))
    return refs


def load_checklist_meta() -> dict[str, dict]:
    merged: dict[str, dict] = {}
    for path in (WORLD_CHECKLIST, CHINA_CHECKLIST):
        if not path.exists():
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        for item in data:
            sci = item.get("sci", "").strip().lower()
            if not sci:
                continue
            base = merged.setdefault(sci, {})
            base.update({k: v for k, v in item.items() if v})
    return merged


def enrich_species(item: dict, checklist_meta: dict[str, dict]) -> dict:
    enriched = dict(item)
    meta = checklist_meta.get(enriched.get("sci", "").strip().lower())
    if meta:
        if meta.get("en"):
            enriched["en"] = meta["en"]
        if meta.get("code"):
            enriched["code"] = meta["code"]
    code_override = EBIRD_CODE_OVERRIDES.get(enriched.get("sci", ""))
    if code_override:
        enriched["code"] = code_override
    parts = []
    if enriched.get("family") or enriched.get("order"):
        parts.append(
            f"隶属{enriched.get('order', '')}{enriched.get('family', '')}"
        )
    if enriched.get("en"):
        parts.append(f"英文名 {enriched['en']}")
    if enriched.get("code"):
        parts.append(f"eBird 编码 {enriched['code']}")
    if parts:
        enriched["description"] = (
            f"{enriched.get('cn', enriched.get('sci', ''))}（{enriched.get('sci', '')}）"
            + "，"
            + "，".join(parts)
            + "。"
        )
        enriched["description_source"] = DESCRIPTION_SOURCE
    return enriched


def main() -> None:
    if not SOURCE_ZIP.exists():
        raise SystemExit(f"Missing source pack: {SOURCE_ZIP}")
    checklist_meta = load_checklist_meta()
    with zipfile.ZipFile(SOURCE_ZIP) as source:
        species = json.loads(source.read("species.json").decode("utf-8"))
        by_sci = {item["sci"].strip().lower(): item for item in species}
        selected = []
        missing = []
        for sci in COMMON_100:
            item = by_sci.get(sci.lower())
            if item is None:
                missing.append(sci)
            else:
                selected.append(enrich_species(item, checklist_meta))
        if missing:
            raise SystemExit("Missing species in source pack:\n" + "\n".join(missing))

        refs = {"species.json", "manifest.json"}
        for item in selected:
            refs.update(media_refs(item))

        manifest = {
            "name": "中国常见鸟 100",
            "region": "中国",
            "version": "1.0",
            "created": date.today().isoformat(),
            "species_count": len(selected),
            "audio_count": sum(len(item.get("audios") or []) for item in selected),
            "image_count": sum(1 for item in selected if item.get("image") or item.get("images")),
            "source": "eBird China geo-recent sample ranked subset from Birdaholic China pack",
            "short_name": "中国常见鸟 100",
        }

        OUTPUT_LIST.write_text(
            json.dumps(
                [
                    {
                        "cn": item.get("cn", ""),
                        "en": item.get("en", ""),
                        "sci": item.get("sci", ""),
                        "order": item.get("order", ""),
                        "family": item.get("family", ""),
                        "code": item.get("code", ""),
                        "description": item.get("description", ""),
                        "description_source": item.get("description_source", ""),
                    }
                    for item in selected
                ],
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )

        OUTPUT_ZIP.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(OUTPUT_ZIP, "w", compression=zipfile.ZIP_DEFLATED) as out:
            out.writestr("species.json", json.dumps(selected, ensure_ascii=False, indent=2))
            out.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
            for name in sorted(refs - {"species.json", "manifest.json"}):
                try:
                    out.writestr(name, source.read(name))
                except KeyError:
                    pass
    print(f"Wrote {OUTPUT_ZIP}")
    print(f"Wrote {OUTPUT_LIST}")


if __name__ == "__main__":
    main()
