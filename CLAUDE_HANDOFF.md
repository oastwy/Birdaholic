# Birdaholic / 鸟瘾综合征 开发交接

这是一份给后续 AI 或开发者直接接手用的项目说明。当前主仓库路径：

```text
/Users/wuyang/Documents/bird_flashcard_repo
```

## 一句话目标

Birdaholic 是一个 Flutter 鸟类闪卡预习/学习 App，核心功能是导入鸟种清单、按鸟种下载/管理图片和鸟鸣音频、用闪卡进行学习复习，并支持 Android APK、iOS 真机安装和 TestFlight 测试。

## 当前技术栈

- Flutter / Dart，不是 React Native，也不是 uni-app。
- Android 与 iOS 共用 Flutter 业务代码。
- 本地数据包以 ZIP 导入为主，内部包含 `manifest.json`、`species.json`、`sounds/`、可选 `images/`。
- 音频播放使用 `audioplayers`。
- 文件选择使用 `file_picker`。
- 本地持久化使用 `shared_preferences` 和应用文档目录。

## 当前版本和构建状态

- `pubspec.yaml` 当前版本：`1.0.23+24`
- iOS Bundle ID：`today.birding.birdaholic`
- iOS 产品名：`Birdaholic`
- iOS Team：`Yang Wu`，项目里当前 `DEVELOPMENT_TEAM = 4X6MA7WX67`
- iOS `Info.plist` 已写入出口合规声明，当前 App 不包含非豁免加密：

```text
ITSAppUsesNonExemptEncryption = false
```

- iOS Archive 已成功过一次；如果改动 `pubspec.yaml` 资源、`Info.plist` 或版本号，需要重新 Archive。
- 本机曾出现 `security find-identity -v -p codesigning` 为 `0 valid identities found`，补齐 Apple 签名证书后 Archive 成功。

## 重要安全规则

- 不要把 eBird API key、Xeno-canto API key、GitHub token 写死进代码。
- App 内应只提供“设置页面手动填写 API key”，并保存到本机。
- 如果日志、文档或提交记录里出现 token，要立即移除并建议用户轮换 token。
- 大型数据包和 ZIP 不应提交到 GitHub，仓库 `.gitignore` 已忽略：

```text
data_packs/*.zip
*.apk
```

## 已完成的重要功能/修复

- GitHub 轻量化：移除了大 ZIP 历史包上传问题，当前仓库不应再提交大型数据包。
- App 封面/图标已替换为 Birdaholic 黄色鸟图标。
- API key 改为用户手动输入，不应内置用户私钥。
- App Store Connect 出口合规问题已通过 `ios/Runner/Info.plist` 的 `ITSAppUsesNonExemptEncryption = false` 固定声明。
- 首页和部分 UI 已做过紧凑化方向调整。
- 预习语义已倾向“开始学习”。
- 数据导入支持 CSV/TXT/英文名/学名，不强制 JSON。
- eBird 示例清单已生成：

```text
import_lists/ebird_pasted_checklist_2026-04-30.csv
```

- 全国鸟种清单相关数据在：

```text
assets/data/china_birds.json
assets/data/china_birds.csv
assets/data/avilist_species.json
```

- iOS 已新增工程并配置：

```text
ios/Runner.xcworkspace
ios/Runner.xcodeproj
ios/Podfile
```

- iOS `User Script Sandboxing` 已关闭，避免 Xcode Archive 时出现：

```text
Sandbox: dart deny file-read-data
Sandbox: rsync deny file-read-data
```

相关配置在：

```text
ios/Runner.xcodeproj/project.pbxproj
ENABLE_USER_SCRIPT_SANDBOXING = NO
```

- 当前不再随 App 内置大型数据包。数据包应通过外部发布、用户导入或后续在线下载获得，避免每次 App 更新都携带数百 MB ZIP。

App 内“数据包”页的内置列表在：

```text
lib/services/pack_manager.dart
```

当前 `PackManager.builtinPacks` 为空。大型 ZIP 被 `.gitignore` 忽略，不会提交到 GitHub。

## 常用命令

刷新依赖：

```bash
/Users/wuyang/.flutter-sdk/bin/flutter pub get
```

分析：

```bash
/Users/wuyang/.flutter-sdk/bin/flutter analyze
```

Android APK：

```bash
/Users/wuyang/.flutter-sdk/bin/flutter build apk --release
```

iOS 刷新版本配置：

```bash
/Users/wuyang/.flutter-sdk/bin/flutter build ios --config-only --build-name=1.0.23 --build-number=24
```

iOS Release 真机构建：

```bash
/usr/bin/arch -arm64e xcrun xcodebuild \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -destination generic/platform=iOS \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build
```

iOS 安装到已连接 iPhone：

```bash
xcrun devicectl device install app \
  --device 952E1637-A3DB-5B79-B27C-607BD5353101 \
  /Users/wuyang/Library/Developer/Xcode/DerivedData/Runner-glnrtlwgczsgitazldouqzrqscas/Build/Products/Release-iphoneos/Birdaholic.app
```

如果 `devicectl` 报 `DeviceLocked`，让用户解锁 iPhone 并保持亮屏。

## TestFlight 当前注意事项

如果 Organizer 里一直显示旧版本：

1. 先确认 `pubspec.yaml` 版本号，例如当前应为 `1.0.23+24`。
2. 关闭 Xcode Organizer。
3. 重新打开 `ios/Runner.xcworkspace`。
4. 选择 `Any iOS Device (arm64)`。
5. `Product > Clean Build Folder`。
6. `Product > Archive`。
7. 新 Archive 应显示 `1.0.23 (24)` 或更新后的版本。

TestFlight 添加测试时如果提示“缺少出口合规证明”：

- 先确认 `ios/Runner/Info.plist` 里存在 `ITSAppUsesNonExemptEncryption = false`。
- 如果已经归档上传的新包仍提示，再进入该 build 的 Export Compliance 手动确认一次。
- 当前 App 没有自定义加密，只有系统 HTTPS，通常选择不使用非豁免加密。

内部测试只能邀请 Apple Developer 团队成员；普通朋友应走外部测试，首次外部测试需要 Beta App Review。

## 当前已知问题/优先任务

优先级 P1：

- 继续验证通过 ZIP 导入全国鸟类包、布里斯班包后，在 iOS 上安装和解压正常。
- 闪卡页应展示图片/音频贡献者；全国数据包里常见字段包括 `image_contributor` 和 `audios[].contributor`。
- 下载失败时跳过，继续下载下一个。
- 重复资源自动跳过，显示“已下载”。
- 后台下载进度可见，不要因为切页面就丢失。
- 鸟种页面支持删除单个鸟种数据。
- 学习详情 UI 右侧空白问题继续优化。
- 返回操作从详情回总览，不要直接回手机主页。

优先级 P2：

- 鸟种全国名录支持搜索地点，例如云南、那邦。
- eBird API 与 Xeno API 放到同一个设置界面。
- 支持手机定位或手动搜索地点，并用 eBird 查询附近鸟种。
- 背景信息窗口继续压缩，信息层级更清楚。

优先级 P3：

- 为 `birding.today` 生成可托管的鸟类媒体数据库。
- 后期支持网站端添加照片和音频。
- 设计在线数据包下载和断点续传。

## 关键文件

业务入口和页面：

```text
lib/main.dart
lib/screens/home_screen.dart
lib/screens/flashcard_screen.dart
lib/screens/pack_manage_screen.dart
lib/screens/online_import_screen.dart
lib/screens/species_list_screen.dart
lib/screens/progress_screen.dart
```

服务：

```text
lib/services/pack_manager.dart
lib/services/storage.dart
lib/services/avilist_service.dart
lib/services/ebird_service.dart
```

数据：

```text
assets/data/china_birds.json
assets/data/avilist_species.json
assets/data/ebird_sample_checklist.csv
import_lists/ebird_pasted_checklist_2026-04-30.csv
data_packs/盈江鸟鸣试用_v0.1.zip
data_packs/brisbane_v1.0_opt.zip
data_packs/china_birds_v1.0_opt.zip
```

iOS：

```text
ios/Runner.xcworkspace
ios/Runner.xcodeproj/project.pbxproj
ios/Flutter/Generated.xcconfig
ios/Flutter/flutter_export_environment.sh
ios/Podfile
```

打包工具：

```text
packager/build_pack.py
packager/optimize_pack.py
packager/generate_china_pack.py
packager/generate_ebird_sample_checklist.py
packager/transcode_audio.swift
```

## 给 Claude 的直接指令

可以把下面这段直接发给 Claude：

```text
你接手的是 Flutter 项目 Birdaholic，路径是 /Users/wuyang/Documents/bird_flashcard_repo。

请先阅读 CLAUDE_HANDOFF.md、pubspec.yaml、lib/services/pack_manager.dart、lib/screens/pack_manage_screen.dart、lib/screens/flashcard_screen.dart。不要重置或覆盖用户未提交的修改。不要把任何 API token 写进代码或提交到 GitHub。

当前最急任务：
1. 每次功能更新必须递增 pubspec.yaml 版本号，例如从 1.0.23+24 到 1.0.24+25。
2. 修复后运行 flutter pub get、flutter analyze，并给出 iOS Archive/TestFlight 的下一步操作。
3. iOS 提交前确认 Info.plist 保留 ITSAppUsesNonExemptEncryption = false。
4. 大型数据包不随 App 内置；通过外部 ZIP 导入或后续在线下载分发。

当前 iOS 配置：
Bundle ID: today.birding.birdaholic
Product name: Birdaholic
Team: 4X6MA7WX67
ENABLE_USER_SCRIPT_SANDBOXING 已设为 NO。

请优先小步修改、验证，不要做大重构。
```
