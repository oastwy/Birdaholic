# Birdaholic / 鸟瘾综合征 Handoff

最后更新：2026-05-16  
项目路径：`/Users/wuyang/Documents/bird_flashcard_repo`  
当前 App 版本：`1.3.0+33`

## 一句话目标

鸟瘾是 Flutter 鸟类闪卡 App：用本地/服务器数据包管理鸟图和鸟鸣，按 eBird 地点筛出附近鸟，用学习/复习/选择题进行训练。另有一个 Mac 本地 OSEA 批量鸟图识别工具，用于管理员整理照片。

## 当前状态

`flutter analyze --no-pub` 通过（exit code 0），只剩一个无影响的 warning（species_list_screen.dart 里一个 dead null-aware expression）。

## v1.3.0 新功能（本次大改）

### 首页（ProgressScreen）

- 移除原来 4 个模式按钮。
- **打卡**按钮（绿色）：开始闪卡复习，行为与原"开始学习"一致。
- **预习**按钮（蓝色）：跳转到鸟种预习页（tab 2）。
- 播客卡片：自动拉取小宇宙「鸟瘾综合征」最新一期，显示封面+标题+日期，点击跳转 App/网页。

### 鸟种页（SpeciesListScreen）→ 全新预习浏览界面

- **当前数据包模式**：整个替换为竖向 PageView，每页展示一种鸟：
  - 上半部分：本地图片（+ 服务器额外图片，左右滑切换）、致谢、收藏按钮、「详情」按钮。
  - 下半部分：中/英/学名、保护级别 chip、本地音频播放器、辨识特征（最多 4 行）。
  - 上下滑翻页浏览鸟种，右上角显示 "N / 总数"。
  - 顶部工具栏：名录/数据包 切换 + 搜索（点图标展开/收起）+ 按目筛选（popup）。
  - 「详情」按钮：push 完整 `BirdPreviewScreen`（含上传、eBird 筛选等）。
  - 暂无图片时显示「从服务器补充」按钮。
- **鸟种名录模式**：保留原有列表 UI（用于 eBird 地点筛选 + 批量勾选下载）。

### 闪卡（FlashcardScreen）

- **10 鸟一组**：每组结束弹出完成面板（动画 + 铃声），显示本组/累计成绩，可"继续下一组"或"重学本组"。
- **多图切换**：卡片内左右滑动切换服务器额外图片，仅 >1 张时才显示 PageView 和点状指示器。
- **完成音效**：`assets/sounds/complete.m4a`（C-E-G 三音上升铃声，约 0.9s）。
- **了解此鸟**：卡片背面按钮，push `BirdPreviewScreen` 查看详情。
- **管理员难度星**：管理员模式下卡片背面出现 1-5 星评分，持久化到 `species.json`。

### 预习界面（BirdPreviewScreen）—— 新建

路径：`lib/screens/bird_preview_screen.dart`

- 两种构造：`BirdPreviewScreen(species:...)` 单种 / `BirdPreviewScreen.list(speciesList:...)` 列表。
- 黑绿暗色主题，上下滑（手势）或底部箭头翻页。
- 照片：本地 + 服务器图合并，横向 PageView + 点状指示器 + 致谢 + 全屏预览。
- 音频：本地 AudioPlayerWidget + 服务器音频（含贡献者可点链接）。
- eBird 地点筛选：顶部绿色图标，弹出 sheet 输入地点，筛选可浏览的鸟种范围。
- 上传：图片/音频按钮，普通用户存本地，管理员推服务器。
- 收藏：右上角星形按钮，复用 storage.toggleFavorite。

### 其他

- **Species 模型**：新增 `difficulty` 字段（int，默认 1，omit-if-default），管理员可改。
- **PackManager**：新增 `saveSpeciesDifficulty()` 持久化到 species.json。
- **PodcastService**：手动解析 RSS XML，无需额外依赖。
- **`.claude/settings.json`**：新建，含 flutter analyze 等常用命令白名单。

## 关键文件

Flutter App：

```text
lib/screens/home_screen.dart          ← jumpToPreview() 新增
lib/screens/progress_screen.dart      ← 双按钮 + 播客卡
lib/screens/flashcard_screen.dart     ← 10鸟组、多图、难度
lib/screens/species_list_screen.dart  ← PageView 预习浏览（大改）
lib/screens/bird_preview_screen.dart  ← 新建，预习详情页
lib/widgets/bird_card.dart            ← 多图 PageView + 难度星 + 了解此鸟
lib/services/pack_manager.dart        ← saveSpeciesDifficulty
lib/services/podcast_service.dart     ← 新建，小宇宙 RSS
lib/services/server_media_service.dart
lib/services/admin_upload_service.dart
lib/models/species.dart               ← difficulty 字段
lib/models/audio_info.dart
assets/sounds/complete.m4a            ← 新建，完成音效
```

本地工具/服务器：

```text
packager/osea_batch_identifier.py
packager/OseaBatchIdentifierApp.swift
server/upload_server.py
```

## 构建和验证命令

```bash
cd /Users/wuyang/Documents/bird_flashcard_repo

# 分析
/Users/wuyang/.flutter-sdk/bin/flutter analyze --no-pub

# 测试
/Users/wuyang/.flutter-sdk/bin/flutter test --no-pub

# iOS archive（需先 SDK 下完）
/Users/wuyang/.flutter-sdk/bin/flutter build ipa --release
```

## iOS Archive 注意事项

当前使用 Xcode 26 beta，iOS 26.5 SDK 需要下载（约 8.5 GB），下完后直接跑 `flutter build ipa --release` 即可。

历史坑：
- `ios/Pods/Manifest.lock` 不存在或 sandbox 不同步：进 `ios` 跑 `pod install`。
- `Generated.xcconfig` 被重置时，确认版本号和 build number（当前 1.3.0+33）。
- 出口合规已在 Info.plist 写过 `ITSAppUsesNonExemptEncryption = false`，如丢失需补回。

## 服务器

```text
http://124.223.101.188:8080
```

上传密钥通过服务端环境变量 `BIRDAHOLIC_UPLOAD_TOKEN` 控制。

## 数据包

内置包：`data_packs/brisbane_v1.0_opt.zip`

逐物种下载流程：eBird API → world_birds.json 映射 → 服务器媒体 → fallback Xeno-Canto/iNaturalist。

## 已知问题 / 下一步

- species_list_screen.dart 中一个 dead null-aware warning（无功能影响）。
- OSEA DMG 不含 Python 依赖，需用户自装 `onnxruntime pillow numpy`。
- 服务器若未同步最新 `upload_server.py`，管理员上传会报接口失败。
- 提交前注意排除大目录：`.birdnet_engine_venv/`、`dist/`、`server_media_library/`、`upload_batch/`。
- eBird 筛选目前在闪卡页和预习详情页，数据包页尚未集成（原计划）。

## 最近 analyze 结果（2026-05-16）

```
exit code 0
1 warning（dead_null_aware_expression，无影响）
```
