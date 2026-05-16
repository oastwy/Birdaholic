#!/usr/bin/env python3
"""Build the bundled China common 100 bird pack from the full China pack."""

from __future__ import annotations

import json
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCE_ZIP = ROOT / "data_packs" / "china_birds_v1.0_opt.zip"
OUTPUT_ZIP = ROOT / "data_packs" / "china_common_100_v1.0_opt.zip"
OUTPUT_LIST = ROOT / "assets" / "data" / "china_common_100.json"

COMMON_100 = [
    "Passer montanus",
    "Pycnonotus sinensis",
    "Acridotheres cristatellus",
    "Spilopelia chinensis",
    "Streptopelia orientalis",
    "Columba livia",
    "Pica serica",
    "Cyanopica cyanus",
    "Corvus macrorhynchos",
    "Cuculus canorus",
    "Centropus sinensis",
    "Hirundo rustica",
    "Cecropis daurica",
    "Motacilla alba",
    "Motacilla cinerea",
    "Anthus richardi",
    "Hypsipetes leucocephalus",
    "Zosterops simplex",
    "Parus minor",
    "Sinosuthora webbiana",
    "Garrulax canorus",
    "Erythrogenys ruficollis",
    "Turdus mandarinus",
    "Turdus merula",
    "Phoenicurus auroreus",
    "Copsychus saularis",
    "Saxicola maurus",
    "Muscicapa dauurica",
    "Ficedula zanthopygia",
    "Phylloscopus inornatus",
    "Acrocephalus orientalis",
    "Orthotomus sutorius",
    "Cisticola juncidis",
    "Prinia inornata",
    "Lanius schach",
    "Dicrurus macrocercus",
    "Oriolus chinensis",
    "Sturnia sinensis",
    "Acridotheres tristis",
    "Lonchura punctulata",
    "Chloris sinica",
    "Spinus spinus",
    "Emberiza elegans",
    "Emberiza cioides",
    "Egretta garzetta",
    "Ardea cinerea",
    "Ardea alba",
    "Bubulcus coromandus",
    "Nycticorax nycticorax",
    "Ardeola bacchus",
    "Ixobrychus sinensis",
    "Phalacrocorax carbo",
    "Anas zonorhyncha",
    "Anas crecca",
    "Anas platyrhynchos",
    "Tachybaptus ruficollis",
    "Podiceps cristatus",
    "Amaurornis phoenicurus",
    "Gallinula chloropus",
    "Fulica atra",
    "Vanellus vanellus",
    "Charadrius dubius",
    "Actitis hypoleucos",
    "Tringa nebularia",
    "Gallinago gallinago",
    "Chroicocephalus ridibundus",
    "Larus vegae",
    "Sterna hirundo",
    "Milvus migrans",
    "Accipiter nisus",
    "Buteo japonicus",
    "Falco tinnunculus",
    "Falco peregrinus",
    "Tyto javanica",
    "Otus sunia",
    "Athene noctua",
    "Alcedo atthis",
    "Halcyon smyrnensis",
    "Merops orientalis",
    "Upupa epops",
    "Psilopogon nuchalis",
    "Dendrocopos major",
    "Picus canus",
    "Bambusicola thoracicus",
    "Coturnix japonica",
    "Phasianus colchicus",
    "Chrysolophus pictus",
    "Dendrocitta formosae",
    "Garrulus glandarius",
    "Pericrocotus solaris",
    "Pericrocotus ethologus",
    "Aegithalos concinnus",
    "Cyanistes cyanus",
    "Alauda gulgula",
    "Mirafra javanica",
    "Pycnonotus aurigaster",
    "Pycnonotus jocosus",
    "Hemixos castanonotus",
    "Leiothrix lutea",
    "Parayuhina diademata",
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


def main() -> None:
    if not SOURCE_ZIP.exists():
        raise SystemExit(f"Missing source pack: {SOURCE_ZIP}")
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
                selected.append(item)
        if missing:
            raise SystemExit("Missing species in source pack:\n" + "\n".join(missing))

        refs = {"species.json", "manifest.json"}
        for item in selected:
            refs.update(media_refs(item))

        manifest = {
            "name": "中国常见鸟 100",
            "region": "中国",
            "version": "1.0",
            "created": "2026-05-16",
            "species_count": len(selected),
            "audio_count": sum(len(item.get("audios") or []) for item in selected),
            "image_count": sum(1 for item in selected if item.get("image") or item.get("images")),
            "source": "Birdaholic China common 100 subset",
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
