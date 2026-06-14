# Handoff：鸟瘾综合征 / Birdaholic（App 本体）

> Flutter iOS+Android 鸟类闪卡学习 App，配 FastAPI 服务器。本文档供接手者（人或 Codex）快速上手。

---

## 0. 当前状态（2026-06-13 更新，**先读这段**）

### 版本与发布
- **线上 = `1.6.15+71`（Android 已发布）**：分支 `feature/v1.6.12-bugfixes-ui`（已 push）。
  - GitHub Release `v1.6.15`（Latest，带 APK）；国内直连 `https://birding.today/download/Birdaholic_v1.6.15_android.apk`，download.html 已指向它。
  - 干净签名 APK 在 `~/Desktop/Birdaholic_v1.6.15_android.apk`（**63.9MB**，arm64+armv7，无 x86_64）。
  - 服务器 `/data/download/` 只留 1.6.15 + `Birdaholic_latest_android.apk` 软链（旧版已删）。
- **iOS 尚未上架**：版本号已对（`ios/Flutter/Generated.xcconfig` = 1.6.15+71，Info.plist 用 `$(FLUTTER_BUILD_NAME)`，pbxproj 无硬编码）。`flutter build ios --release --no-codesign` 的 Xcode 编译能过，但 CLI 末尾 ad-hoc 签 Flutter.framework 失败（`identity -`，是 --no-codesign 自身怪癖，不影响 Xcode 真机 Archive）。用户本人在 Xcode `Runner.xcworkspace` → Clean Build Folder → Any iOS Device → Archive；遇 resource-fork 报错先 `xattr -cr build/ ios/Pods ~/.pub-cache`。
- 提交信息：包名 `com.birdflash.bird_flashcard`；ICP 粤ICP备2026057758号-2A；隐私 `https://birding.today/privacy.html`、支持 `https://birding.today/support.html`。App Store 6.5吋截图（1242×2688，无 alpha）在 `~/Downloads/预览/AppStore_6.5/`。
- 1.6.13~1.6.15 期间用户(oastwy)与接手者在同一分支交替提交（如 `60b5e1b ui: polish home/news`），**先 `git pull`/看 log 再动手**。

### 本次会话已完成（客户端，分支上）
- 闪卡：频谱图随 call/song 切换更新；预习页多音频互斥；选择题选项在非全屏被压缩时消失 → 改可滚动 ListView+固定行高；中文鸟名截断 → 中文名优先；难度筛选只在图片模式显示。
- **call/song 拆卡（1.6.13）**：听声模式下多音频物种拆成多张卡，一卡一音频一频谱图。核心是新类型 `_DeckCard(species, audioIdx)`（见 `flashcard_screen.dart`），音频索引随洗牌/错题流转；频谱图缓存键含 audioIdx。
- 总览页：「正确率」→「已掌握」；四个统计卡片可点击跳转鸟种清单（`_StatSpeciesListScreen`）；打卡日历改按月排版。"总览"标题在 1.6.11 的 commit 已去掉（用户旧截图是更早的安装包）。
- 上传：鸟种/预习页上传改用与闪卡一致的 `InFlashcardUploadModal`；无 Token 时显示"仅本地不上传"黄条。
- **鸟种详情/预习页「编辑辨识特征」入口（2026-06-13）**：`bird_preview_screen.dart` `_buildFeaturesSection` 标题右侧加「编辑/添加」按钮 → `_editSpeciesFeatures(sp)`，弹框复用闪卡那套（`storage.setSpeciesNote` + 管理员「保存并推送」走 `AdminUploadService().uploadIdentificationFeatures`）；空特征时也显示占位+「添加」入口。

### 本次会话已部署（服务器，**已上线生效**）
- **反馈/纠错 API**：`POST /api/feedback`、`GET /api/admin/feedback`、`POST /api/admin/feedback/resolve`（修复纠错审核 404）。
- **APK 国内直连**：`/data/download/` + nginx `location /download/`（443 vhost）+ download.html 主按钮指向 `https://birding.today/download/Birdaholic_vX_android.apk`。
- 服务器部署细节与回滚方式见 `docs/deploy_v1.6.12.md`。**仓库的 `server/upload_server.py` 已与线上同步**（含 `_compress_image` + 反馈端点），不再是旧版。
- **世界名录（1.6.15）**：`server/gen_checklists.py` 用 eBird（国家→省 subnational1→spplist）+ `world_birds.json` 生成 `/data/checklists/{地区}.json`（**精简格式：只存 eBird code 数组**，客户端用内置 world_birds.json 还原名字）+ `_index.json` 目录树。已全量跑完 **251 国 / 3442 地区 / 18MB**，nginx `location /checklists/` 服务。地区中文名表 `server/region_names_zh.json`（250 国 + 34 中国省，中文优先英文兜底）。客户端 `checklist_service.dart` + 数据包页「名录服务器下载」弹窗（中国完整/分省/**世界**）。重跑/补：`python3 /data/server/gen_checklists.py --key <eBird key>`（断点续传），再 `compact_checklists.py` 瘦身。
- **访问统计 GoAccess**：`https://birding.today/_stats/`（basic auth，账号 `birdadmin`，密码找用户/在服务器 `/etc/nginx/.htpasswd_stats`）。中文界面、`--ignore-crawlers` 去爬虫。`/usr/local/bin/refresh_goaccess.sh` + `/etc/cron.d/goaccess_refresh` 每小时刷新。
- 国内下载 `/download/`、世界名录 `/checklists/`、统计 `/_stats/` 三个 location 都加在 **443 vhost `birding.today.conf`**；改 nginx 用"备份+`nginx -t`+失败回滚"的小 python patcher（参考本次做法）。

### 仍待办
- [ ] **数据包断点续传「继续下载」按钮**（用户报：数据包没下完会停，需手动续）：`DownloadTaskService`（单例 ChangeNotifier，单任务锁 `_runningTask`）已有任务状态；需在数据包管理页（`pack_manage_screen.dart`）对「未完成/中断」的包显示「继续下载」按钮，复用原下载入口、跳过已下文件。
- [ ] **eBird 打卡筛选加时间筛选**（用户提）：eBird API 支持拉近 1–30 天（`/data/obs/{region}/recent?back=N`）和历史某天（`/data/obs/{region}/historic/{y}/{m}/{d}`）。当前 `_applyEBirdDeckFilter`（`flashcard_screen.dart:1082` 附近）只拉默认近期；加「近 N 天 / 指定日期」选项。
- [ ] **eBird 地点筛选持久化 + 历史地点**（用户提）：现每次打开重置，按热点筛选要重输 hotspot ID。需把上次选的地区/热点存 SharedPreferences，并维护一个「最近用过的地点」列表供下拉选。
- [ ] iOS Xcode Archive 上传 App Store（用户本人，见上版本块）。
- [ ] 国内安卓商店逐家上架（华为/小米/OPPO/vivo/应用宝）——无官方批量；注意多数要**软著**；个人 ICP 非商业，官网下载可作主渠道。
- [ ] 频谱图美化（已和用户讨论，**结论：不做 app 选样式的着色器**，第一性原理上只需"高对比+干净坐标轴"一张好图；服务器侧重生成尚未做）。
- [ ] eBird 邮件授权存档。
- ✅ 已完成（勿重复）：build.gradle.kts 已删；APK 去 x86_64（abiFilters）；世界名录 + GoAccess 已上线（见下）。

### 关键环境/凭据（本次验证可用）
- SSH：`ssh root@124.223.101.188` 用本机 `~/.ssh/id_rsa`（已在 known_hosts，连通正常）。
- `gh` 已登录 `oastwy`，可发 Release。Android 签名 keystore + `android/local.properties` 就位，release 构建出 `CN=Birdaholic` 证书。

### ⚠️ 本次踩的新坑（务必注意）
- **`" 2"` 重复垃圾文件会让 APK 翻倍**：构建出 130MB（正常 75MB），查出 build 缓存里有 160 个 `china_common_100_..._opt 2.zip` / `libapp 2.so` 之类重复文件（macOS/iCloud 同步或并行构建产生）。**打包前先 `find . -name "* 2.*"` 检查，或直接 `flutter clean` 再构建**。还删了个 `ios/Podfile 2.lock` 垃圾。
- **难度筛选"无效"是数据问题**：数据包 108 张图几乎全是难度 1，需在服务器给图片打难度分才有区分（代码没问题）。

---

## 1. 这是什么

- **产品名**：鸟瘾综合征（英文 Birdaholic）
- **类型**：鸟类识别闪卡（图片认鸟 / 听声认鸟），面向观鸟爱好者
- **平台**：iOS + Android（同一套 Flutter 代码）
- **法律主体**：伍洋（个人 ICP 备案，**非商业**）
- **备案号**：粤ICP备2026057758号-2A
- **仓库**：`/Users/wuyang/Documents/bird_flashcard_repo`，GitHub `github.com/oastwy/Birdaholic`
- **当前版本**：线上 `1.6.12+68`，本地分支已到 `1.6.13+69`（详见第 0 节）。改版本号 `pubspec.yaml` 与 `lib/app_version.dart` 两处都要同步改

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

- **接手第一件事：读第 0 节**（当前版本/分支/部署状态/待办/新坑）。
- flutter 用全路径 `/Users/wuyang/.flutter-sdk/bin/flutter`
- 改完 `flutter analyze --no-pub` 必须 0 issue
- **提交/推送/部署前问用户**；不要生成 `" 2"` `" 3"` 之类重复垃圾文件。
  **打 APK 前先 `find . -name "* 2.*" | grep -v build` 或 `flutter clean`**——本次就因 build 缓存里的 `" 2"` 重复文件把包从 75MB 撑到 130MB。
- 改 `upload_server.py` 前先确认 `_compress_image` 和合规入口没被覆盖；仓库副本现已与线上同步，但部署仍优先"往线上文件插入"而非整文件覆盖（见 `docs/deploy_v1.6.12.md`）。
- 改隐私政策内容 → 同步 bump `kPrivacyPolicyVersion`。
