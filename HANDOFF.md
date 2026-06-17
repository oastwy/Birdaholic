# Birdaholic / 鸟瘾综合征 Handoff

最后更新：2026-06-17  
项目路径：`/Users/wuyang/Documents/bird_flashcard_repo`  
当前 App 版本：代码观测为 `1.6.16+73`（以 `pubspec.yaml` / `lib/app_version.dart` 为准）

## 一句话目标

鸟瘾是 Flutter 鸟类闪卡 App：用本地/服务器数据包管理鸟图和鸟鸣，按 eBird 地点筛出附近鸟，用学习/复习/选择题进行训练。另有一个 Mac 本地 OSEA 批量鸟图识别工具，用于管理员整理照片。

## 0. 当前状态（2026-06-17，接手先读）

### 版本与工作树

- 当前代码观测：`pubspec.yaml` = `1.6.16+73`，`lib/app_version.dart` = `1.6.16` / build `73`。
- 当前分支：`feature/v1.6.12-bugfixes-ui`；最近 HEAD 观测为 `bbf2185 1.6.16：发现页改版 + eBird 筛选增强 + 名录跨包复用 + 运营后台`。
- 工作树是脏的，且有用户 / Claude / Codex 交错改动。**不要 reset，不要整文件覆盖。**
- **🔀 会话分工（2026-06-17 用户确认，已更新归属）**：
  - **Claude「主会话」= App 代码 `lib/` ＋ birding.today 后台（`server/`、`/data/server` 运维）**。Codex 原先的 App 代码工作已由用户转交此会话；**Codex 不再改本仓库代码**。
  - **另一个 Claude「数据包会话」= 数据包 / iNat 补图线**（`packager/backfill_*`、`birdaholic_inat_top100_review`、review 包）。
  - **「App 打包/发布线」= 编译与发版**（`flutter pub get` / test / `build ipa`·`build apk` / 版本号 / iOS archive）。它消费主会话的 `lib/` 代码 + 数据包会话产出的内置包 zip，不改业务代码。接手指南见本节末「🚚 转交 App 打包/发布线」。
  - 边界：数据包会话**不碰 `lib/`**；主会话**不碰 `packager/backfill_*`**。同步 `backfill_inat_photos.py` 到服务器前先 diff，保留补图审核闸门（`review_mode`/`backfill_review`/`pending_reason`）。三方共用本 HANDOFF 对齐。

### 🚚 转交「App 打包/发布线」（2026-06-17，接手先读这段）

**就绪状态**：App 代码改动（v1.6.16 各功能 + 闪卡署名 `@作者·地点·时间` + 内置包换 v2.0）已 commit 进 `d95ba72`；`flutter analyze --no-pub` 通过 **No issues**。

**⚠️ 头号坑：内置包 zip 不在 git**。`.gitignore:48 data_packs/*.zip`（仅 v1.0 例外）——`china_common_100_v2.0_opt.zip` 是**构建产物**，干净检出里没有。打包前必须确认它在位：
- 本机已有 `data_packs/china_common_100_v2.0_opt.zip`（45MB）。
- 若缺失/要更新：跑 `/opt/anaconda3/bin/python3 packager/build_pack_from_review.py` 从 review 包重生成（需 `birdaholic_inat_top100_review/extracted_pack` 在位，那是数据包会话产物）。
- **该生成脚本 `packager/build_pack_from_review.py` 目前还未提交**——建议先 commit 它，打包线才能复现内置包（zip 本身仍不入 git）。

**打包/发版步骤与坑**：
1. `flutter pub get`。
2. 测试**必须用** `/Users/wuyang/flutter-ohos/bin/flutter test --no-pub`；**别用** `.flutter-sdk`(3.29.3) 跑 test（会 `CupertinoDynamicColor` 编译失败，是 SDK 错配非代码 bug）。
3. 版本号：当前 `pubspec.yaml` `1.6.16+73` / `lib/app_version.dart` `1.6.16`；发版前 bump（两处同步，别回退）。
4. iOS：`/Users/wuyang/.flutter-sdk/bin/flutter build ipa --release`。Xcode 26 beta、iOS 26.5 SDK 需先下（~8.5GB）；`ios/Pods/Manifest.lock` 缺就进 `ios` 跑 `pod install`；`Generated.xcconfig` 被重置时核版本号；`ITSAppUsesNonExemptEncryption=false` 别丢。
5. Android：`flutter build apk --release`（已只保真机架构，APK ~63.9MB）。
6. **换包影响**：内置包 `dirName` 已升到 `china_common_100_v2`，老用户首次启动会自动重解压换成新 100 种包（带地点/时间），发版说明可提一句。
7. 提交时排除大目录：`.birdnet_engine_venv/`、`dist/`、`server_media_library/`、`upload_batch/`、`data_packs/*.zip`。
- `AGENTS.md` 和 `CLAUDE.md` 均为指向 `HANDOFF.md` 的符号链接；更新本文件即可让 Codex / Claude 共用同一状态。
- `docs/handoff_app.md` 仍有 1.6.15 与更旧版本混杂内容；接手时以代码、git log、本节为准，再同步清理旧 handoff。

### 当前未提交改动概览

已观测到这些功能线有本地改动，需先验收再继续加功能：

- 首页 / 总览：`progress_screen.dart` 有更新通知 banner 关闭按钮等改动，但用户仍反馈首页 UI 难看，需要继续做视觉收口。
- 资讯页：`news_screen.dart` 已有入群二维码入口和服务器发现页内容拉取；但二维码还需要支持点击放大、保存 / 下载，方便去微信扫码。
- 设置页：`settings_screen.dart` 已加入“申请上传权限”“反馈与通知”“检查版本更新”等入口。
- 反馈回复：`admin_upload_service.dart` / `settings_screen.dart` / `server/upload_server.py` 已接入 `client_id` 与 `/api/feedback/replies`，需要端到端验证匿名用户同机可收回复。
- 上传权限申请：App 与服务器已有 `/api/token_requests`、审核、回传 token 的雏形；需验证不收集手机号/微信/邮箱/姓名，隐私政策 `kPrivacyPolicyVersion = 1.1` 已 bump。
- eBird 筛选：闪卡与数据包下载页已有时间筛选、指定日期、经纬度输入相关改动；需明确 UI 文案：recent 最多 1-30 天，超过 30 天只能指定历史某一天或另做本地聚合。
- 答题统计：`flashcard_screen.dart` 已加 `_answeredCardKeys` 防重复计数，需真机验证“10 题对 6 错 7”不再出现。
- 后台：`server/admin.html` 新增统一后台页面，`server/upload_server.py` 新增 `/admin`；需确认是否已部署到 `https://birding.today/admin`。
- 上传地点：App 上传、闪卡内上传、服务器 `/api/upload`、审核列表已出现 `location` 字段，需验证批准后 manifest 保留地点。
- 难度管理：App / 上传 / 预习 / 闪卡已有图片难度相关代码，需确认后台媒体管理是否也满足用户“闪卡里面的难度管理”预期。
- 服务器媒体管理：`server_media_manager_section.dart` 已有清除选中物种的 `_clearSelection()`，需在 UI 上确认 X 号可见、好用。
- **闪卡图片署名改版（主会话 2026-06-17，已 analyze 通过 No issues）**：`lib/models/species.dart` 给 `SpeciesImageInfo` 加 `location`/`date` 字段（fromJson 兼容 `observed_on`）；`lib/widgets/bird_card.dart` 的 `_ImageEntry` 加 `contributor`/`location`/`date` 并透传，图片下方由 `© {长串credit}` 改为 `_imageCaption()` 拼的 **`@作者 · 地点 · 时间`**（缺的省略、作者优先用干净 contributor、`maxLines:2`+省略号）。预习页 `bird_preview_screen.dart` 暂未统一（待用户定）。
  - **地点/时间数据已解决**：新内置包 v2.0 直接从 review 包打（见下条），review 图自带 location/date，所以 iNat 图的 `地点·时间` 已随包进 App、会显示；用户上传图仍无地点/时间（上传未采集）。若将来改回用 `build_china_common_100_pack.py` 从服务器 manifest 打包，才需要数据包会话补：① 服务器 `backfill_locations.py` 回填、② `build_image_entries` 拷 `location`/`date`。
- **新内置包 v2.0（主会话 2026-06-17，已接入、analyze 通过）**：用户要"重做一版全国新手常见100取代现有内置包"，名单+图取自 8787 人工 curate 的 review 包。
  - 新脚本 `packager/build_pack_from_review.py`：**从 `birdaholic_inat_top100_review/extracted_pack/` 直接转**成 App 包（不重拉服务器，保住人工删图/排序/打星/换种/用户图优先）；只打 species.json 引用到的媒体（去孤儿）、图片缩≤1280 + JPEG q80 重压、写 App 版 manifest（去 `review_only`）、并同步重写 `assets/data/china_common_100.json` 名单。**review 继续 curate 后重跑此脚本即出新包。**
  - 产物 `data_packs/china_common_100_v2.0_opt.zip`（**44.6MB**，100 种 / 289 图(205 带地点) / 168 音频）。
  - 接入：`pubspec.yaml` 资产改 v2.0；`pack_manager.dart` `assetPath`→v2.0、`dirName`→`china_common_100_v2`（**升 dirName 强制所有用户重解压换包**）。
  - 旧 `china_common_100_v1.2_opt.zip`（43MB）已不再被引用，可删（暂留未删）。
  - ⚠️ 这是 2026-06-17 当时 review curate 状态的**快照定稿**；如继续 curate，重跑脚本 + 不用再改接入即可更新。

### 待优先收口的问题（数据包以外）

1. 首页 UI 继续收口：减少零状态时的空旷和笨重感，四个统计卡保持一行，首页只保留核心学习动作、统计、日历、复习建议。
2. 资讯页入群二维码：放在资讯页，点击可大图查看，并提供保存 / 下载二维码。
3. 反馈与通知：验证匿名同机反馈、token 用户反馈都能收到管理员回复；旧匿名反馈无法回达要在 UI 里说清。
4. 申请上传权限：验证普通用户无 token 时能提交匿名申请，后台批准后 App 自动保存 token。
5. 后台统一页面：验证 `/admin` 的上传、待审核、纠错审核、权限申请、用户密钥、发现页运营、媒体统计均可用。
6. eBird 时间 / 经纬度筛选：验证近 N 天、指定历史日期、经纬度半径筛选与数据包下载路径都能正常工作。
7. 统计计数 bug：验证选择题和滑动答题不会重复计数。
8. FileBrowser：用户反馈 `https://birding.today/filebrowser` 看不了，需检查 nginx `/filebrowser` 与 `/filebrowser/` 路由、baseurl、服务状态。

### Codex 2026-06-17 给 Claude 的 App 收口补充

- 用户明确要求：App 相关修改要继续记录在本文件，`AGENTS.md` / `CLAUDE.md` 是到 `HANDOFF.md` 的双向入口；不要另起零散 handoff。
- 当前版本以代码为准，已不是早先口头说的 1.6.13；接手先核 `pubspec.yaml` / `lib/app_version.dart`，不要回退版本号。
- 首页仍是用户最不满意的 App UI 点：当前零状态首页显得空、笨重。继续收口时优先处理：顶部主按钮比例、统计四卡单行文字、日历卡视觉密度、复习建议空状态，不要再把播客/更新通知塞回首页。
- 资讯页方向已确认：入群二维码放资讯页，二维码图片可点击放大，并提供保存/下载，方便用户去微信扫码；鸟瘾综合征最新一期、更新通知、志愿者招募、鸟讯集中到资讯页。
- 设置页方向已确认：闪卡设置放二级界面；设置首页保留入口；版本/检查更新放到设置页底部；隐私政策、用户协议、声明致谢入口不能删。
- 反馈与通知：后台已有回复能力，App 端需要继续验证/完善“我的反馈/通知”界面；匿名同机反馈依赖 `client_id`，真正无身份历史匿名反馈无法回达，要在 UI 文案中讲清。
- 上传权限申请：保持低门槛，不收手机号/微信/邮箱/姓名；普通用户提交申请到后台审核，批准后 App 自动保存 token。这个设计当前判断不等同于用户注册，但隐私政策要继续同步。
- eBird/经纬度筛选：用户需求是打卡和下载都能按时间长度/指定日期/经纬度筛选；官方 recent API 只适合 1-30 天，超过 30 天要用指定历史日期或本地聚合方案，不要误写成官方 recent 可自定义超过 30 天。
- 闪卡统计 bug 要继续真机验：同一张卡重复滑动/选择不能造成 10 题出现对 6 错 7。
- 鸟种页交互已确认：点击鸟图本身进入详情/大图，右上角放大按钮可保留但不能是唯一入口。
- 服务器媒体管理：用户要物种选择后有清晰 X 号可一键清除；难度管理、用户图优先、署名/许可显示都要在后台和 App 两边保持一致。

### 验证状态

- 曾尝试运行 `/Users/wuyang/.flutter-sdk/bin/flutter analyze --no-pub`，长时间停在 `Analyzing bird_flashcard_repo...`，已中断，未拿到结果。接手第一步请先重跑 analyze；如果仍卡住，查 `.dart_tool`、Flutter 缓存或改用更窄范围分析。
- 不要在 analyze 未完成前打包、推送或部署。
- **2026-06-17（Claude 复跑）**：`analyze --no-pub` 跑完了，约 191s，**No issues found**（之前那个 dead null-aware warning 已不存在）。
  - **测试工具链坑**：`flutter test` 必须用 **`/Users/wuyang/flutter-ohos/bin/flutter test --no-pub`**。`.dart_tool` 依赖按 flutter-ohos 解析，若用 `.flutter-sdk`(3.29.3) 的 Dart 去跑 test 会编译失败（`CupertinoDynamicColor` 缺新版 `Color.toARGB32`）——这是框架/SDK 版本错配，**非代码 bug**。用 flutter-ohos 链：**全套 10 测试通过**。
  - 新增 `test/pinyin_test.dart`、`test/species_test.dart`（拼音首字母 + Species 序列化/难度）。

### 独立数据包线（不要混入 App 收口）

- `/Users/wuyang/Documents/New project/birdaholic_inat_top100_review` = 中国常见 100 种开源许可图片重建（review 候选包，review_only，不直接进 App）。
- **2026-06-17 进展**：开源图重建已跑完（`DONE image_count=300 lacking=0`，报告/zip 已出）。在此之上由 Claude 做了一轮**增量换种 + 用户图排前**（保留已有人工删图记录，未碰生产服务器；删除数实时变动，见 `review_delete_state.json`，14:54 时为 16 条且仍在增加）：
  - 候选清单 `build_inat_top100_review_pack.py` 的 `INAT_TOP_100` 换 3 种：换出 鸿雁/凤头鹰/普通秋沙鸭，换入 绿鹭/噪鹃/针尾鸭（就地 1:1，带"替补"备注）。
  - `apply_review_swap.py`（新增，增量）：删 3 旧种+其图、从服务器拉 3 新种图注入 extracted_pack，重打包+重生成 review.html/清单。
  - `merge_user_upload_images.py`：把已在 100 里的物种用户图排到首图，本轮改 17 种/28 图。**加了一处兜底**：空许可的 `birdaholic-upload` 用户图按 CC BY-NC 4.0 处理（与 11:03 服务器 pica 许可回填同政策）——否则那 6 种空许可用户图会被白名单挡掉。许可政策详见 Codex note `~/.codex/memories/.../20260617-...-birdaholic-user-upload-license-policy.md`。
  - 当前 review 包：100 种 / 290 图 / 168 音频，`review.html`+`v0.1.zip` 已同步（2026-06-17 11:43）。
- **⚠️ 两份清单差 36 种**：App 内置包 `data_packs/china_common_100_v1.2_opt.zip`（由 `packager/build_china_common_100_pack.py` 的 `COMMON_100` 生成）与 review 的 iNat-top-100 只重合 64 种。换出的鸿雁/凤头鹰/普通秋沙鸭 **只在 iNat-top-100，App 包没有**。本轮**只更新了 review 包**；App 内置包是否对齐/换种**由用户手动处理**。
- 绿鹭用户图已解决：那 3 张被归到**异名目录 `Butorides_atricapilla`**（cn 也叫"绿鹭"，是 `Butorides striata` 的拆分/异名）。已拉入 review 包 striata 条目排前（CC BY-NC 4.0，致谢 虾虎鱼/pica，上传者 海盗观鸟团）。**分类重名坑**：服务器名录里 `Butorides_striata` 和 `Butorides_atricapilla` 两条都叫"绿鹭"，用户上传落到了 atricapilla；服务器侧若要合并去重由用户手动处理。
- 清理：本轮顺手删了 `extracted_pack/images/` 下 52 张历次 merge 替换遗留的孤儿图（未被 species.json 引用）；删图备份 `_review_deleted_images/` 未动，15 条删除记录仍可恢复。
- **⚠️ 主会话 2026-06-17 越界改动交接（数据包会话接手前先看）**：分工确立前，主会话在 review 包里动过这些，**现状无冲突、改动均已落盘**，但归属应转回数据包会话：
  - `review_delete_server.py`：① 把"站内已有"标签并入 `inaturalist`（48 张全是 iNat，无管理员手传，已核）；② 删除记录从主页内嵌**拆成独立 `/deleted` 页**（带缩略图+撤销），主页工具栏改为「删除记录(N)」入口。**当前 8787 跑的就是这版（PID 由主会话重启）**；数据包会话要改此文件前先 `diff`，别回退这两处。
  - `apply_review_swap.py`（主会话新增）+ `merge_user_upload_images.py` 的空许可兜底改动：见上文换种/merge 记录。
  - review 包数据（换种+用户图+绿鹭+孤儿清理）已是最新；14:54 后的删除是数据包会话/用户通过该服务继续操作，实时状态以 `review_delete_state.json` 为准。
- 除非用户明确要求，不要把这个任务和 App UI / 后台问题混在同一轮处理。

## 当前状态（旧记录，保留作历史）

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

## 与 birding.today 后台对接（2026-06-16，服务器端已就绪，待 App 接入）

> 这几项的**服务器端已在 `124.223.101.188:/data/server/upload_server.py` 写好并上线**，只差 App 端调用/加界面。
> App 基址沿用 `http://124.223.101.188:8080`（nginx 已把 `/api/` 反代到 FastAPI :8000，`/species/` 也在 8080）。
> 后台/服务器侧细节见 birding-today 项目 handoff：`/Users/wuyang/Projects/birding-today/HANDOFF.md`。

1. **上传界面加「地点」字段**
   - `POST /api/upload` 已新增可选表单字段 `location`（字符串，≤200 字）。App 上传界面加一个"地点"输入框，提交时带上 `location` 即可；服务器会写进该图/音频条目的 `location`。无需改服务器。

2. **上传/选中物种时显示该种已有图片+音频**（避免重复上传）
   - 拉 `GET /species/<学名空格转下划线>/manifest.json`（如 `Troglodytes_troglodytes`），读 `images[]`/`audio[]`（过滤 `pending==true`），渲染缩略图/播放器。条目 `url` 是 `http://...:8080/...`，App 直接用即可（非 https 页无混合内容问题）。

3. **识别测验出题日志**（方案 A：用于定位有问题的题/图）
   - App 在**答错或用户点"这题有问题"时** `POST /api/quiz/log`，JSON：
     ```json
     {"sci":"正确种学名","image":"images/xxx.jpg","options":["选项1","选项2"],
      "correct":"正确项","chosen":"用户所选","is_correct":false,
      "reported":false,"mode":"题型(可选)","client":"android 1.6.x(可选)"}
     ```
   - 软鉴权：带用户 token 会记 `uploader_id`，匿名也可。后台「测验题目」页按"举报+答错"汇总问题图。建议只在答错/被举报时回传，别每题都发。

4. **纠错回复显示给用户**
   - 用户在 App 提交纠错后，管理员会在后台回复；App 加「我的反馈/通知」拉 `GET /api/feedback/replies?token=<用户token>`，返回 `items:[{id,message,reply,replied_at,species_cn,species_sci}]`（只返回该用户、且已被回复的）。匿名反馈无法回达。

**另外（无需 App 改动，自动受益）**：`/api/search` 已升级——结果按匹配精确度排序、去掉 20 条上限（→300）、支持拼音首字母与全拼（如 `jl`/`jiaoliao` 搜"鹪鹩"）。App 若用此接口做物种搜索，重启服务后即生效。

## iNaturalist 补图任务（2026-06-16，进行中）

为每个物种补到 3 张图（多补 1–2 张），iNat 图展示优先级低于用户上传图。

- **脚本**：`packager/backfill_inat_photos.py`（已同步到 `root@124.223.101.188:/data/server/`）。本次改动：
  - **只收开源安全许可** `OPEN_LICENSES = {cc0, cc-by, cc-by-sa}`（排除 NC/ND——NC 与开源 app 商用/fork 冲突，ND 与缩放=演绎冲突）；空/保留所有权利一律剔除。
  - 压缩改用 **Pillow**（服务器无 `sips`），长边 1600px、质量 72。
  - 写回 manifest 前**稳定排序**：`source==inaturalist` 永远排在用户上传图之后。
  - 修复 `refresh_index()`：写**裸列表**（与 `upload_server.update_index()` 一致，`image_count` 只数非 pending），原先写 dict 会破坏 App 消费的索引格式。
- **回溯清理**：`packager/cleanup_noncc_backfill.py` 删除了早期跑批加进去的 67 张 NC/ND 图（39 个物种，只删文件名含 `_inat_` 的补图，原图不动），并重建索引。
- **替换原始图版权问题（第二阶段，进行中）**：原始抓取主图里 1,579 张"保留所有权利"+ 7,542 张 NC/ND（仅 1,702 张 CC0/BY/SA）。脚本新增 `--purge-nonopen-inat`（删非开源 iNat 图并换成 CC0/BY/SA）+ `--compress-existing`（超 1600px/600KB 的存量图才压，避免重复降质）。用户上传图（source != inaturalist）一律不动。
  - **非破坏性保证**：只有在"已拿到替代图"或"API 确认该种无开源图"时才删非开源原图；网络失败则保留原图、下轮重试——绝不因网络抖动把物种删空。
  - **网络瓶颈**：服务器（腾讯云·国内）→ iNat 跨境严重限速（API 单次可达 90s、下载 ~17KB/s/连接）。已加全局 socket 超时 + 单图失败跳过 + `--workers` 并发（16 路）。实测并发只提速 ~3x（≈1.1 网络型物种/分钟，疑似总带宽封顶），全量预计数天。
  - **运行**（当前用并发版，见 `packager/restart_backfill.sh`）：`setsid bash /data/server/restart_backfill.sh </dev/null >/dev/null 2>&1 &`（内部会先杀旧 python 再起，含 `--workers 16 --purge-nonopen-inat --compress-existing --timeout 20`）。脱离会话、按物种写状态、可续跑。
  - 监控：`ssh root@124.223.101.188 'tail -f /data/inat_backfill.log'`；崩溃/重启后重跑 restart 脚本即可。
  - **动手前已全量备份**：`/data/backups/manifests_<ts>.tar.gz` + 索引 + 旧状态。
  - **提速备选（plan B，待用户资源）**：跨境限速是根因，最优解是在境外/连通性好的机器上跑下载+压缩，再把图同步回服务器（域内传输快）。需用户提供境外机或确认 Mac 的 iNat 通路。
  - `packager/backfill_guard.sh`（自愈 cron 守护）已上传 `/data/server/` 但 cron 未装（权限拦截）；需无人值守可手动 `*/15 * * * * /data/server/backfill_guard.sh`。
- **图片地点信息**：iNat 观测自带 `place_guess`（地名，多为英文/当地语）+ `location`（`lat,lng` 坐标）+ `observed_on`（日期）。
  - 新下载的图：`inat_candidates()` 已带出这三项，写进 manifest 条目的 `location` / `coords` / `observed_on`。
  - 存量图（pass1 加的 6645 张 + 保留的开源原图）：用 `packager/backfill_locations.py` 按 obs_id 批量补（iNat 一次查 200 条观测，~10k 图仅 ~50 次请求）。**必须在图片 backfill 停止时跑**，避免两进程同时写 manifest。计划在补图收敛后跑一遍。
- **补图审核闸门（Claude 加，2026-06-17，勿删）**：脚本读 `manifest["backfill_review"]`，为真时**新补的图标 `pending=True` + `pending_reason="backfill_review"`**，只进后台「待审核」、人工通过后才上线。配套逻辑在 birding.today 后台 `upload_server.py`（删空物种打标记、审核通过清标记）。
  - ⚠️ 协作提醒：此脚本两份（本 repo `packager/` 与 `124.223.101.188:/data/server/`）。**2026-06-17 发现 Codex 重新同步时把这段 review 逻辑覆盖过一次**，已重新加回。今后同步前请先 `diff`，保留 `review_mode`/`backfill_review`/`pending_reason` 三处。
- **未提交 git、未改 App**；脚本改动 + `cleanup_noncc_backfill.py` / `restart_backfill.sh` / `run_backfill_v2.sh` / `backfill_guard.sh` / `backfill_locations.py` 待 commit。

## 最近 analyze 结果（2026-05-16）

```
exit code 0
1 warning（dead_null_aware_expression，无影响）
```
