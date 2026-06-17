#!/usr/bin/env python3
"""Backfill location (place name + coords + observed date) onto iNaturalist
image entries that lack it, by batch-querying the source observations.

Each backfilled photo's observation id is recoverable from its filename
(`*_inat_<obs>_<photo>.jpg`) or its `contributor_url`. iNat lets us fetch up to
200 observations per request (`?id=a,b,c...`), so ~10k photos cost only ~50
calls. Idempotent; skips entries that already have a location.

IMPORTANT: run this when the photo backfill is NOT running, to avoid two
processes writing the same manifest.json concurrently.
"""
from __future__ import annotations

import glob
import json
import re
import socket
import time
import urllib.parse
import urllib.request
from pathlib import Path

INAT = "https://api.inaturalist.org/v1/observations"
UA = {"User-Agent": "BirdaholicMediaBackfill/1.0"}
SPECIES_GLOB = "/data/species/*/manifest.json"
BATCH = 200
socket.setdefaulttimeout(40)


def obs_id_of(entry: dict) -> str:
    m = re.search(r"_inat_(\d+)_\d+", str(entry.get("file") or ""))
    if m:
        return m.group(1)
    m = re.search(r"/observations/(\d+)", str(entry.get("contributor_url") or ""))
    return m.group(1) if m else ""


def fetch_batch(ids: list[str]) -> list[dict] | None:
    q = urllib.parse.urlencode({"id": ",".join(ids), "per_page": str(len(ids))})
    for _ in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(f"{INAT}?{q}", headers=UA)) as r:
                return json.loads(r.read().decode()).get("results", [])
        except Exception:
            time.sleep(3)
    return None


def main() -> None:
    need: dict[str, list[tuple[str, dict]]] = {}
    manifests: dict[str, dict] = {}
    for mp in glob.glob(SPECIES_GLOB):
        try:
            m = json.loads(Path(mp).read_text(encoding="utf-8"))
        except Exception:
            continue
        manifests[mp] = m
        for e in m.get("images", []):
            if not isinstance(e, dict):
                continue
            if str(e.get("source") or "").strip().lower() != "inaturalist":
                continue
            if e.get("location") or e.get("coords"):
                continue
            oid = obs_id_of(e)
            if oid:
                need.setdefault(oid, []).append((mp, e))

    ids = list(need.keys())
    total_entries = sum(len(v) for v in need.values())
    print(f"need location: {total_entries} entries across {len(ids)} observations")

    dirty: set[str] = set()
    filled = 0
    for i in range(0, len(ids), BATCH):
        batch = ids[i : i + BATCH]
        res = fetch_batch(batch)
        if res is None:
            print(f"  batch {i}-{i+len(batch)} failed (network); will retry on next run")
            continue
        for o in res:
            oid = str(o.get("id"))
            place = str(o.get("place_guess") or "").strip()
            coords = str(o.get("location") or "").strip()
            observed = str(o.get("observed_on") or "").strip()
            for mp, e in need.get(oid, []):
                if place:
                    e["location"] = place
                if coords:
                    e["coords"] = coords
                if observed:
                    e["observed_on"] = observed
                if place or coords or observed:
                    dirty.add(mp)
                    filled += 1
        print(f"  {min(i+BATCH, len(ids))}/{len(ids)} observations processed", flush=True)
        time.sleep(0.5)

    for mp in dirty:
        Path(mp).write_text(
            json.dumps(manifests[mp], ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    print(f"Done. filled={filled} entries, manifests updated={len(dirty)}")


if __name__ == "__main__":
    main()
