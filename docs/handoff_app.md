# Handoff：鸟瘾综合征 / Birdaholic（App 本体）

> Flutter iOS+Android 鸟类闪卡学习 App，配 FastAPI 服务器。本文档供接手者（人或 Codex）快速上手。

---

## 1. 这是什么

- **产品名**：鸟瘾综合征（英文 Birdaholic）
- **类型**：鸟类识别闪卡（图片认鸟 / 听声认鸟），面向观鸟爱好者
- **平台**：iOS + Android（同一套 Flutter 代码）
- **法律主体**：伍洋（个人 ICP 备案，**非商业**）
- **备案号**：粤ICP备2026057758号-2A
- **仓库**：`/Users/wuyang/Documents/bird_flashcard_repo`，GitHub `github.com/oastwy/Birdaholic`
- **当前版本**：`1.6.11+67`（`pubspec.yaml` 与 `lib/app_version.dart` 两处都要同步改）

---

## 2. 发布状态

| 渠道 | 状态 |
|---|---|
| Android APK | 已构建并发到 GitHub Release v1.6.11，下载页 `https://birding.today/download.html` |
| iOS App Store | 提交资料已基本填好（年龄分级 4+、隐私/支持 URL、版权"2026 伍洋"、免费、无需登录），**Archive 需用户本人在 Xcode 做** |
| 国内安卓商店 | 备案已过，靠 GitHub Release + 下载页分发 |

---

## 3. 技术栈与架构

- **Flutter** 3.x（SDK 在 `/Users/wuyang/.flutter-sdk`，**flutter 不在全局 PATH**，必须用全路径 `/Users/wuyang/.flutter-sdk/bin/flutter`）
- **本地存储**：SharedPreferences（key 带 `flutter.` 前缀），无本地数据库
- **数据包**：zip 包，内含若干物种的 manifest + 媒体；内置包 `data_packs/china_common_100_v1.2_opt.zip`（41.5MB，100 种）
- **后端**：FastAPI（无数据库，文件即数据），见第 5 节
- **关键依赖**：audioplayers、geolocator（用系统 API，无第三方地图 SDK）、file_picker、lpinyin（拼音首字母搜索）、wakelock_plus、archive

### 数据流
App 启动 → `_ConsentGate`（同意协议）→ HomeScreen（底部 Tab：闪卡 / 鸟种 / 进度 / 设置）。媒体既可来自**内置/下载的数据包**（离线），也可从**服务器** `https://birding.today` 拉取。

---

## 4. 关键文件地图

### Screens（`lib/screens/`）
| 文件 | 作用 |
|---|---|
| `flashcard_screen.dart` | **核心**：闪卡主界面，图片/音频模式、左右滑切鸟、多图轮播、闪卡内上传入口 |
| `pack_manage_screen.dart` | 数据包管理页；按 token 角色显示不同 section（上传/审核/历史/服务器媒体/用户管理/反馈审核）；省名录下载器 `_showProvincePicker` |
| `species_list_screen.dart` | 鸟种列表 + 搜索（支持拼音首字母） |
| `settings_screen.dart` | 设置 + 隐私政策/用户协议/声明致谢入口 + ICP 页脚（**合规必需，勿删**） |
| `in_flashcard_upload_modal.dart` | 闪卡内上传弹窗（与数据包页上传 UI 统一，含 CC 协议勾选） |
| `consent_dialog.dart` / `privacy_policy_screen.dart` / `user_agreement_screen.dart` / `data_attribution_screen.dart` | **合规四件套**：首启同意 + 三个法律页 |
| `upload_section.dart` / `upload_review_section.dart` / `audit_history_section.dart` / `user_management_section.dart` / `feedback_review_section.dart` / `server_media_manager_section.dart` | 多用户上传+审核+管理子页 |

### Services（`lib/services/`）
| 文件 | 作用 |
|---|---|
| `pack_manager.dart` | 数据包加载/切换/合并；内置包 assetPath、avilist 分类权威源 |
| `server_media_service.dart` | 拉服务器媒体；`defaultBaseUrl = 'https://birding.today'` |
| `admin_upload_service.dart` | 所有上传/审核/用户/反馈 API 客户端 |
| `storage.dart` | SharedPreferences 封装；token、同意版本、贡献者名等 |
| `pinyin.dart` | `Pinyin.initials()` 拼音首字母（lpinyin） |
| `ecological_group.dart` | 六大生态类群（游禽/涉禽/陆禽/猛禽/攀禽/鸣禽）映射 |
| `avilist_service.dart` | AviList 分类权威（静态缓存，2.3MB JSON 只解析一次） |
| `ebird_service.dart` / `xeno_canto_service.dart` / `inaturalist_service.dart` / `wikimedia_service.dart` | 各数据源客户端 |

### 合规版本常量
- `lib/screens/privacy_policy_screen.dart:3` → `kPrivacyPolicyVersion = '1.0'`（**改协议内容时必须 bump 此值**，否则老用户不会重新弹同意框）

---

## 5. 服务器后端

- **机器**：`root@124.223.101.188`，域名 `birding.today`（HTTPS via certbot）
- **服务**（systemd，都 active）：
  - `birdaholic-upload.service` → FastAPI `/data/server/upload_server.py`（业务 API）
  - `nginx.service` → 反代 + 静态（`/data/packs`、`/species/` 走 nginx 直出）
  - `filebrowser.service` → 网页版文件管理（127.0.0.1:8082，baseurl `/filebrowser`）
- **数据目录**：`/data/species/{Genus_species}/{images,audio,audio_spectrograms}/` + 每种一个 `manifest.json`；无数据库
- **用户体系**：`users.json` 映射 `token → {id, role, name}`，role 为 `admin` / `beta`；上传带 `pending:true` 进审核队列
- **主要端点**：`/api/upload`（带自动压缩 `_compress_image`）、`/api/whoami`、`/api/admin/users`、`/api/admin/pending`、`/api/admin/approve`（通过后剔除同种 iNat 条目）、`/api/admin/reject`、`/api/admin/history`、`/api/feedback`、`/api/set_image_difficulty`
- **媒体处理**：上传图片 HEIC/PNG→JPG 压缩；音频频谱图 `showspectrumpic=900x334` JPG

> ⚠️ **历史教训**：Codex 曾两次覆盖 `upload_server.py` 弄丢 `_compress_image`、又删过 settings 里的合规入口。改服务器/settings 前先确认这些还在。

---

## 6. 构建与发布流程

### Android APK
```bash
cd /Users/wuyang/Documents/bird_flashcard_repo
/Users/wuyang/.flutter-sdk/bin/flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
# 改名 Birdaholic_v<版本>_android.apk，发 GitHub Release，更新 download.html
```
- **签名**：release keystore `/Users/wuyang/birdaholic_release.jks`，签名配置（storeFile/storePassword/keyAlias/keyPassword）在 `android/local.properties`（未纳入 git，值找用户）
- ⚠️ **技术债**：`android/app/` 下同时存在 `build.gradle`（groovy，含 release 签名，**活跃**）和 `build.gradle.kts`（旧的，用 debug 签名）。**应删掉 `.kts` 避免混淆**。

### iOS Archive（用户本人做）
- bundle id `today.birding.birdaholic`，team `4X6MA7WX67`，version/build 跟 `1.6.11/67`
- ⚠️ 历史坑：CodeSign "resource fork...not allowed" → 先 `xattr -cr build/ ios/Pods ~/.pub-cache`
- 模拟器只能 debug（`flutter run --release` 不支持模拟器）

### 发布版本号
改 3 处保持一致：`pubspec.yaml` 的 `version:`、`lib/app_version.dart` 的 `appVersionName`+`appBuildNumber`。然后 `flutter analyze` 0 issue 再打包。

### 下载页
`https://birding.today/download.html`（服务器上），改版本：`sed -i -E 's#v1\.6\.[0-9]+#v1.6.NEW#g' download.html`

---

## 7. 凭据与常量

> ⚠️ **真实密码/token 不写进本文档**（避免随 git 泄露）。下表只给"在哪找"。实际值见本机 `android/local.properties`、服务器配置，或向用户索取。

| 项 | 位置 / 说明（值找用户要） |
|---|---|
| Android keystore | `/Users/wuyang/birdaholic_release.jks`；密码/alias 在 `android/local.properties`（**该文件已/应在 .gitignore**） |
| 服务器 SSH | `root@124.223.101.188`（密钥/密码找用户） |
| 管理员 token | 向用户索取；服务器 `users.json` 里 role=admin 的那条 |
| FileBrowser 后台 | `birding.today/filebrowser`，账号密码找用户 |
| eBird API key | 找用户（采集/名录用） |
| iOS team | `4X6MA7WX67`（非密） |
| bundle id | `today.birding.birdaholic`（非密） |
| ICP | 粤ICP备2026057758号-2A，主体 伍洋（公开备案信息） |

---

## 8. 合规红线（勿动）

- **首启同意框** `_ConsentGate`：拒绝则 Android 退出、iOS 显示"需同意才能使用"
- **三个法律页**（隐私/协议/致谢）+ settings 入口 + ICP 页脚：上架必需，Codex 删过一次
- **不收集任何个人信息**，无第三方共享，无第三方地图/统计 SDK
- **用户内容 CC BY-NC 4.0**；iNat 仅用 CC 授权图；xeno/wiki 保留署名
- **个人 ICP 不能商业经营**：付费招募广告会同时违反 ICP 非商业 + eBird 条款 → 只能做免费信息板
- App Store 描述里**不要**放联系电话/二维码/外链

---

## 9. 已知问题 / 技术债

1. **`android/app/build.gradle.kts` 应删**（与 groovy 版冲突，见第 6 节）
2. **`docs/ebird_permission_email.md`** 里被误粘了基金本子文字 —— **保持原样别清理**（用户知情）
3. 模拟器无法跑 release；同意框无法用 `defaults`/`plutil` 绕过（key 带点 + cfprefsd 缓存）→ 测试用 `xcrun simctl spawn <id> defaults write today.birding.birdaholic "flutter.consent_accepted_version" -string "1.0"`

---

## 10. 待办 / 未完成

- [ ] iOS Xcode Archive 上传 App Store（用户本人）
- [ ] App Store 开发者账号需 伍洋 实名（与 ICP 一致）
- [ ] eBird 邮件授权回复存档
- [ ] 清理 `build.gradle.kts`
- [ ] 全球鸟类媒体采集（**另一条线，已单独交接** → `docs/handoff_world_ingest.md`）

---

## 11. 给接手者的注意事项

- flutter 用全路径 `/Users/wuyang/.flutter-sdk/bin/flutter`
- 改完 `flutter analyze --no-pub` 必须 0 issue
- **提交/推送前问用户**；不要生成 `" 2"` `" 3"` 之类重复垃圾文件
- 改 `upload_server.py` 或 settings 合规入口前，先确认现有功能没被覆盖
- 改隐私政策内容 → 同步 bump `kPrivacyPolicyVersion`
