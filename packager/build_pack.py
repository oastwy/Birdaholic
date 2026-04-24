#!/usr/bin/env python3
"""
数据包构建工具
将鸟种数据、音频、图片打包成 ZIP 数据包，供 App 导入使用。

用法:
    python build_pack.py                     # 默认输出到 data_packs/
    python build_pack.py -o /path/to/output  # 指定输出目录
    python build_pack.py --name "盈江夏季"    # 自定义数据包名称
"""

import argparse
import json
import os
import shutil
import sys
import zipfile
from datetime import datetime

SUPPORTED_AUDIO_EXTS = (".mp3", ".m4a", ".aac", ".ogg", ".wav")


def get_base_dir():
    """获取脚本所在目录"""
    return os.path.dirname(os.path.abspath(__file__))


def load_json(filepath):
    with open(filepath, "r", encoding="utf-8") as f:
        return json.load(f)


def build_species_json(species_list, audio_results, image_results, base_dir):
    """
    构建 species.json，合并鸟种信息、音频文件引用、图片文件引用。
    输出格式中 audios[].file 和 image 都是相对于数据包根目录的路径。
    """
    result = []
    for sp in species_list:
        sci = sp["sci"]
        entry = {
            "cn": sp["cn"],
            "en": sp["en"],
            "sci": sci,
            "cons": sp.get("cons", ""),
            "habitat": sp.get("habitat", ""),
        }

        # 音频
        audios = audio_results.get(sci, [])
        audio_list = []
        for a in audios:
            filepath = a.get("filepath", "")
            filename = a.get("filename", "")
            if filepath and os.path.exists(filepath):
                size = os.path.getsize(filepath)
                if size > 5000:  # 跳过太小的无效文件
                    audio_list.append({
                        "type": a.get("type", "call"),
                        "file": f"sounds/{filename}",
                    })
        if audio_list:
            entry["audios"] = audio_list

        # 图片
        img_info = image_results.get(sci)
        if img_info and img_info.get("status") == "ok":
            img_path = img_info.get("filepath", "")
            img_file = img_info.get("filename", "")
            if img_path and os.path.exists(img_path):
                entry["image"] = f"images/{img_file}"

        result.append(entry)

    return result


def build_pack(base_dir, output_dir, pack_name, region):
    """构建数据包 ZIP"""
    print("=" * 50)
    print("📦 数据包构建工具")
    print("=" * 50)

    # 加载数据 - 查找 yingjiang_birds 目录
    possible_bases = [
        os.path.join(base_dir, "..", "yingjiang_birds"),
        os.path.join(base_dir, "..", "..", "yingjiang_birds"),
        base_dir,
    ]
    src_dir = None
    for d in possible_bases:
        d = os.path.normpath(d)
        if os.path.exists(os.path.join(d, "bird_species.json")):
            src_dir = d
            break

    if src_dir is None:
        print("❌ 找不到 bird_species.json，请确保 yingjiang_birds 目录存在")
        sys.exit(1)

    species_file = os.path.join(src_dir, "bird_species.json")
    audio_file = os.path.join(src_dir, "audio_results.json")
    image_file = os.path.join(src_dir, "image_results.json")

    species_list = load_json(species_file)
    audio_results = load_json(audio_file) if os.path.exists(audio_file) else {}
    image_results = load_json(image_file) if os.path.exists(image_file) else {}

    print(f"📋 鸟种: {len(species_list)}")
    print(f"🔊 音频记录: {len(audio_results)}")
    print(f"🖼️  图片记录: {len(image_results)}")

    # 构建 species.json
    species_json = build_species_json(species_list, audio_results, image_results, base_dir)

    # 统计
    audio_count = sum(len(s.get("audios", [])) for s in species_json)
    image_count = sum(1 for s in species_json if s.get("image"))

    # 构建 manifest.json
    manifest = {
        "name": pack_name,
        "region": region,
        "version": "1.0",
        "created": datetime.now().strftime("%Y-%m-%d"),
        "species_count": len(species_json),
        "audio_count": audio_count,
        "image_count": image_count,
    }

    print(f"\n📊 数据包内容:")
    print(f"   鸟种: {manifest['species_count']}")
    print(f"   音频: {manifest['audio_count']}")
    print(f"   图片: {manifest['image_count']}")

    # 创建 ZIP
    os.makedirs(output_dir, exist_ok=True)
    safe_name = pack_name.replace(" ", "_").replace("/", "_")
    zip_path = os.path.join(output_dir, f"{safe_name}_v{manifest['version']}.zip")

    print(f"\n🔄 正在打包...")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        # manifest.json
        zf.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
        # species.json
        zf.writestr("species.json", json.dumps(species_json, ensure_ascii=False, indent=2))

        # 音频文件
        sounds_src = os.path.join(src_dir, "sounds")
        if os.path.isdir(sounds_src):
            count = 0
            for fname in os.listdir(sounds_src):
                fpath = os.path.join(sounds_src, fname)
                if os.path.isfile(fpath) and fname.lower().endswith(SUPPORTED_AUDIO_EXTS):
                    # 只打包在 species.json 中引用过的文件
                    zf.write(fpath, f"sounds/{fname}")
                    count += 1
            print(f"   音频文件: {count} 个")

        # 图片文件
        images_src = os.path.join(src_dir, "images")
        if os.path.isdir(images_src):
            count = 0
            for fname in os.listdir(images_src):
                fpath = os.path.join(images_src, fname)
                if os.path.isfile(fpath):
                    ext = os.path.splitext(fname)[1].lower()
                    if ext in (".jpg", ".jpeg", ".png", ".webp", ".gif"):
                        zf.write(fpath, f"images/{fname}")
                        count += 1
            print(f"   图片文件: {count} 个")

    size_mb = os.path.getsize(zip_path) / 1024 / 1024
    print(f"\n✅ 数据包构建完成!")
    print(f"   文件: {zip_path}")
    print(f"   大小: {size_mb:.1f} MB")
    print(f"\n📱 使用方式:")
    print(f"   1. 将 {os.path.basename(zip_path)} 传到手机")
    print(f"   2. 在 App 中点击「导入数据包」选择该文件")

    return zip_path


def main():
    parser = argparse.ArgumentParser(description="构建鸟鸣闪卡数据包")
    parser.add_argument("-o", "--output", default=None, help="输出目录 (默认: ../data_packs/)")
    parser.add_argument("-n", "--name", default="盈江鸟鸣闪卡", help="数据包名称")
    parser.add_argument("-r", "--region", default="云南盈江", help="地区名称")
    args = parser.parse_args()

    base_dir = get_base_dir()
    output_dir = args.output or os.path.join(base_dir, "..", "data_packs")

    build_pack(base_dir, output_dir, args.name, args.region)


if __name__ == "__main__":
    main()
