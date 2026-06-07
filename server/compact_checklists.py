#!/usr/bin/env python3
"""把已生成的"胖"地区名录（species:[{code,sci,en,zh}]）就地转成"瘦"格式
（codes:[eBird code]）。客户端用内置 world_birds.json 还原名字。不调 eBird。

用法：python3 compact_checklists.py
"""
import json
from pathlib import Path

OUT_DIR = Path("/data/checklists")


def main() -> None:
    files = [p for p in OUT_DIR.glob("*.json") if p.name != "_index.json"]
    converted = 0
    skipped = 0
    for p in files:
        try:
            d = json.loads(p.read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001
            continue
        if "codes" in d and "species" not in d:
            skipped += 1
            continue
        species = d.get("species", [])
        codes = [s.get("code", "") for s in species if s.get("code")]
        new = {
            "code": d.get("code", p.stem),
            "name": d.get("name", ""),
            "name_zh": d.get("name_zh", d.get("name", "")),
            "country": d.get("country", ""),
            "count": len(codes),
            "missing": d.get("missing", 0),
            "codes": codes,
        }
        p.write_text(json.dumps(new, ensure_ascii=False), encoding="utf-8")
        converted += 1
    print(f"转换 {converted} 个，跳过（已瘦）{skipped} 个，共 {len(files)} 个文件")


if __name__ == "__main__":
    main()
