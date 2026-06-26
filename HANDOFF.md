# Birdaholic / 鸟瘾综合征 Handoff

最后更新：2026-06-26  
项目路径：`/Users/wuyang/Documents/bird_flashcard_repo`  
当前 App 版本：**`1.7.0+86`**（以 `pubspec.yaml` / `lib/app_version.dart` 为准；用户要求从 1.6.27 改名升 1.7）。**安卓包已打、用户已测过、待发布到 GitHub Release + birding.today**：
- 安卓 `releases/Birdaholic_v1.7.0_android.apk`（71.7MB / vc86 / sha256 见 `.sha256`）。
- **鸿蒙 1.7.0 .app 未打**（用户本轮只要 github+birding.today；要上 AppGallery 时照下「鸿蒙配方」打，bump ohos/local.properties 到 1.7.0/86 即可）。
- **环境为鸿蒙态**：pubspec overrides 反注释 + `android/local.properties` flutter.sdk→flutter-ohos + `flutter-ohos pub get`（lock audioplayers 回 ohos fork）。
- **服务器 `upload_server.py`（含审核通知 + 安全/正确性修复）已部署 124.223.101.188 并实测**，备份 `.bak_20260626_173246` / `.bak_20260626_210912`。
- ⏳ **收尾中**：commit+push main → 建 GitHub Release v1.7.0（挂 APK）→ 更新 birding.today `download.html` 到 1.7.0。

## ✅ v1.6.27 已打包待发版（2026-06-26，全量 analyze No issues；服务器已部署实测）

本版一次性带上：①「中国观鸟记录中心」导入 + 跨分类同义词映射；② 安全审查 S1–3 + code-review C1–14 修复；③ 用户口述 6 条待改；④ 新手教程同步更新（点鸟名进「了解此鸟」、今日听声挑战位置、记录中心导入说明）。**安卓 + 鸿蒙两包均已打**（见顶部）。**细节见 [docs/CHANGELOG.md](docs/CHANGELOG.md)**，下面只留要点：

- **6 条待改（全做进本版）**：① 详情页(`progress_detail_screen`)与主页「学习概览」重复的 6 张统计卡 → 删详情页那组，主页那套(可点进清单)留作唯一入口；② 「今日听声挑战」移到打卡日历**上方**(`_soundChallengeCard`)；③ 删「学习周报」(tile + import + `weekly_report_screen.dart` 文件)；④ **【合规】闪卡音频致谢**——根因是**正面(听音频那面)无致谢行**(数据/back 侧正常)，已给 `_buildPromptFront` 音频分支补 `_creditLine`；⑤ 答案侧「了解此鸟」按钮删除、`_difficultyRow` 用 `FittedBox` 兜底防溢出；⑥ 答案侧中/英/拉丁名包成可点 → `onLearnMore`(带「轻点名字·了解此鸟」提示)。
- **服务器 `upload_server.py`**：S1 `species_key()` 加路径穿越校验(一处覆盖全部写入点)；S2 `set_difficulty` 收成 `_require_admin`；C6 `admin_rate_resolve` 记录先删后应用+catch 404；C8 回达跳过 pending；C10 difficulty 安全解析；C11 评级队列缓存加单飞锁。**已部署 124.223.101.188，curl 实测：路径穿越→400 / 无token→401 / rate-queue admin→200 全过**，备份 `.bak_20260626_173246`。
- **App 修复**：C1 对账删除用含 pending 的 `allImages/allAudio` 防误删本地图；C2/C3 `_imageEntriesFromItem` 无损 + `_setCoverFromEntry` 同步 source/license（合规·防署名丢失）；C4 新地点也重置「可能性」；C5/C7/C9 xlsx/CSV 导入解析加固；C13/C14 eBird URL 编码+按日期排序。**C12（对账兄弟图保活漏删）有意不改**——良性失败，收紧匹配反招「误删本地文件」数据丢失。
- 记录中心导入 + 同义词映射详情见 CHANGELOG；同义词资产 `assets/data/taxonomy_synonyms.json`(208 键双向)。

> **⏳ 待用户定（未做）**：审核通过后给上传者发「已过审」通知（复用 relay 机制写 `/api/feedback/replies`，纯服务器改，只对真·App 用户上传发，守去社交）——已分析、未实现。

## Changelog

> 📜 **完整版本历史已抽到 [docs/CHANGELOG.md](docs/CHANGELOG.md)**（2026-06-25 拆分，给 handoff 瘦身）。本节只留**最新进行中**一条 + **近版一句话摘要**；查旧版细节看 CHANGELOG.md。**新版本细节追加到 CHANGELOG.md 顶部，这里只更新摘要。**

- **2026-06-26 — v1.7.0+86（1.6.27 改名升 1.7；安卓 `Birdaholic_v1.7.0_android.apk` vc86 已打+用户测过 → 发 GitHub Release + birding.today；鸿蒙 .app 待 AGC 再打；细节见 [docs/CHANGELOG.md](docs/CHANGELOG.md)）**：在 1.6.27 之上加三功能——① **物种难度筛选**（难度行扩成 物种+图片 两个下拉，物种难度两模式都生效、图片难度仅图片模式显示）；② **类群概览可点**（数据包目 Chip→该目鸟种预览）；③ **断点续传整包**（持久化意图清单，数据包管理「继续下载（还差 N 种）」补齐没下完的种，首页横幅失败/取消也有「继续下载」）。code-review 两轮修 G1/R1/F-a/F-b/F-c。
- **2026-06-26 — v1.6.27+84：安全审查+code-review 19 修 + 记录中心导入 + 同义词映射 + 6 条待改 + 教程更新（安卓 `Birdaholic_v1.6.27_android.apk` + 鸿蒙 `Birdaholic_v1.6.27_ohos_api22_release.app` 两包均已打、待发版；服务器 `upload_server.py` 已部署实测；细节见 [docs/CHANGELOG.md](docs/CHANGELOG.md)）**：服务器 S1 路径穿越/S2 鉴权/C6 待审卡死/C8 回达/C10/C11；App C1 对账防误删/C2-3 主图署名无损/C4 可能性重置/C5-9 导入解析/C13-14 eBird；6 待改=学习概览去重·听声挑战上移·删学习周报·音频致谢补正面·难度防溢出·鸟名可点跳转；记录中心 xlsx 导入 + 郑四↔AviList 同义词映射。C12 有意不改（防过删本地文件）。
- **2026-06-26 — v1.6.26+83：用户 4 项 UX（已打安卓包 `releases/Birdaholic_v1.6.26_android.apk` 71.7MB/vc83，待发版；细节见 [docs/CHANGELOG.md](docs/CHANGELOG.md)）**：
  - ① **打卡日历默认两周可展开整月**（`progress_screen._checkInCalendar`：新增 `_calExpanded`，默认收起成「最近两周」周一对齐 2 行，底部「展开整月」放大到完整月历+月份切换，展开自动跳回本月）。
  - ② **闪卡筛选页「地点筛选」改方框格式**（`InputDecorator`+`OutlineInputBorder`+`地点筛选` label，跟旁边「数据包」下拉一致），原 `OutlinedButton` 弃用。
  - ③ **「可能性」= 纯排序（整包保留）**：按用户确认，不筛掉任何种——整包都在、把该地区近 30 天 eBird 观测到的种排到前面（`_likelihoodRank` 命中的靠前，其余按名称垫底）。snackbar 报「已把…N 种排到前面」(N=本包与近期观测的重合数)。仅当**整包与该地区近期记录零交集**（排序无意义）时弹**非阻塞**提示 + 可选「去下载数据包」→ 跳 `PackManageScreen`，**不清空/不强制改顺序**。（注：曾先做成「交集筛选」，用户明确要保留整包→已改回纯排序。）
  - ④ **闪卡致谢渲染修复（合规）**：查实内置中国包数据 100/100 种、289 图全有署名（非数据问题）。`bird_card`：单图轮播也在图下显示 `_imageCaption`（空则兜底「图片感谢：物种级致谢」），`_creditLine` 简化为只管「音频感谢」——**单图/多图、正反面每张图都带致谢**，杜绝无署名。装新包即生效。
  - 全量 `flutter analyze` No issues；打包配方同前，打完已手动恢复鸿蒙。

- **2026-06-26 — v1.6.25+82：code-review(xhigh) 正确性修一批 + 服务器 #9/#10 收口（已打安卓包 `releases/Birdaholic_v1.6.25_android.apk` 71.7MB/vc82，待发版；细节见 [docs/CHANGELOG.md](docs/CHANGELOG.md)）**：
  - **App 8 处正确性修复（全量 analyze No issues）**：① 清除地点/切数据包后「可能性」排名不失效→牌组被旧地区排名静默排序：新增 `_resetLikelihoodOnContextChange()`，5 处（清除地点×3 + 切包×2）清 `_likelihoodRank`+若正按可能性则退回随机；② 两处**切包补 `clearEbirdFilter()`**，storage 地区码/经纬度不再残留到新包污染后续可能性；③ 删本地图后 **PageController 归位**（丢旧 controller、post-frame dispose、重建到第0页，消除越界/圆点错位）；④ **多图卡署名兜底**（`bird_card._imageCaption` 空署名回退物种级图片致谢，杜绝无署名图，合规）；⑤ 可能性排名 key 两侧统一 `StorageService.normalizeSci` 二名归一（eBird 亚种三名不再误排末尾）；⑥ 二维码长按改 await `launchUrl` 按结果提示，去掉「成功+失败」双弹；⑦ 新手模式建包失败**不写入模式**+提示，保留模式选择门不落空首页；⑧ `removeSpeciesImageFromActivePack` 改归一化匹配 sci。
  - **清理**：删死字段 `_taxonomicOrder`（按目筛选下拉早移除、永远 'all'，连带 `orderText` 8 处插值）+ 死持久化 `checkinConfigured`/key（已被 `_configuredThisLaunch` 取代）+ `_AdminTokenRequestsScreen._approve` 的 `TextEditingController` 补 dispose。
  - **服务器（已部署 124.223.101.188 + curl 实测，`/data/server/*.bak_20260626_093958`）**：① **#9** `/api/contributors` 加**单飞+双检锁** `_CONTRIB_CACHE_LOCK`——失效后只让一个线程扫全量 ~1.1万 manifest、其余复用，避免写后惊群把同步线程池耗尽（冷查回数据、热查 0.0016s）；② **#10** `admin.html` 反馈图缩略图加 `safeMediaUrl` scheme 白名单（客户端可控的 `image_url` 防 `javascript:`/`data:`/协议相对注入）。
  - 打包配方同前（注释 overrides + local.properties 指 .flutter-sdk + bump 1.6.25+82，打完手动恢复鸿蒙）。

- **2026-06-26 — v1.6.23+80：UX 大改一批 + 著作权合规（已打安卓包 `releases/Birdaholic_v1.6.23_android.apk`，待发版）**：
  - **【合规·要紧】音频署名补齐**：用户报"闪卡大量图/音频不显示致谢，版权风险"。查实=**数据缺口非渲染 bug**。服务器 495 条缺录音者的音频，用文件名 Xeno-canto 编号经 **XC API v3**（密钥 `/data/server/.xeno_key`）反查 录音者+许可+地点 回填 → 全库 17755 条 **100%**；内置中国包 66 条用服务器导出的 `xc_id→署名` map 补齐 → 168/168 **100%**（脚本 `scratchpad/backfill_audio_attrib.py`/`patch_pack_attrib.py`，内置包原档 `data_packs/china_common_100_v2.0_opt.zip.bak_attrib`，服务器 manifest 全量备份 `/data/backups/manifests_attrib_*.tar.gz`）。图片仅服务器 135 张(0.5%,远古无出处图)待收。详见 birding.today handoff。
  - **15 项 UI/功能**：① 鸟种页**长按删本地问题图**（新 `pack_manager.removeSpeciesImageFromActivePack`，删 species.json 条目+文件+改主图，即时刷新）；② eBird 地点筛选标签裸显代码(NO-03)→ 新 `EBirdService.fetchRegionName` 经 `/v2/ref/region/info` 转真实地名；③ **打卡进不去筛选 bug**：弃用持久化 `checkinConfigured`，改**本次启动**会话标志 `_configuredThisLaunch`（重启首次进筛选，之后打卡/复习都直接沿用上次；打卡/复习逻辑统一）；④ 图片卡 `_creditLine` 只显示「图片感谢」（音频感谢仅音频卡）；⑤ 首页 `progress_screen` 瘦身：删 今日目标/中国鸟选择题/建议优先复习+相应死方法/import，日历上移、连续天数加🔥；⑥ 闪卡筛选页 `_buildFilterPage`+练习中弹层重做：数据包+地点并列、学习/测试模式整行、判断题/选择题一行、音频/图片闪卡、去按目筛选、顺序改 随机/分类关系(`_order=='taxonomic'` 按 `BirdOrderTaxonomy.sortWeight`)；⑦ 发现页 `_showWechatSheet` 加关闭按钮+长按打开/保存；⑧ 设置审核合并到一级（审核组：内容审核/上传权限审批(原"申请"改"审批")/评级审核 + 管理员工具：逐种评级，新增 `_groupHeader`）；⑨ 设置分组（学习/账号与上传/帮助与关于）+ 删垃圾文件 `flashcard_screen 2.dart`。
  - **「可能性」排序（2026-06-26 追加，v1.6.24+81）**：eBird spplist API 只给"有没有"、无真·出现频率，故用 **eBird 近期观测**近似——`EBirdService.fetchRecentObsBySci(region)` 拉 `/v2/data/obs/{region}/recent`(近30天)、按 `obsDt` 倒序给学名排名；`_order=='likelihood'` 时按此排（未上榜的排后）。需先做过**地区代码**(非经纬度)的地点筛选(地区码存 `storage.ebirdFilterRegion`，`clearEbirdFilter` 同步清)+ 有 API Key，否则 snackbar 提示。两处顺序下拉(独立页+练习弹层)都加了「可能性（近期 eBird 观测）」。**仍是近似，非真频率。**
  - 逐文件 + 全量 `flutter analyze` 均 No issues。打包配方同前（注释 overrides + local.properties 指 .flutter-sdk + bump 1.6.23+80，打完手动恢复鸿蒙）。

- **2026-06-25 — 鸟种页图片加「反馈图片问题」按钮（带图片提交者身份；analyze No issues，待发版/后台配套）**：
  - `lib/screens/bird_preview_screen.dart`：`_buildPhotoPage` 图片右上角加半透明 `bug_report_outlined` 圆钮（点击不触发原「点图放大」，二者用 `Stack` 分层），新增 `_reportImageIssue(sp, img)` 复用 flashcard 那套 `storage.addFeedbackEntry` + `AdminUploadService.submitFeedback` 流程，`page='鸟种图片'`。
  - **「通过图给提交者反馈」走管理员中转（用户确认，守备案不做用户↔用户直连）**：反馈 `context` 带上这张图的提交者身份——`report_type=image / image_url / image_file / image_source / image_contributor / image_contributor_url`。为此给 `_PreviewImage` 加了 `contributor`/`contributorUrl` 两字段（服务器图取 `img.contributor/contributorUrl`，本地图取 `info?.contributor/contributorUrl`）。
  - **code-review 复查修 4 处（2026-06-25，已 analyze/部署/实测）**：① 后台 `/api/admin/feedback` 排除 `kind==image_relay` 出站通知（不再污染纠错列表）；② relay 按 `source_feedback_id` 去重（「再次回达」不再给提交者发重复）；③ App `_reportImageIssue` 改为 await+timeout(10s)，同步失败如实提示「已记录，但网络异常未能同步」（原来无条件报已提交）；④ 该方法 `TextEditingController` 现已 dispose。
  - ✅ **后台配套已上线（birding.today，2026-06-25 部署+实测）**：① `submit_feedback` 持久化 `image_*` 字段；② 新增 `POST /api/admin/feedback/relay`，按 `species_sci+image_file` 反查 manifest 那张图的 `uploader_id`，生成定向给提交者的通知（带 reply，经 `/api/feedback/replies` 下发），不暴露举报者；③ `admin.html` 反馈页显示被举报图缩略图+提交者+「回达提交者」按钮（非 App 用户上传图禁用）。全链路 curl 实测通过（401/持久化/no_app_submitter/真实图回达可达/举报者不泄露）。详见 birding.today handoff。**App 端发版即生效。**
  - **本轮追加（性能 + UX；App 端 analyze No issues、服务器已上线实测）**：① **P1** 公开致谢 `GET /api/contributors` 加 5min TTL 缓存（原每请求扫全部 ~1.1 万 manifest，冷 ~1.2s→热 ~8ms 约 143×；approve/删图即时失效）；② **P2** admin `rate/queue` 加 60s TTL 缓存 + 评级写即时失效 + 修双 `mp.exists()`（冷 168→热 8ms）；③ **P3** 预习页 `_localPreviewImages` 把每张图的 `existsSync` 进程内缓存（`_localFileExists`，切包清空），消除翻页/重建时 UI 线程同步磁盘 I/O；④ **U1** 全屏看大图左上角也加「反馈图片问题」按钮（pop 后走 `_reportImageIssue`）。**P4 经查非真冗余**——`_PreviewImage.credit` 是带 source/sp.imageCredit 兜底的展示串、`contributor` 是干净署名，合并会回退 `©` 文案，故不动。服务器侧 P1/P2 见 birding.today handoff。
  - **致谢「必做」已补 + code-review 修复（2026-06-25）**：① 致谢页 `data_attribution_screen.dart` 补 **GBIF** 图源卡片 + 感谢名单（Wikimedia 之前已在），完成「下一版发布必做」项；② code-review 抓出 **P3 回归**——本屏上传/下载补进来的新本地图会被先前缓存的 `false` 挡住不显示，已改成**只缓存「存在」、不缓存「不存在」**（新文件下次 build 必重查）；③ 顺手**补全服务器缓存失效**：approve/delete/upload(管理员)/restore 现两缓存（致谢 + 评级队列）全覆盖（原只 approve/delete 覆盖致谢）。均 analyze/py_compile/重部署实测过。

- **近版一句话（细节见 [docs/CHANGELOG.md](docs/CHANGELOG.md)）**：
  - **v1.6.21**（已打 APK `releases/Birdaholic_v1.6.21_android.apk`，+78）：闪卡「数据包」筛选 bug 修复（`loadSpeciesForPack` 按激活单包出题）+ 致谢名单恢复（公开 `GET /api/contributors`）+ 闪卡停顿放慢 + 筛选表单统一 + 上传按钮合并 + 新手锁包加固。
  - **v1.6.20**（+77）：新手/自由模式（首启二选一）+ 首页三键化（打卡/预习/复习）瘦身 + 逐种评级入 App（`/api/rate/*` 上线）+ 数据包按国家分组 + 删二级审核（统一走设置→内容审核）。
  - **v1.6.18**（+75/76）：5 处 bug/UI 收口 + 后台逐种评级页（`/api/admin/rate/queue`）+ 中国鸟选择题库（`china_quiz_bank.json` 1460/1490）。
  - **更早**：留存 1–6 批、每日提醒、启动匿名上报（`/api/ping`）、后台快赢批、补图收尾「全库零空白零非开放图」、备案去社交、v1.6.18+75 鸿蒙拒回修复等 → 见 CHANGELOG.md。

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
5. Android：**安卓和鸿蒙分开打**。安卓用普通 `.flutter-sdk`（不要用 flutter-ohos——它启动强制要 HOS SDK，且 audioplayers 的 ohos fork 在普通安卓编译不过）。配方（2026-06-17 实测 1.6.17+74 成功，70.4MB 已签名）：
   1. `android/local.properties` 的 `flutter.sdk` 改 `/Users/wuyang/.flutter-sdk`（鸿蒙时是 `/Users/wuyang/flutter-ohos`）。
   2. **注释掉 pubspec 的整个 `dependency_overrides` 块**（audioplayers 的 ohos fork），让 audioplayers 用上游 ^6.1.0。`dependencies` 里的 `*_ohos` 平台实现可留着（安卓不编译它们）。
   3. `/Users/wuyang/.flutter-sdk/bin/flutter clean && pub get`（**clean 必须**，否则 GeneratedPluginRegistrant 残留旧插件报 cannot find symbol）。
   4. `/Users/wuyang/.flutter-sdk/bin/flutter build apk --release`。
   5. 打完恢复鸿蒙环境：`git checkout pubspec.yaml pubspec.lock`、local.properties 改回 flutter-ohos、`flutter-ohos pub get`。
   - 代码侧：`_platformLabel` 已改为 `.name` 兜 ohos（commit 79412de），两套工具链都能编译，勿回退成 `case TargetPlatform.ohos`。
5b. **鸿蒙打包 + 华为应用市场(AppGallery)上架**（2026-06-17 实测 1.6.17+74 一路过到"等待预审"成功）。⚠️ flutter-ohos CLI 写死要 HarmonyOS(Hmos) SDK，**不能**用它打——走 DevEco 的 hvigor 命令行。

   **★ AppGallery 上架最终关键参数（血泪总结，下次直接照抄）**：
   - **API 必须 ≤22**：华为现网手机最高 API 22。打 API 23 会被自检拒（"仅支持API Level≤22的手机"）。故 `build-profile.json5` product 设 `compatibleSdkVersion:22, targetSdkVersion:22, compileSdkVersion:23`（compile 仍用已装的 23 SDK，合法：compatible≤target≤compile）。PC/2in1 要 ≤21。
   - **必须传 `.app` 不是 `.hap`**：`.hap` 是侧载/调试包；上架要 App Pack `.app`，用 `assembleApp`（不是 assembleHap）打。
   - **apiReleaseType 必须 Release**：Beta（如 DevEco 自带 API26 Beta1）必被拒。用 `~/Library/OpenHarmony/Sdk/23`(6.1.0.31 Release) 即满足。
   - **签名**：`birdaholic_v3Release.p7b` 经查是正经 AGC 发布证书（`type:release, distribution-type:app_gallery, bundle:com.birdflash.bird_flashcard, app-feature:hos_normal_app`，有效期到~2029），直接能用。
   - **权限一致性**：包里 user_grant 权限（LOCATION/APPROXIMATELY_LOCATION，eBird 按位置筛鸟用）必须在 **AGC 后台"权限申请说明"+隐私政策**里声明，否则自检报"权限与隐私政策不一致"。App 内隐私政策(`lib/screens/privacy_policy_screen.dart` 第57/73/85行)已含位置措辞，AGC 那份照抄即可。**包不用改、纯后台操作，改完重传同一个 .app。**
   - 产物：`releases/Birdaholic_v1.6.17_ohos_api22_release.app`（约 70M）。打 .app 命令：`assembleApp -p product=default -p buildMode=release --mode project --no-daemon`，产物在 `ohos/build/outputs/default/ohos-default-signed.app`（**要 signed 那个，别拿 unsigned**）。

   **★ 上架自检逐条拒回 & 修复（持续累积，下次直接照查）**：
   - **图标拒回**「应用图标为系统图标/易误认为系统应用」：桌面启动图标走 `module.json5` ability 的 `$media:icon` → `entry/src/main/resources/base/media/icon.png`，DevEco 新建工程默认是**蓝色模板图**（6.7KB），必须换成真图标。修法：`cp ohos/AppScope/resources/base/media/app_icon.png ohos/entry/src/main/resources/base/media/icon.png`（app_icon 是黄底猫头鹰 1024²，AppScope 那份应用市场展示用、本来就对；要改的是 entry 那份桌面图）。改完重打 .app，解包验 `resources/base/media/icon.png` 应为 129450 bytes 非 6790。（2026-06-18 已修，等重传）
   - **名称拒回**「应用名称/隐私弹窗与 AGC 提交名不一致」（2026-06-19 拒回 → 已修）：终端任务列表/桌面显示的是 `bird_flashcard`，而 AGC 提交名+App 内隐私弹窗是「鸟瘾综合征」。修法：把 4 处显示名串全改成「鸟瘾综合征」——`ohos/AppScope/resources/base/element/string.json` 的 `app_name`（桌面名）、`ohos/entry/src/main/resources/{base,zh_CN,en_US}/element/string.json` 的 `EntryAbility_label`（任务列表名）。`bundleName`（com.birdflash.bird_flashcard）是包标识符**不能动**。改完重打 .app。**版本已同步 bump 到 1.6.18+75**（pubspec / `lib/app_version.dart` / `ohos/local.properties`），AGC 重传要求 versionCode > 上次 74。
   - **两条非阻塞项（2026-06-19 已一并修，仅鸿蒙端，不影响 iOS/安卓）**：
     ① **删自建隐私弹窗（鸿蒙端）**：已接入 AGC 平台隐私托管，自建弹窗会造成首启双弹窗。`lib/main.dart` `_ConsentGate._check()` 开头加 `if (defaultTargetPlatform.name == 'ohos') { 直接放行 }`——**仅鸿蒙跳过自建弹窗，iOS/安卓照旧弹**（那两端没有平台托管，必须保留）。已 `import 'package:flutter/foundation.dart'`（defaultTargetPlatform 需要它，material 不再 re-export）。**枚举不能写 `TargetPlatform.ohos`，用 `.name=='ohos'`**（同 settings_screen 既有约定）。
     ② **本地导入失败修复**：设置→数据包管理→本地导入，鸿蒙上 `result.files.single.path` 为 null 或指向 dart:io 读不了的 URI → `importPack(path)` 抛错。修法：`FilePickerGuard.pickFiles` 加 `withData` 透传，`_importPack` 用 `withData:true` 取内存字节，**优先 `importPackFromBytes(bytes,name)`**（已存在），缺字节才退回 path。iOS/安卓字节路径与原 readAsBytes 内存一致、无回归。`flutter-ohos analyze` 三文件 No issues。

   **⚠️ 清理构建垃圾后重建 ohos 依赖**（清理会删 `ohos/entry/har/`、`ohos/entry/oh_modules`、`ohos/oh_modules`；`flutter_assets`/`libapp.so` 在 `entry/src/main/resources/rawfile` 和 `entry/libs` 通常还在）：
   - `flutter-ohos pub get` 默认报 `No Hmos SDK found` 跳过 ohos 工程生成 → 必须设 **`HOS_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk`**（指 `default/` 的**父级** sdk 目录，它读 `default/sdk-pkg.json` 的 apiVersion=26 即认；指到 openharmony 子目录无效）。带它跑 `flutter-ohos pub get` 就把 `entry/oh_modules` 全套（@ohos/flutter_ohos + 各插件）重建好（har 不需要，直接解析到引擎缓存）。
   - 副作用：会往 `ohos/local.properties` 加一行 `hwsdk.dir=.../sdk`（API26）。**打包前删掉它**（恢复纯 OpenHarmony 23 的 sdk.dir），免得 hvigor 误用 HarmonyOS SDK。`build-profile.json5` 不会被动。
   - 打包前先备份 `build-profile.json5`/`local.properties`/`module.json5` 到 /tmp 比对。

   **DevEco/hvigor 打包踩过的坑＋配方**：
   1. **SDK 版本格式**：社区 OpenHarmony 全量 SDK（`~/Library/OpenHarmony/Sdk/23`，6.1.0.31 Release）在 `ohos/build-profile.json5` 用**整数** `23`，不是 HarmonyOS 那种 `"6.1.0(23)"`/`"5.0.0(12)"` 串。
   2. **不能 app 和 product 两处都配 SDK 版本**：`build-profile.json5` 的 `app.products[0]` 配 `compatibleSdkVersion/compileSdkVersion/targetSdkVersion: 23 + runtimeOS:"OpenHarmony"`；**删掉 `app` 顶层的 `compileSdkVersion`/`compatibleSdkVersion`**（原来是 1，会冲突报"不能同时配置"）。`ohos/local.properties`：`sdk.dir=~/Library/OpenHarmony/Sdk`、`flutter.sdk=/Users/wuyang/flutter-ohos`、`flutter.versionName/Code` 同步成发版号。
   3. **StoreKit 坑**：audioplayers 的 ohos fork `/Users/wuyang/ohos-flutter_audioplayers/packages/audioplayers_ohos/.../player/MediaPlayerPlayer.ets` 有一句 `import { appInfoManager } from '@kit.StoreKit'`（**死 import、没用到**）。`@kit.StoreKit` 是 HarmonyOS 独有，OpenHarmony 23 没有→编译 `Cannot find module '@kit.StoreKit'`。**已删该行**，勿回退。其余 `@kit.*`（ArkTS/AbilityKit/BackgroundTasksKit/BasicServicesKit/AVSessionKit）OpenHarmony 都有。
   4. DevEco 项目结构→基础信息：Node 选自带 `/Applications/DevEco-Studio.app/Contents/tools/node`(v24，仅告警"建议18.x"，可忽略)；SDK 整数格式正确后下拉能选 23。
   5. **命令行直接出 release HAP**（绕开 GUI 找 buildMode）：
      ```
      cd ohos && /Applications/DevEco-Studio.app/Contents/tools/node/bin/node \
        /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js \
        assembleHap -p product=default -p buildMode=release --mode module --no-daemon
      ```
      产物 `ohos/entry/build/default/outputs/default/entry-default-signed.hap`。
   6. 签名：`app.signingConfigs` 那份 `type:"HarmonyOS"` 的 `birdaholic_v3` .p12/.p7b/.cer 对 OpenHarmony 也能签且 verify-app 通过，无需换。
   7. 验产物：`.app` 解包看 `pack.info` 的 `apiVersion`（上架版应 compatible 22/target 22/Release；侧载可 23）+ `version`（1.6.17/74）；`java -jar ~/Library/OpenHarmony/Sdk/23/toolchains/lib/hap-sign-tool.jar verify-app -inFile <hap/app>` 验签名（应 verify-app success）。
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
- **替换原始图版权问题（第二阶段，✅ 2026-06-24 全部完成，详见顶部 Changelog：非开放图清零 + Wikimedia/GBIF 兜底 + 159 占位图 + 拒爬黑名单）**：原始抓取主图里 1,579 张"保留所有权利"+ 7,542 张 NC/ND（仅 1,702 张 CC0/BY/SA）。脚本新增 `--purge-nonopen-inat`（删非开源 iNat 图并换成 CC0/BY/SA）+ `--compress-existing`（超 1600px/600KB 的存量图才压，避免重复降质）。用户上传图（source != inaturalist）一律不动。
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

