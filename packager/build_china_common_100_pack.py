#!/usr/bin/env python3
"""Build the bundled China common 100 bird pack.

The bundled pack is based on the fixed common-100 list and the local China
checklist. Media is refreshed from the Birdaholic server so new user/admin
uploads can replace older iNaturalist cover images. The full China ZIP is not
required; missing server media simply leaves that species without that media
type in the bundled pack.
"""

from __future__ import annotations

import json
import re
import zipfile
from datetime import date
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urlparse
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent.parent
OUTPUT_ZIP = ROOT / "data_packs" / "china_common_100_v1.2_opt.zip"
OUTPUT_LIST = ROOT / "assets" / "data" / "china_common_100.json"
CHINA_CHECKLIST = ROOT / "assets" / "data" / "china_birds_zheng.json"
WORLD_CHECKLIST = ROOT / "assets" / "data" / "world_birds.json"
SERVER_BASE = "https://birding.today"
SERVER_IP_BASE = "http://your-server-ip:8080"
MAX_IMAGES_PER_SPECIES = 3
REQUEST_TIMEOUT = 20
EMBED_SPECTROGRAM_FILES = True

USER_UPLOAD_SOURCES = {
    "birdaholic-upload",
    "birdaholic",
    "user-upload",
    "user",
    "local",
    "用户上传",
    "管理员上传",
}

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


def species_dir(sci: str) -> str:
    return re.sub(r"[^A-Za-z0-9_]+", "_", sci.strip().replace(" ", "_")).strip("_")


def safe_filename(name: str, fallback: str) -> str:
    name = unquote(name).split("?")[0].split("#")[0].strip()
    name = Path(name).name
    if not name:
        name = fallback
    name = re.sub(r"[^A-Za-z0-9._-]+", "_", name)
    return name or fallback


def basename_from_url(url: str, fallback: str) -> str:
    if not url:
        return fallback
    parsed = urlparse(url)
    return safe_filename(parsed.path, fallback)


def fetch_json(url: str) -> dict | None:
    request = Request(url, headers={"User-Agent": "Birdaholic-packager/1.0"})
    try:
        with urlopen(request, timeout=REQUEST_TIMEOUT) as response:
            if response.status != 200:
                return None
            return json.loads(response.read().decode("utf-8"))
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError):
        return None


def fetch_bytes(url: str) -> bytes | None:
    if not url:
        return None
    request = Request(url, headers={"User-Agent": "Birdaholic-packager/1.0"})
    try:
        with urlopen(request, timeout=REQUEST_TIMEOUT) as response:
            if response.status != 200:
                return None
            return response.read()
    except (HTTPError, URLError, TimeoutError):
        return None


def load_server_manifest(sci: str) -> dict | None:
    path = f"/species/{species_dir(sci)}/manifest.json"
    return fetch_json(f"{SERVER_BASE}{path}") or fetch_json(f"{SERVER_IP_BASE}{path}")


def is_user_upload_media(item: dict) -> bool:
    source = str(item.get("source") or "").strip().lower()
    contributor_url = str(item.get("contributor_url") or "").strip().lower()
    if source in {s.lower() for s in USER_UPLOAD_SOURCES}:
        return True
    if "upload" in source or "用户" in source or "管理员" in source:
        return True
    return "birding.today" in contributor_url and "inaturalist" not in contributor_url


def media_identity(item: dict) -> str:
    for key in ("contributor_url", "url", "file"):
        value = str(item.get(key) or "").strip()
        if value:
            return value
    return json.dumps(item, ensure_ascii=False, sort_keys=True)


def media_sort_key(indexed_item: tuple[int, dict]) -> tuple[int, int]:
    index, item = indexed_item
    source = str(item.get("source") or "").strip().lower()
    if is_user_upload_media(item):
        bucket = 0
    elif source == "inaturalist":
        bucket = 2
    else:
        bucket = 1
    return (bucket, index)


def selected_server_images(manifest: dict | None) -> list[dict]:
    if not manifest:
        return []
    raw_images = [item for item in manifest.get("images") or [] if isinstance(item, dict)]
    seen: set[str] = set()
    images: list[dict] = []
    for _, item in sorted(enumerate(raw_images), key=media_sort_key):
        identity = media_identity(item)
        if identity in seen:
            continue
        seen.add(identity)
        images.append(dict(item))
        if len(images) >= MAX_IMAGES_PER_SPECIES:
            break
    for index, item in enumerate(images):
        raw_difficulty = item.get("difficulty") or item.get("suggested_difficulty")
        if raw_difficulty is None:
            item["difficulty"] = 1
        else:
            try:
                item["difficulty"] = max(1, min(5, int(raw_difficulty)))
            except (TypeError, ValueError):
                item["difficulty"] = 1
    return images


def add_remote_media(
    out: zipfile.ZipFile,
    *,
    url: str,
    folder: str,
    sci: str,
    fallback_name: str,
    written: set[str],
) -> str | None:
    data = fetch_bytes(url)
    if data is None:
        return None
    base = basename_from_url(url, fallback_name)
    local = f"{folder}/{species_dir(sci)}_{base}"
    counter = 2
    while local in written:
        stem = Path(base).stem
        suffix = Path(base).suffix
        local = f"{folder}/{species_dir(sci)}_{stem}_{counter}{suffix}"
        counter += 1
    out.writestr(local, data)
    written.add(local)
    return local


def add_source_media(
    source: zipfile.ZipFile | None,
    out: zipfile.ZipFile,
    source_path: str,
    written: set[str],
) -> str | None:
    if source is None:
        return None
    if not source_path or source_path in written:
        return source_path if source_path in written else None
    try:
        out.writestr(source_path, source.read(source_path))
    except KeyError:
        return None
    written.add(source_path)
    return source_path


def build_image_entries(
    source: zipfile.ZipFile | None,
    out: zipfile.ZipFile,
    sci: str,
    base_item: dict,
    server_manifest: dict | None,
    written: set[str],
) -> list[dict]:
    entries: list[dict] = []
    for item in selected_server_images(server_manifest):
        url = str(item.get("url") or "").strip()
        local = add_remote_media(
            out,
            url=url,
            folder="images",
            sci=sci,
            fallback_name=f"{species_dir(sci)}.jpg",
            written=written,
        )
        if not local:
            continue
        contributor = str(item.get("contributor") or "").strip()
        source_name = str(item.get("source") or "").strip()
        entry = {
            "file": local,
            "difficulty": int(item.get("difficulty") or 1),
        }
        for key in ("contributor", "contributor_url", "source", "license"):
            value = str(item.get(key) or "").strip()
            if value:
                entry[key] = value
        entry["credit"] = contributor or source_name
        entries.append(entry)

    if entries:
        return entries

    fallback_paths = []
    if base_item.get("image"):
        fallback_paths.append(str(base_item["image"]))
    for image_item in base_item.get("images") or []:
        if isinstance(image_item, str):
            fallback_paths.append(image_item)
        elif isinstance(image_item, dict) and image_item.get("file"):
            fallback_paths.append(str(image_item["file"]))
    seen_paths: set[str] = set()
    for path in fallback_paths:
        if path in seen_paths:
            continue
        seen_paths.add(path)
        local = add_source_media(source, out, path, written)
        if not local:
            continue
        entries.append(
            {
                "file": local,
                "difficulty": 1,
                "source": str(base_item.get("image_source") or "inaturalist"),
                "credit": str(base_item.get("image_credit") or base_item.get("image_source") or ""),
            }
        )
        if len(entries) >= MAX_IMAGES_PER_SPECIES:
            break
    return entries


def build_audio_entries(
    source: zipfile.ZipFile | None,
    out: zipfile.ZipFile,
    sci: str,
    base_item: dict,
    server_manifest: dict | None,
    written: set[str],
) -> list[dict]:
    entries: list[dict] = []
    raw_audio = []
    if server_manifest:
        raw_audio = [item for item in server_manifest.get("audio") or [] if isinstance(item, dict)]
    for item in raw_audio:
        url = str(item.get("url") or "").strip()
        local = add_remote_media(
            out,
            url=url,
            folder="sounds",
            sci=sci,
            fallback_name=f"{species_dir(sci)}_{item.get('type') or 'call'}.m4a",
            written=written,
        )
        if not local:
            continue
        entry = {
            "type": str(item.get("type") or "call"),
            "file": local,
        }
        for key in ("contributor", "contributor_url", "license"):
            value = str(item.get(key) or "").strip()
            if value:
                entry[key] = value
        spectrogram_url = str(item.get("spectrogram_url") or "").strip()
        if EMBED_SPECTROGRAM_FILES and spectrogram_url:
            spectrogram_local = add_remote_media(
                out,
                url=spectrogram_url,
                folder="spectrograms",
                sci=sci,
                fallback_name=f"{Path(local).stem}.png",
                written=written,
            )
            if spectrogram_local:
                entry["spectrogram"] = spectrogram_local
        if spectrogram_url:
            entry["spectrogram_url"] = spectrogram_url
        entries.append(entry)

    if entries:
        return entries

    for item in base_item.get("audios") or []:
        if not isinstance(item, dict) or not item.get("file"):
            continue
        local = add_source_media(source, out, str(item["file"]), written)
        if not local:
            continue
        entry = dict(item)
        entry["file"] = local
        entries.append(entry)
    return entries


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
    if not enriched.get("cn") and enriched.get("zh"):
        enriched["cn"] = enriched["zh"]
    if not enriched.get("cons") and enriched.get("protection"):
        enriched["cons"] = enriched["protection"]
    meta = checklist_meta.get(enriched.get("sci", "").strip().lower())
    if meta:
        if meta.get("zh") and not enriched.get("cn"):
            enriched["cn"] = meta["zh"]
        if meta.get("en"):
            enriched["en"] = meta["en"]
        if meta.get("code"):
            enriched["code"] = meta["code"]
        if meta.get("family") and not enriched.get("family"):
            enriched["family"] = meta["family"]
        if meta.get("order") and not enriched.get("order"):
            enriched["order"] = meta["order"]
        if meta.get("protection") and not enriched.get("cons"):
            enriched["cons"] = meta["protection"]
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
    checklist_meta = load_checklist_meta()
    selected_base = []
    missing = []
    for sci in COMMON_100:
        meta = checklist_meta.get(sci.lower())
        if meta is None:
            missing.append(sci)
            continue
        selected_base.append(enrich_species({"sci": sci, **meta}, checklist_meta))
    if missing:
        raise SystemExit("Missing species in checklist:\n" + "\n".join(missing))

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
                for item in selected_base
            ],
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    source = None
    OUTPUT_ZIP.parent.mkdir(parents=True, exist_ok=True)
    selected: list[dict] = []
    written: set[str] = set()
    server_media_count = 0
    user_upload_species = 0
    fallback_species = 0
    with zipfile.ZipFile(OUTPUT_ZIP, "w", compression=zipfile.ZIP_DEFLATED) as out:
        for index, base_item in enumerate(selected_base, start=1):
            sci = str(base_item.get("sci") or "").strip()
            print(f"[{index:03d}/{len(selected_base)}] {sci}")
            server_manifest = load_server_manifest(sci)
            item = enrich_species(base_item, checklist_meta)
            if server_manifest:
                for key in ("cons", "habitat"):
                    if server_manifest.get(key):
                        item[key] = server_manifest[key]

            images = build_image_entries(
                source, out, sci, item, server_manifest, written
            )
            audios = build_audio_entries(
                source, out, sci, item, server_manifest, written
            )
            if server_manifest:
                server_media_count += len(images) + len(audios)
            else:
                fallback_species += 1
            if any(is_user_upload_media(image) for image in (server_manifest or {}).get("images") or []):
                user_upload_species += 1

            item["images"] = images
            if images:
                first = images[0]
                item["image"] = first["file"]
                if first.get("credit"):
                    item["image_credit"] = first["credit"]
                if first.get("source"):
                    item["image_source"] = first["source"]
                if first.get("license"):
                    item["image_license"] = first["license"]
            else:
                item.pop("image", None)
            item["audios"] = audios
            item.pop("audio", None)
            selected.append(item)

        manifest = {
            "name": "中国常见鸟 100",
            "region": "中国",
            "version": "1.2",
            "created": date.today().isoformat(),
            "species_count": len(selected),
            "audio_count": sum(len(item.get("audios") or []) for item in selected),
            "image_count": sum(len(item.get("images") or []) for item in selected),
            "source": "Birdaholic server manifests refreshed from user uploads first",
            "short_name": "中国常见鸟 100",
            "server_refreshed": True,
            "max_images_per_species": MAX_IMAGES_PER_SPECIES,
            "spectrogram_embedded": EMBED_SPECTROGRAM_FILES,
        }
        out.writestr("species.json", json.dumps(selected, ensure_ascii=False, indent=2))
        out.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
    print(f"Wrote {OUTPUT_ZIP}")
    print(f"Wrote {OUTPUT_LIST}")
    print(f"Server media entries used: {server_media_count}")
    print(f"Species with user-upload images on server: {user_upload_species}")
    print(f"Species using fallback only: {fallback_species}")


if __name__ == "__main__":
    main()
