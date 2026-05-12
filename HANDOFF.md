# Birdaholic / 鸟瘾综合征 Handoff

最后更新：2026-05-12  
项目路径：`/Users/wuyang/Documents/bird_flashcard_repo`  
当前 App 版本：`1.2.0+32`

## 一句话目标

鸟瘾是 Flutter 鸟类闪卡 App：用本地/服务器数据包管理鸟图和鸟鸣，按 eBird 地点筛出附近鸟，用学习/复习/选择题进行训练。另有一个 Mac 本地 OSEA 批量鸟图识别工具，用于管理员整理照片。

## 当前版本

版本号位置：

```text
pubspec.yaml                         version: 1.2.0+32
ios/Flutter/Generated.xcconfig       FLUTTER_BUILD_NAME=1.2.0 / NUMBER=32
ios/Flutter/flutter_export_environment.sh
```

Archive 前建议确认这三处一致。

## 最近完成的功能

### 闪卡页

- 去掉闪卡页顶部“闪卡学习”标题，节省空间。
- 学习模式与复习模式已区分：
  - 学习模式：每道题出现时直接显示答案。
  - 复习模式：每道题出现时不显示答案，点“不认识”后显示答案。
- 音频题修复：学习模式选择“音频”时，答案区优先显示音频播放器，不再先显示图片。
- 答案区遮挡优化：卡片更紧凑，滚动区底部加留白。
- 闪卡底部有 `?` 问号入口，编辑“识别特征”。
- 上传图、上传音频：
  - 普通用户：保存到本地当前数据包。
  - 管理员模式：本地保存并推送服务器。
- 闪卡筛选加入 eBird 地点按钮，可输入 `CN`、`CN-53`、`那邦` 等，把当前牌组限制到该地点名录匹配的鸟种。

### 数据包页

- 保留两种下载模式：
  - 整包 ZIP 下载。
  - 按 eBird 国家/地区名录逐物种下载。
- 整包下载支持 `.part` 断点续传，校验 `Content-Range`，先解压到 staging 目录，成功后再替换旧包。
- API 设置里新增“管理员上传密钥”。填入后开启管理员模式。

### 服务器媒体逻辑

- `ServerMediaService` 优先从服务器按物种拉媒体。
- 服务器没有对应物种时，下载器可 fallback 到 Xeno-Canto 音频、iNaturalist/Wikimedia 图片。
- 音频贡献者修复：
  - 不再默认显示 `Xeno-canto` 当作者。
  - 优先使用每条音频的 `contributor`。
  - 旧包如果 `audio_credit` 是平台名但 `audios[].contributor` 有人名，也会优先显示人名。

### 管理员上传

新增：

```text
lib/services/admin_upload_service.dart
```

接口：

- `POST /api/upload`：上传图片/音频。
- `POST /api/features`：上传识别特征。

服务端文件：

```text
server/upload_server.py
```

服务端已支持：

- `contributor` 字段。
- `identification_features` 写入物种 manifest。

## OSEA 批量鸟图识别工具

目标：Mac 本地批量识别鸟图，给管理员整理照片用。

关键文件：

```text
packager/osea_batch_identifier.py          # Python ONNX 批量识别核心 + CSV 输出
packager/OseaBatchIdentifierApp.swift      # 原生 SwiftUI Mac App 外壳
packager/build_osea_batch_identifier_dmg.sh
packager/OSEA_BATCH_IDENTIFIER.md
dist/OSEA_Batch_Identifier.dmg
```

现状：

- 已从 Tk 界面切换成原生 SwiftUI 外壳，因为本机 Tk 会 abort，之前导致 DMG 黑屏。
- Python 只作为后台识别引擎。
- 借鉴 SuperPicky 的摄影筛选逻辑，CSV 里加入：
  - `stars` 0-3 星
  - `sharpness`
  - `exposure`
- DMG 已生成并通过 `hdiutil verify`：

```text
dist/OSEA_Batch_Identifier.dmg
```

注意：

- 当前 DMG 不包含 Python 依赖和 OSEA 模型。
- 需要用户先安装：

```bash
python3 -m pip install onnxruntime pillow numpy
```

- OSEA 模型默认路径：

```text
models/osea/bird_model.onnx
models/osea/bird_info.json
```

如果要做真正免安装胖包，需要解决 pip SSL/网络问题或离线 wheel，然后把 Python runtime、onnxruntime、pillow、numpy、模型一起打进 `.app`。

## 关键文件

Flutter App：

```text
lib/screens/home_screen.dart
lib/screens/flashcard_screen.dart
lib/screens/pack_manage_screen.dart
lib/screens/species_list_screen.dart
lib/widgets/bird_card.dart
lib/widgets/audio_player_widget.dart
lib/services/pack_manager.dart
lib/services/download_task_service.dart
lib/services/pack_downloader.dart
lib/services/server_media_service.dart
lib/services/admin_upload_service.dart
lib/services/storage.dart
lib/services/ebird_service.dart
lib/services/inaturalist_service.dart
lib/models/species.dart
lib/models/audio_info.dart
```

本地工具/服务器：

```text
packager/osea_batch_identifier.py
packager/OseaBatchIdentifierApp.swift
packager/build_osea_batch_identifier_dmg.sh
server/upload_server.py
```

## 构建和验证命令

Flutter 分析：

```bash
cd /Users/wuyang/Documents/bird_flashcard_repo
/Users/wuyang/.flutter-sdk/bin/flutter analyze --no-pub
```

Flutter 测试：

```bash
/Users/wuyang/.flutter-sdk/bin/flutter test --no-pub
```

Python 服务端语法：

```bash
python3 -m py_compile server/upload_server.py
python3 -m py_compile packager/osea_batch_identifier.py
```

生成 OSEA DMG：

```bash
packager/build_osea_batch_identifier_dmg.sh
hdiutil verify dist/OSEA_Batch_Identifier.dmg
```

## iOS Archive 注意事项

常规命令：

```bash
cd /Users/wuyang/Documents/bird_flashcard_repo
/Users/wuyang/.flutter-sdk/bin/flutter clean
/Users/wuyang/.flutter-sdk/bin/flutter pub get
open ios/Runner.xcworkspace
```

然后 Xcode 里 `Product > Archive`。

历史坑：

- `ios/Pods/Manifest.lock` 不存在或 sandbox 不同步：进 `ios` 跑 `pod install`。
- `DKPhotoGallery` 缺 Swift 文件：通常是 Pods 损坏或 file_picker 相关 Pod 没同步，清 Pods 后重装。
- `Generated.xcconfig` 被重置时，确认版本号和 build number。
- 出口合规已在 Info.plist 写过 `ITSAppUsesNonExemptEncryption = false`，如丢失需补回。

## 服务器

当前硬编码服务器：

```text
http://124.223.101.188:8080
```

相关服务：

```text
server/upload_server.py
server/uploader.html
```

上传密钥通过服务端环境变量 `BIRDAHOLIC_UPLOAD_TOKEN` 或默认值控制。不要把真实生产密钥写入公开代码。

## 数据包逻辑

内置包：

- `data_packs/brisbane_v1.0_opt.zip`

远程整包：

- Brisbane
- 全国鸟类包

逐物种下载：

1. eBird API 获取国家/地区名录。
2. 用 `world_birds.json` 映射 eBird code / scientific name。
3. 先请求服务器物种媒体。
4. 服务器没有时 fallback 到 Xeno-Canto + iNaturalist/Wikimedia。
5. 写入本地 pack 并激活。

## 已知风险 / 下一步

- OSEA DMG 目前不是免安装版；用户没有 `onnxruntime/pillow/numpy` 时不能识别。
- OSEA SwiftUI 外壳已替代 Tk，但最好在用户机器上再打开一次 DMG 验证。
- OSEA 模型下载按钮现在只在旧 Tk Python GUI 内，SwiftUI 外壳目前是选择本地模型路径；可以下一步把下载模型按钮迁到 SwiftUI。
- eBird 地点筛选在闪卡页已实现，但还可以进一步做成 Merlin 风格的“地点优先 -> 当前可能鸟种 -> 开始学习”流程。
- 管理员上传推送服务器依赖 `/api/upload` 和 `/api/features` 服务端已部署/更新；若服务器未同步最新 `upload_server.py`，App 端会报接口失败。
- 仓库当前 dirty/untracked 文件很多，提交前要仔细筛选，不要误提交大目录：
  - `.birdnet_engine_venv/`
  - `dist/`
  - `server_media_library/`
  - `server_media_library_optimized/`
  - `upload_batch/`

## 最近验证结果

最近一次已通过：

```text
flutter analyze --no-pub
flutter test --no-pub
python3 -m py_compile server/upload_server.py
python3 -m py_compile packager/osea_batch_identifier.py
hdiutil verify dist/OSEA_Batch_Identifier.dmg
```

注意：后续如果继续改 OSEA SwiftUI 外壳，应重新跑 `packager/build_osea_batch_identifier_dmg.sh` 和 `hdiutil verify`。
