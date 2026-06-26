#!/usr/bin/env python3
"""生成「中国鸟看图选择题」题库。

为 china_birds.json（~1490 种中国鸟）里每个在服务器上有可用图片的物种生成一道
「看图选鸟种」选择题：正确答案 = 该种中文名，3 个干扰项优先同科、其次同目、再全局随机。
随机用固定种子（按 sci 派生），可复现。

设计成可在**服务器本地**跑（读 /data/species/*/manifest.json，零网络），也可指定 --species-dir
在别处跑。难度档取 manifest 顶层 difficulty（物种难度，由后台「逐种评级」写入；未评为 0）
与所选图片的 difficulty 综合，供 App 分级出题。

用法（服务器上）：
  python3 build_china_quiz_bank.py \
      --china-birds /data/server/china_birds.json \
      --species-dir /data/species \
      --out /data/server/china_quiz_bank.json
"""
import argparse
import json
import random
import re
import sys
from pathlib import Path

PUBLIC_HTTPS_BASE = "https://birding.today"


def species_key(scientific_name: str) -> str:
    """与服务器 species_key 一致：学名空白转下划线。"""
    return re.sub(r"\s+", "_", scientific_name.strip())


def pick_image(manifest: dict) -> dict | None:
    """选一张代表图：跳过 pending / 占位图，优先图片难度最低（最清晰典型）的。"""
    imgs = [
        x
        for x in manifest.get("images", [])
        if not x.get("pending")
        and not x.get("placeholder")
        and x.get("source") != "placeholder"
        and x.get("file")
    ]
    if not imgs:
        return None
    imgs.sort(key=lambda x: int(x.get("difficulty", 1) or 1))
    return imgs[0]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--china-birds", required=True, help="china_birds.json 路径")
    ap.add_argument("--species-dir", default="/data/species", help="manifest 根目录")
    ap.add_argument("--out", required=True, help="输出题库 json 路径")
    ap.add_argument("--min-quality", type=int, default=0,
                    help="图片难度>该值视为质量过低而跳过（0=不过滤；评级后可设阈值）")
    args = ap.parse_args()

    china = json.loads(Path(args.china_birds).read_text(encoding="utf-8"))
    species_dir = Path(args.species_dir)

    # 物种池：sci -> {zh, en, order, family}
    pool = []
    for s in china:
        sci = (s.get("sci") or "").strip()
        zh = (s.get("zh") or s.get("cn") or "").strip()
        if not sci or not zh:
            continue
        pool.append({
            "sci": sci,
            "zh": zh,
            "en": (s.get("en") or "").strip(),
            "order": (s.get("order") or "").strip(),
            "family": (s.get("family") or "").strip(),
        })

    by_family: dict[str, list[str]] = {}
    by_order: dict[str, list[str]] = {}
    all_zh = []
    for p in pool:
        all_zh.append(p["zh"])
        if p["family"]:
            by_family.setdefault(p["family"], []).append(p["zh"])
        if p["order"]:
            by_order.setdefault(p["order"], []).append(p["zh"])

    bank = []
    no_image = 0
    low_quality = 0
    for p in pool:
        key = species_key(p["sci"])
        mp = species_dir / key / "manifest.json"
        if not mp.exists():
            no_image += 1
            continue
        try:
            manifest = json.loads(mp.read_text(encoding="utf-8"))
        except Exception:
            no_image += 1
            continue
        img = pick_image(manifest)
        if img is None:
            no_image += 1
            continue
        img_diff = int(img.get("difficulty", 1) or 1)
        if args.min_quality and img_diff > args.min_quality:
            low_quality += 1
            continue

        rng = random.Random(p["sci"])  # 固定种子，可复现
        # 干扰项：同科 > 同目 > 全局，去掉自己
        distractors: list[str] = []
        for source in (by_family.get(p["family"], []),
                       by_order.get(p["order"], []),
                       all_zh):
            cands = [z for z in source if z != p["zh"] and z not in distractors]
            rng.shuffle(cands)
            for z in cands:
                if len(distractors) >= 3:
                    break
                distractors.append(z)
            if len(distractors) >= 3:
                break
        if len(distractors) < 3:
            continue  # 凑不够 4 选 1，跳过

        options = [p["zh"]] + distractors[:3]
        rng.shuffle(options)
        answer = options.index(p["zh"])

        file_rel = img["file"].lstrip("/")  # 形如 images/xxx.jpg
        image_url = f"{PUBLIC_HTTPS_BASE}/species/{key}/{file_rel}"

        species_diff = int(manifest.get("difficulty", 0) or 0)  # 0=未评级
        bank.append({
            "id": f"q_{key}",
            "sci": p["sci"],
            "zh": p["zh"],
            "en": p["en"],
            "order": p["order"],
            "family": p["family"],
            "image_url": image_url,
            "options": options,
            "answer": answer,
            "species_difficulty": species_diff,
            "image_difficulty": img_diff,
        })

    Path(args.out).write_text(
        json.dumps(bank, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"题库已生成：{args.out}")
    print(f"中国鸟总数={len(pool)} 出题={len(bank)} 无图跳过={no_image} 质量过低跳过={low_quality}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
