#!/usr/bin/env python3
"""Generate per-region (country -> subnational1 "省/州") bird checklists from
eBird, joined with world_birds.json, for Birdaholic's worldwide checklist
feature ("像懂鸟一样，精确到省").

Output (under /data/checklists/):
  {regionCode}.json     一个地区一份名录：{code,name,name_zh,country,count,missing,species:[{code,sci,en,zh}]}
  _index.json           国家→省 目录树：{generated, countries:[{code,name,name_zh,province_count,provinces:[{code,name,name_zh,count}]}]}

地区中文名：优先查 region_names_zh.json（国家 ISO2 + 中国省 CN-XX），查不到用 eBird 英文名兜底。
物种中文名：来自 world_birds.json（按 eBird code 关联）。

用法：
  python3 gen_checklists.py --key <EBIRD_KEY>                # 全量 subnational1
  python3 gen_checklists.py --key <K> --country US           # 只跑某国（验证用）
  python3 gen_checklists.py --key <K> --limit 3              # 只跑前 3 个国家
  python3 gen_checklists.py --key <K> --delay 0.6            # 调限速
  python3 gen_checklists.py --key <K> --overwrite            # 强制重抓
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

EBIRD = "https://api.ebird.org/v2"
OUT_DIR = Path("/data/checklists")
WORLD_BIRDS = Path("/data/server/world_birds.json")
REGION_ZH = Path("/data/server/region_names_zh.json")


def ebird_get(path: str, key: str, retries: int = 3):
    url = EBIRD + path
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"X-eBirdApiToken": key})
            with urllib.request.urlopen(req, timeout=40) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            last = e
            if e.code in (404, 400):
                return None  # 该地区无数据
            time.sleep(2 * (attempt + 1))
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(2 * (attempt + 1))
    print(f"  ! 放弃 {path}: {last}", file=sys.stderr)
    return None


def load_world_birds() -> dict:
    data = json.loads(WORLD_BIRDS.read_text(encoding="utf-8"))
    by_code = {}
    for it in data:
        code = (it.get("code") or "").strip()
        if code:
            by_code[code] = it
    return by_code


def load_region_zh() -> dict:
    if REGION_ZH.exists():
        try:
            return json.loads(REGION_ZH.read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001
            return {}
    return {}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--key", required=True, help="eBird API key")
    ap.add_argument("--delay", type=float, default=0.6, help="每次调用间隔秒")
    ap.add_argument("--country", default="", help="只跑某国（ISO2，如 US）")
    ap.add_argument("--limit", type=int, default=0, help="只跑前 N 个国家（0=全部）")
    ap.add_argument("--overwrite", action="store_true", help="强制重抓已存在的地区")
    args = ap.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    by_code = load_world_birds()
    region_zh = load_region_zh()
    print(f"world_birds: {len(by_code)} 种；region_zh: {len(region_zh)} 条")

    # 1) 国家列表
    countries = ebird_get("/ref/region/list/country/world", args.key) or []
    if args.country:
        countries = [c for c in countries if c.get("code") == args.country]
    if args.limit > 0:
        countries = countries[: args.limit]
    print(f"待处理国家：{len(countries)}")

    index_countries = []
    total_regions = 0
    for ci, country in enumerate(countries):
        ccode = country.get("code", "")
        cname = country.get("name", "")
        cname_zh = region_zh.get(ccode, cname)
        subs = ebird_get(f"/ref/region/list/subnational1/{ccode}", args.key) or []
        # 有的小国没有 subnational1，则把国家本身当作一个"地区"
        regions = subs if subs else [{"code": ccode, "name": cname}]
        prov_entries = []
        for region in regions:
            rcode = region.get("code", "")
            rname = region.get("name", "")
            rname_zh = region_zh.get(rcode, rname)
            out_path = OUT_DIR / f"{rcode}.json"
            if out_path.exists() and not args.overwrite:
                try:
                    cached = json.loads(out_path.read_text(encoding="utf-8"))
                    prov_entries.append({
                        "code": rcode, "name": rname, "name_zh": rname_zh,
                        "count": cached.get("count", 0),
                    })
                    total_regions += 1
                    continue
                except Exception:  # noqa: BLE001
                    pass
            codes = ebird_get(f"/product/spplist/{rcode}", args.key) or []
            time.sleep(args.delay)
            species = []
            missing = 0
            for code in codes:
                hit = by_code.get(code)
                if hit:
                    species.append({
                        "code": code,
                        "sci": hit.get("sci", ""),
                        "en": hit.get("en", ""),
                        "zh": hit.get("zh", ""),
                    })
                else:
                    missing += 1
            payload = {
                "code": rcode, "name": rname, "name_zh": rname_zh,
                "country": ccode, "count": len(species), "missing": missing,
                "species": species,
            }
            out_path.write_text(
                json.dumps(payload, ensure_ascii=False), encoding="utf-8"
            )
            prov_entries.append({
                "code": rcode, "name": rname, "name_zh": rname_zh,
                "count": len(species),
            })
            total_regions += 1
            print(f"  [{ci+1}/{len(countries)}] {ccode} {rcode} {rname_zh}: "
                  f"{len(species)} 种 (missing {missing})")
        index_countries.append({
            "code": ccode, "name": cname, "name_zh": cname_zh,
            "province_count": len(prov_entries),
            "provinces": sorted(prov_entries, key=lambda x: x["name"]),
        })

    index = {
        "generated": int(time.time()),
        "country_count": len(index_countries),
        "region_count": total_regions,
        "countries": sorted(index_countries, key=lambda x: x["name"]),
    }
    (OUT_DIR / "_index.json").write_text(
        json.dumps(index, ensure_ascii=False), encoding="utf-8"
    )
    print(f"完成：{len(index_countries)} 国 / {total_regions} 地区 → {OUT_DIR}/_index.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
