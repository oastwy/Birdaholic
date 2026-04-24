# BirdFlashcard App 架构设计

## 概述

鸟鸣闪卡学习 App，支持数据包分离，一次开发多平台运行（Android/iOS）。

## 项目结构

```
bird_flashcard/
├── pubspec.yaml                 # Flutter 项目配置
├── ARCHITECTURE.md              # 本文件
├── lib/
│   ├── main.dart                # 入口
│   ├── models/
│   │   ├── species.dart         # 鸟种数据模型
│   │   ├── audio_info.dart      # 音频信息模型
│   │   └── data_pack.dart       # 数据包元信息模型
│   ├── services/
│   │   ├── pack_manager.dart    # 数据包导入/解析/管理
│   │   ├── audio_player.dart    # 音频播放服务
│   │   └── storage.dart         # 本地存储（收藏、进度）
│   ├── screens/
│   │   ├── home_screen.dart     # 主页（底部导航）
│   │   ├── flashcard_screen.dart# 闪卡模式页
│   │   ├── species_list_screen.dart # 鸟种列表页
│   │   ├── favorites_screen.dart# 收藏夹页
│   │   └── pack_manage_screen.dart # 数据包管理页
│   └── widgets/
│       ├── bird_card.dart       # 闪卡组件（翻转动画）
│       ├── audio_player_widget.dart # 播放器控件
│       └── species_tile.dart    # 鸟种列表项
├── packager/
│   └── build_pack.py            # Python 数据包构建脚本
└── android/                     # Android 平台代码
```

## 数据包格式

### ZIP 结构
```
yingjiang_v1.zip
├── manifest.json       # 元信息
├── species.json        # 鸟种列表
├── sounds/             # MP3 音频文件
│   ├── 107314_call.mp3
│   └── ...
└── images/             # JPG 图片文件
    ├── Buceros_bicornis.jpg
    └── ...
```

### manifest.json
```json
{
  "name": "盈江鸟鸣闪卡",
  "region": "云南盈江",
  "version": "1.0",
  "created": "2026-04-10",
  "species_count": 136,
  "audio_count": 243,
  "image_count": 133
}
```

### species.json
```json
[
  {
    "cn": "双角犀鸟",
    "en": "Great Hornbill",
    "sci": "Buceros bicornis",
    "cons": "1",
    "habitat": "热带雨林",
    "audios": [
      {"type": "call", "file": "sounds/107314_call.mp3"},
      {"type": "song", "file": "sounds/302245_song.mp3"}
    ],
    "image": "images/Buceros_bicornis.jpg"
  }
]
```

## 核心流程

### 数据包导入
1. 用户选择 .zip 文件（系统文件选择器）
2. 解压到 App 沙盒 `documents/packs/{pack_name}/`
3. 解析 manifest.json 和 species.json
4. 校验文件完整性
5. 存储到本地数据库

### 闪卡模式
1. 从已加载数据包获取鸟种列表
2. 按筛选条件（全部/有音频/保护等级/收藏）构建牌组
3. 自动播放第一张卡片的鸟鸣
4. 用户点击「揭晓」翻转卡片显示答案和图片
5. 点击「认识/不认识」记录并自动跳转下一张

### 存储
- 数据包文件：App 沙盒 documents/packs/
- 收藏列表：SharedPreferences
- 学习进度：SharedPreferences

## 技术栈
- **Flutter 3.29+** (Dart)
- **audioplayers** - 音频播放
- **path_provider** - 文件路径
- **shared_preferences** - 本地存储
- **archive** - ZIP 解压
- **file_picker** - 文件选择
