# Birdaholic / 鸟瘾综合征 — 完整版本历史（Changelog 归档）

> 本文件是 2026-06-25 从 `HANDOFF.md` 拆分出来的**完整版本流水**，目的是给主 handoff 瘦身（handoff 每次被 Claude/Codex 读，逐版本细节属只增不减的历史，不必每次进上下文）。
> HANDOFF.md 只保留「最新进行中 + 近版一句话摘要」；要查某版改了什么细节，来这里查。**新版本细节追加到本文件顶部，HANDOFF 只更新摘要。**

## Changelog

- **2026-08-21 — 对抗审查高风险修复（v1.7.8+94 已发布 OTA）**：本地 ZIP 数据包改为路径/容量/符号链接校验 + staging 校验后原子替换，防 Zip Slip、恶意包与坏包覆盖旧数据；管理员令牌统一改走 Bearer header，Android/iOS 的上传令牌与外部 API Key 自动从 SharedPreferences 迁入加密存储（Android 关闭备份）；应用内 APK 更新仅接受 birding.today 的 HTTPS APK + `version.json` SHA-256，下载完校验失败即丢弃。自定义复习不再覆盖常用打卡设置，恢复「可能性」顺序会重新取排名。新增数据包安全和 APK 哈希回归测试；项目指定鸿蒙工具链全量测试 30 条通过、全量 analyze 只剩既有文件名 info。**OTA 已发布，线上 `version.json` 含 SHA-256 `2d3d813d5a549972f7c9adb5ea16fe479f59be813a57252d282e036bd6c2a27e`。**

- **2026-08-21 — 闪卡筛选不再重置（v1.7.8+94 已发布 OTA）**：持久化整套闪卡配置（学习/测试、判断/选择/输入、音频/图片、范围、顺序、物种/图片难度），下次进入恢复上次确认值；保留旧范围键迁移、异常值验证和「可能性」动态刷新。筛选页新增今日目标进度条/达标反馈。定向 analyze 通过，2 条本地存储回归测试通过。

- **2026-06-26 — v1.7.0+86（从 1.6.27 改名升 1.7；安卓 `releases/Birdaholic_v1.7.0_android.apk` vc86 已打+用户测过，发 GitHub Release + birding.today；鸿蒙 .app 待 AGC 时再打）**：在 1.6.27 全部内容之上，新增三个用户功能 + 一轮 code-review 修复：
  - **物种难度筛选**（`flashcard_screen`）：闪卡筛选/练习弹层的「难度」行从单个「图片难度」扩成 **物种难度 + 图片难度** 两个下拉（`_difficultyDropdown(species:)`）。物种难度按 `species.difficulty` 评分、两种模式都生效（`_buildDeck` 加 `_speciesDifficultyFilter` 过滤，难度 0/未评按 1）；图片难度只对图片闪卡生效，故只在图片模式显示（音频模式隐藏，避免设了看不到/清不掉的静默过滤——code-review G1）。每档带计数 `⭐⭐⭐ (N)`。
  - **类群概览可点**（`pack_manage_screen._showPackOrderOverview`）：目的 `Chip` 改 `ActionChip`，点某目 → `_openOrderSpecies` 把该目鸟种（`Species.fromJson` 解 species.json 行）用 `BirdPreviewScreen.list` 打开，可左右翻看/点进详情。
  - **断点续传整包**（数据包管理「继续下载（还差 N 种）」）：解决「1000 种下了 100 种就断了，更新媒体只刷新那 100 种、剩 900 种下不了」。`DownloadTaskService.start` 把**完整意图物种清单**按包名持久化（`storage.savePendingDownload`，跨重启有效）；`createPack` 跑完整意图清单后清记录（`_run` 成功分支 `clearPendingDownload`，幂等跳过已下）；`pack_manage._buildPackCard` 按 `intended - speciesCount = remaining` 显示绿色「继续下载（还差 N 种）」按钮 → `_resumePackDownload` 重跑补齐；删包时连带清记录（code-review R1）。另：首页悬浮下载横幅在**失败/取消**后显示「继续下载」(↻)按钮（`canResume`/`retryLast`，内存态，code-review 修了存活引用别名 F-a、弹层 `Expanded(Wrap)` 防溢出 F-b、弹层 `ListenableBuilder` 实时化 F-c）。
  - **code-review（两轮）**：本批新功能跑了 finder+核验+sweep，修了 G1（物种难度音频模式静默过滤）、R1（删包清续传记录）、F-a/F-b/F-c（横幅按钮）；R2（同名包碰撞）/R3（app 杀在清记录瞬间虚显按钮）判定为窄边角/自愈，记录不改。全量 analyze No issues。
  - **改名**：版本号 1.6.27→**1.7.0**（pubspec / app_version / android+ohos local.properties 四处，vc 84→86）。

- **2026-06-26 — v1.6.27+84：安全审查 + code-review 一批修复 + 记录中心导入 + 同义词映射 + 6 条待改（已打 `releases/Birdaholic_v1.6.27_android.apk` 71.7MB/vc84/sha256 已出，待发版；服务器 `upload_server.py` 已部署 124.223.101.188 实测，备份 `.bak_20260626_173246`）**：
  - **流程**：用户要求「先跑 code-review 再一起修」。先做了安全聚焦审查（S1–S3），再跑 `/code-review`（10 finder 角度 + 验证 + sweep）得 15 条（C1–C15），合并去重后一起修。全量 `flutter analyze` No issues、服务器 `py_compile` 通过。
  - **服务器 `server/upload_server.py`（6 处，已部署+curl 实测）**：
    - **S1 路径穿越写**：`species_key()` 内加路径校验（拒 `/`、`\`、`..`、绝对路径、前导 `.`、空）。一处收口覆盖全部「用 sci 拼写入路径」的 sink：`set_identification_features` / `set_difficulty` / `set_image_difficulty` / `_apply_rating` / `load_manifest`。`match_species` 只对 world_birds（干净二名）调它，正常不触发。实测 `sci="../../tmp/evil"` + admin → `400 Invalid species name`。
    - **S2/S3 鉴权**：`set_difficulty` 由 `check_token`（任意 beta）收成 `_require_admin`（beta 评级走 `/api/rate/submit` 进待审；App 端 `setDifficulty` 仅 `isAdminMode` 调，无回归）。`_resolve_image_uploader` 的越界读经 S1 守卫 + 既有 `except` 兜住。实测无 token → `401`。
    - **C6** `admin_rate_resolve`：待审记录**先在锁内删、再到锁外** `_apply_rating`，并 `try/except HTTPException` 软报错。杜绝①持 `_pending_ratings_lock` 时跑 `update_index()` 全量扫盘；②目标图被删时 404 抛出导致记录永远卡队列。
    - **C8** `_resolve_image_uploader`：循环跳过 `pending` 图（不据未过审图回达其提交者）。
    - **C10** `rate_submit`：`int(difficulty)` 包 `try/except` 先于校验（非整数 payload → 400 而非 500）。`set_difficulty` 同样加固。
    - **C11** `admin_rate_queue`：新增 `_RATE_QUEUE_CACHE_LOCK` 单飞 + 双检（对齐 `public_contributors`），过期/失效时只一个线程扫 ~1490 manifest，余者复用，防惊群打满同步线程池。
  - **App（全量 analyze No issues）**：
    - **C1 对账误删**（`pack_manager.updateActivePackFromServer(pruneRemoved)`）：`ServerSpeciesMedia` 新增 `allImages`/`allAudio`（**含 pending**，`server_media_service.fromJson` 从原始 list 构建）；对账「服务器仍知道」集合改用它——避免把**重审中(pending)**的图当「已删」而删掉本地文件。gate 也改成 `allImages/allAudio.isNotEmpty`。
    - **C2/C3 主图署名丢失（合规）**：`_imageEntriesFromItem` 改**无损**——主图若在 `images[]` 有完整条目就用那条（保 `contributor_url`/`location`/`difficulty`），否则才用顶层字段合成；原先合成的精简条目被回写会**永久抹掉署名/定位**并破坏后续对账 `contributor_url` 匹配。新增 `_setCoverFromEntry` 让 `removeSpeciesImageFromActivePack` 与对账换主图时**同步 `image_source`/`image_license`**（漏改会让 `_isUserProvidedCover` 误判、冻结服务器主图刷新并显示错许可）。
    - **C4 可能性未重置**：`flashcard_screen._applyEBirdDeckFilter` 应用**新地点**时也调 `_resetLikelihoodOnContextChange()`（原只清 `_likelihoodRank` 没退 `_order`，牌组静默按拼音排但 UI 仍显示「可能性」）。
    - **C5/C7/C9 导入解析**（`life_list_screen`）：xlsx 按 sheet 序号收集全部工作表、逐表按「拉丁名」表头找列（不再取 zip 首表；新 `_latinNamesFromSheetXml`），固定列(C)兜底加二名抽样校验；CSV 兜底列(idx=2)也加 `_columnLooksLikeBinomials` 校验（防选错文件把 C 列当学名导入假记录）；xlsx `inlineStr` 多 `<t>` run 拼接（防富文本学名截断）。
    - **C13/C14 eBird**（`ebird_service`）：`fetchRegionName` 改 `Uri.https` 让 path 段编码（不再字符串插值进 `Uri.parse`）；`_rankObsBySci` 按 `obsDt` 前 10 位（日期）排序，修「日期」与「日期+时间」混排导致的同日次序错乱。
    - **C12 有意不改**：对账靠 `contributor_url` 识别、同贡献者多图共用一个 url 时删其一会被兄弟图保活漏删——属「该删未删」良性失败；强行收紧匹配会换来「误删本地文件」的数据丢失，两害取轻，保留保守行为。
  - **6 条用户待改（全做进本版）**：
    - **①「学习概览」去重**：打卡日历「详情」页 `progress_detail_screen` 原有 6 张统计卡，与主页 `progress_screen._studyOverviewCard`（4 项可点进 `_StatSpeciesListScreen`）重复且不可点。删详情页那组 `GridView`+`_statCard` 方法+`favorites`/`mastered` 局部变量，详情页只保留「最近学习轨迹」；主页那套留作唯一（可点）入口。
    - **②「今日听声挑战」上移**：`_moreWaysCard`（含听声挑战 + 学习周报两 tile）重写为 `_soundChallengeCard`（单卡只剩听声挑战），并在主 ListView 里挪到 `_checkInCalendar`**之上**。
    - **③ 删「学习周报」**：去 `_moreWaysCard` 里的 tile + `import 'weekly_report_screen.dart'` + 删文件 `lib/screens/weekly_report_screen.dart`。
    - **④【合规】闪卡音频致谢**：查实内置包 89/89 音频种 `audios[].contributor` 全有、`Species.fromJson` 回退 `audioContributors.join` 正确、`_normalizeSpecies`/`copyWith` 保留 audioCredit、答案(back)侧 `_creditLine` 正常——**根因是正面(听音频猜的那面 `_buildPromptFront`)从来没有致谢行**。已在正面音频分支补 `_creditLine(showImageCredit:false)`（录音者名非答案、不剧透）。
    - **⑤ 难度/了解此鸟溢出**：删答案侧「了解此鸟」`TextButton.icon`；`_difficultyRow()` 用 `FittedBox(scaleDown)` 兜底（字体放大/窄屏整行缩放不溢出），管理员评分控件保留。
    - **⑥ 鸟名可点跳「了解此鸟」**：答案侧中/英/拉丁名包进 `GestureDetector(onTap: widget.onLearnMore)`，下方加「轻点名字 · 了解此鸟 ›」小提示。
  - **记录中心导入 + 同义词映射**（v1.6.26 已做、本版随包发布）：`life_list_screen.extractBirdreportLatinNames` 零依赖手解 birdreport.cn xlsx；`assets/data/taxonomy_synonyms.json`（郑四↔AviList 208 键双向）+ `storage.loadTaxonomySynonyms()`/`lifeGroup()`，读取时展开匹配，新旧清单/任意分类包都自动命中。
  - **新手教程同步更新**（`lib/screens/tutorial_screen.dart`）：② 段加「看答案时点鸟的中/英/拉丁名 → 了解此鸟详情页」；④ 段标题改「打卡日历 / 今日听声挑战」并加听声挑战说明 + 日历默认两周可展开整月；⑦ 段把 life list 导入更新成「eBird CSV 或中国观鸟记录中心 birdreport.cn 的鸟种数据导出.xlsx，或鸟种页手动标记」+ 同义词映射自动对齐说明。
  - **打包（安卓 + 鸿蒙双端均已打、待发版）**：
    - 安卓：bump 1.6.27+84 三处 + 注释 `dependency_overrides` + `local.properties` flutter.sdk→.flutter-sdk → `flutter clean && pub get && build apk --release`。产物 `releases/Birdaholic_v1.6.27_android.apk`（vc84，**含教程更新——后补教程后重打过一次**，sha256 `4bde17d0…316c0`）。
    - 鸿蒙（AGC .app）：恢复鸿蒙态（反注释 overrides + flutter.sdk→flutter-ohos + `HOS_SDK_HOME=… flutter-ohos pub get`）→ `ohos/local.properties` bump 1.6.27/84 + 删 `hwsdk.dir` → `hvigor assembleApp -p product=default -p buildMode=release --mode project`（`flutter-hvigor-plugin` 触发 Dart 重编，flutter_assets 时间戳刷新确认新代码进包）。产物 `releases/Birdaholic_v1.6.27_ohos_api22_release.app`（70.6MB / 1.6.27·vc84 / compatible22·target22·Release，hvigor SignApp 用 AGC Release 证书签名）。注：独立 `hap-sign-tool verify-app` 报「Param is not trusted」是该 CLI 信任根限制，非签名问题（构建 SignApp 已成功、同 1.6.17/1.6.18 上架那套签名）。

- **2026-06-26 — v1.6.26+83：用户 4 项 UX（已打安卓包 `releases/Birdaholic_v1.6.26_android.apk` 71.7MB/vc83/sha256 已出，待发版）**：
  - **① 打卡日历默认两周、可展开整月**（`lib/screens/progress_screen.dart` `_checkInCalendar`）：新增状态 `_calExpanded`（默认 false）。收起时渲染「最近两周」——以本周一为锚、回退 7 天取 14 格（2 行，周一对齐，含 isToday/isFuture 标记）；展开时渲染原整月网格 + 月份左右切换行（`if (_calExpanded)` 包住）。GridView `children: _calExpanded ? monthCells : stripCells`。底部居中 `TextButton.icon`「展开整月 ▾ / 收起 ▴」切换，展开时 `_calMonth = thisMonth` 跳回本月。
  - **② 闪卡筛选页「地点筛选」改方框格式**（`flashcard_screen._buildFilterPage`）：原 `OutlinedButton.icon` 换成 `InkWell` 包 `InputDecorator`（`OutlineInputBorder` + `labelText:'地点筛选'` + `isDense`），内放地点图标 + 地名/「选择地点」，视觉与同排「数据包」`DropdownButtonFormField` 一致的方框。
  - **③ 「可能性」排序语义确认 = 纯排序（整包保留）**：
    - 中途曾实现为「交集筛选」（`_buildDeck` 里 `if (_order=='likelihood' && _likelihoodRank.isNotEmpty)` 过滤到 pack ∩ 近期观测），**用户明确要「保留整包、只把近期的排前面」→ 已回退该过滤**。现 `_order=='likelihood'` 仅排序（`_likelihoodRank[normalizeSci]` 命中越靠前、未命中 `1<<30` 垫底再按 cn）。
    - `_selectLikelihoodOrder`：拉近 30 天 eBird 观测建 rank 后 `_buildDeck()`（整包），统计 `overlap`=本包去重学名里命中 rank 的数量。`overlap>0` → snackbar「已把该地区近 30 天最可能遇到的 N 种排到前面」。`overlap==0`（整包与该地区近期记录零交集、排序无意义）→ `_promptLikelihoodInsufficient()`。
    - `_promptLikelihoodInsufficient`（**非破坏性**）：弹「该地区数据不足…可去数据包管理下载/启用覆盖该地区的包」对话框，选「去下载数据包」→ `Navigator.push(PackManageScreen(...))`、返回后 `_loadSpecies()`；**不清空牌组、不强制改 `_order`**（整包仍在，零交集时退化为名称序）。新增 `import 'pack_manage_screen.dart'`。
  - **④ 闪卡致谢渲染修复（合规，用户两次反馈「闪卡没有致谢」）**：先验证内置 `china_common_100_v2.0` 数据 **100/100 种有图片署名、289 图 0 缺 credit&contributor → 非数据问题**，定位为渲染：单图卡走 `_imageCarousel` 的 `images.length==1` 分支只渲染 `_singleImageView`、不显示 caption，而图片署名仅 `_creditLine` 兜底、有缝。修：
    - `bird_card._imageCarousel` 单图分支改为 `Column[ 图, if(caption) Text(caption) ]`，单图也在图下显示 `_imageCaption`（`@作者·地点·时间`，全空时兜底「图片感谢：species.imageCredit」，v1.6.25 已加该兜底）。
    - `bird_card._creditLine` 简化为**只管音频**：`if (showImageCredit || audioCredit.isEmpty) return shrink;` 否则「音频感谢：…」。图片署名完全交给轮播/单图视图的 `_imageCaption`（单图+多图、正反面都带），消除「单图卡漏致谢」与「多图卡 image+audio 双逻辑」的缝。
  - 全量 `flutter analyze` No issues；打包配方同前（注释 `dependency_overrides` + `flutter.sdk` 指 `.flutter-sdk` + bump 1.6.26+83，打完手动恢复鸿蒙：overrides 反注释 + flutter.sdk→flutter-ohos + `flutter-ohos pub get`，未用 `git checkout`）。

- **2026-06-26 — v1.6.25+82：code-review(xhigh effort) 抓一批正确性 bug 修复 + 服务器 #9/#10 收口（已打安卓包 `releases/Birdaholic_v1.6.25_android.apk` 71.7MB/vc82/sha256 已出，待发版）**：
  - 对 v1.6.24 本轮全部未提交改动做了一次 xhigh code-review（10 角度 finder + 自核），抓出并修复以下问题：
  - **① 「可能性」排名上下文失效漏洞（最严重）**：清除地点（3 处入口）/ 切数据包（2 处入口）后，只重置了 `_ebirdFilterSci/Label`，**没清 `_likelihoodRank` 也没退 `_order`**，导致 `_buildDeck` 仍按上一个地区/包的旧排名静默排序。修：新增 `_resetLikelihoodOnContextChange()`（清排名 + 若 `_order=='likelihood'` 退回 `'random'`），5 处全调用，对齐原本只在 `_applyEBirdDeckFilter` 换地点时才有的 `_likelihoodRank=const{}`。
  - **② 切包未清 storage 地点**：两处切包 `onChanged` 没调 `storage.clearEbirdFilter()`，`getEbirdFilterRegion()/Coords()` 仍返回旧包地区码 → 之后选「可能性」拿旧地区给新包排名、还弹"已排序"误导。修：切包补 `await storage.clearEbirdFilter()`。
  - **③ 删本地图后 PageController 越界**：`bird_preview_screen._deleteLocalImage` 只把 `_photoPageIndex[sci]=0`，但持久化的 `_photoControllers[sci]` 仍停旧页 → 轮播变短后越界/白页 + 圆点指示器错位。修：`_photoControllers.remove(sci)` 让 `_pageControllerFor` 重建从第 0 页起的新 controller，旧 controller 走 `addPostFrameCallback` 延后 dispose（避免帧内 use-after-dispose）。
  - **④ 多图卡署名兜底（合规）**：`bird_card._creditLine` 对多图图片卡只交给每图 `_imageCaption`；某图 contributor+credit+location+date 全空时 caption 为空 → 该图无任何署名（单图卡有 `图片感谢` 兜底、多图卡没有）。修：`_imageCaption` 空结果时回退 `图片感谢：species.imageCredit`，与单图卡一致、杜绝无署名图。
  - **⑤ 可能性 key 归一不一致**：deck 侧用 `sci.trim().toLowerCase()`、rank 侧用 eBird `sciName`，而同函数的 lifer 分支用 `StorageService.normalizeSci`；eBird 返回亚种三名时匹配不上落到 `1<<30` 排末。修：建 rank（`putIfAbsent`）与查 rank 两侧统一 `normalizeSci` 二名归一。
  - **⑥ 二维码长按双提示**：`news_screen._saveGroupQr` fire-and-forget `_open` + 无条件弹成功条，失败时与 `_open` 的失败条同时弹。修：改 `async` await `launchUrl`，按返回值单条提示。
  - **⑦ 新手模式建包失败落空首页**：`main._ModeGate._choose` 先 `setAppMode` 再 try 装包且 `catch(_){}`，失败时模式已写入 → 门户消失到「未安装数据包」空首页且无提示。修：beginner 改为**先装包成功再写模式**，失败弹提示 + return 保留模式选择门。
  - **⑧ removeSpeciesImageFromActivePack 精确匹配 sci**：与 `findWritablePackDirForSpecies`/`addUploadedSpeciesImageFromFile` 的归一化匹配不一致，大小写/空白差异会误报「未找到」。修：改 `.trim().toLowerCase()` 匹配。
  - **清理**：删死字段 `_taxonomicOrder`（「按目筛选」下拉这轮已移除、永远 'all'，连带 `_buildDeck` 过滤块 + `_deckSummary` 的 `orderText` 局部变量及 8 处 `$orderText` 插值 + startSession/startCustomSession 两处重置）；删死持久化 `checkinConfigured` getter/setter + `_checkinConfiguredKey`（已被会话标志 `_configuredThisLaunch` 取代、全库无引用）；`_AdminTokenRequestsScreen._approve` 的 `TextEditingController` 补 dispose（每次批准都泄漏一个）。
  - **服务器（birding.today，已部署 124.223.101.188 + curl 实测，备份 `/data/server/upload_server.py.bak_20260626_093958`、`admin.html.bak_…`）**：
    - **#9** `GET /api/contributors`（公开无鉴权、每次冷查扫 ~1.1万 manifest）原无单飞，每次缓存失效后并发请求各自重复全量扫描、可把 Starlette 同步线程池耗尽（写后惊群）。注：该路由是 `def`（非 `async def`），Starlette 本就放线程池跑、**不阻塞事件循环**——所以原 review「阻塞整个服务」一说被否；真问题是重复扫描。修：加 `_CONTRIB_CACHE_LOCK = threading.Lock()` 做**单飞 + 双检**，失效后只放一个线程算、其余等它复用。实测冷查回数据、热查 0.0016s。
    - **#10** `admin.html` 反馈图缩略图直接把客户端可控的 `row.image_url` 去源后塞进 `href/src`（`esc()` 只转义不校验 scheme），构造 `javascript:`/`data:` 可在管理员页注入可点链接。修：新增 `safeMediaUrl(u)`——去 `http(s)://源` 后只放行以单个 `/` 开头的本站路径（拒 `javascript:`/`data:`/`//协议相对`），缩略图 href/src 改用它、不安全则整块不渲染。
  - 全量 `flutter analyze` No issues；打包配方同前（注释 `dependency_overrides` + `android/local.properties` 的 `flutter.sdk` 指 `.flutter-sdk` + bump 1.6.25+82，打完手动恢复鸿蒙：overrides 反注释 + flutter.sdk→flutter-ohos + `flutter-ohos pub get`，未用 `git checkout`）。

- **2026-06-25 — 鸟种页图片加「反馈图片问题」按钮（带图片提交者身份；analyze No issues，待发版/后台配套）**：
  - `lib/screens/bird_preview_screen.dart`：`_buildPhotoPage` 图片右上角加半透明 `bug_report_outlined` 圆钮（点击不触发原「点图放大」，二者用 `Stack` 分层），新增 `_reportImageIssue(sp, img)` 复用 flashcard 那套 `storage.addFeedbackEntry` + `AdminUploadService.submitFeedback` 流程，`page='鸟种图片'`。
  - **「通过图给提交者反馈」走管理员中转（用户确认，守备案不做用户↔用户直连）**：反馈 `context` 带上这张图的提交者身份——`report_type=image / image_url / image_file / image_source / image_contributor / image_contributor_url`。为此给 `_PreviewImage` 加了 `contributor`/`contributorUrl` 两字段（服务器图取 `img.contributor/contributorUrl`，本地图取 `info?.contributor/contributorUrl`）。
  - **code-review 复查修 4 处（2026-06-25，已 analyze/部署/实测）**：① 后台 `/api/admin/feedback` 排除 `kind==image_relay` 出站通知（不再污染纠错列表）；② relay 按 `source_feedback_id` 去重（「再次回达」不再给提交者发重复）；③ App `_reportImageIssue` 改为 await+timeout(10s)，同步失败如实提示「已记录，但网络异常未能同步」（原来无条件报已提交）；④ 该方法 `TextEditingController` 现已 dispose。
  - ✅ **后台配套已上线（birding.today，2026-06-25 部署+实测）**：① `submit_feedback` 持久化 `image_*` 字段；② 新增 `POST /api/admin/feedback/relay`，按 `species_sci+image_file` 反查 manifest 那张图的 `uploader_id`，生成定向给提交者的通知（带 reply，经 `/api/feedback/replies` 下发），不暴露举报者；③ `admin.html` 反馈页显示被举报图缩略图+提交者+「回达提交者」按钮（非 App 用户上传图禁用）。全链路 curl 实测通过（401/持久化/no_app_submitter/真实图回达可达/举报者不泄露）。详见 birding.today handoff。**App 端发版即生效。**
  - **本轮追加（性能 + UX；App analyze No issues、服务器已上线实测）**：① **P1** 公开致谢 `GET /api/contributors` 加 5min TTL 缓存（原每请求扫 ~1.1 万 manifest，冷 ~1.2s→热 ~8ms 约 143×，approve/删图即时失效，approve+delete_media 调 `_invalidate_contributors_cache`）；② **P2** `GET /api/admin/rate/queue` 加 60s TTL 缓存 + `set_difficulty`/`set_image_difficulty`/`_apply_rating` 即时失效 + 修双 `mp.exists()`（冷 ~168→热 ~8ms）；③ **P3** `bird_preview_screen._localPreviewImages` 把每张本地图的 `existsSync` 进程内缓存 `_localFileExists`（切包 `_warmCachedPackDir` 清空），消除翻页/setState 重建时 UI 线程同步磁盘 I/O；④ **U1** `_showFullscreenImage(sp,img)` 全屏看大图左上角加「反馈图片问题」按钮（pop 后 `_reportImageIssue`）。**P4 否决**：`_PreviewImage.credit`（带 source/sp.imageCredit 兜底的展示串）与 `contributor`（干净署名）非真冗余，合并会回退 `©` 文案，保留。
  - **致谢必做 + code-review 修复**：致谢页补 **GBIF** 图源卡片 + 感谢名单（完成「下一版必做」，Wikimedia 之前已在）。code-review 抓出 **P3 回归**（本屏上传/下载补进的新本地图被先前缓存的 `false` 挡住）→ 改成只缓存「存在」、不缓存「不存在」。**补全服务器缓存失效**：approve/delete_media/upload(管理员)/restore 现两缓存全覆盖（原只 approve/delete 覆盖致谢；`_invalidate_rate_queue_cache` 现 7 个写点、`_invalidate_contributors_cache` 现 4 个写点）。备份 `.bak_upload_server_20260625_174456.py`，重部署 + analyze/py_compile 实测。

- **2026-06-24 — v1.6.21 实测反馈批 3（analyze 全绿；已打安卓包 releases/Birdaholic_v1.6.21_android.apk，versionCode 78）**：
  - **闪卡「数据包」筛选 bug 修复（核心）**：根因 `PackManager.loadSpecies()` 是把**所有已启用包合并**返回，而 `setActivePack` 会把新包**加进**启用集——所以选挪威包没切换、而是并进中国100。新增 `loadSpeciesForPack(packDir)`（只读单包），闪卡 `_loadSpecies` 改成按**当前激活的单个包**出题（无激活包才退回合并）。现在选哪个包就只学哪个包。
  - **致谢名单恢复**：App 调公开 `/api/contributors` 但服务器只有 `/api/admin/contributors`（admin）→ 一直 404。服务器**新增公开 `GET /api/contributors`**（按 contributor 聚合、只计已通过、不暴露 uploader_id），已部署实测 200。App 端无需改、点「重新加载」即出。
  - **闪卡停顿放慢一点**（上一轮砍太狠）：认对 450→650、看答案 1000→1300、选择题 1000→1300、swipe 400→500、组完成 1000→1300。
  - **今日练习卡**去掉副标题「听声打卡，预习补图像和特征」。
  - **闪卡筛选表单统一**：数据包/范围/顺序/按目筛选 全部改成整行 `DropdownButtonFormField`（OutlineInputBorder），范围+顺序由并排改成各占一行，修「下拉箭头压住方框」。
  - **闪卡界面调整**：① 顶部「筛选」按钮移到底部操作行；②「上传照片」「上传音频」合并成一个「上传」按钮（`_uploadMedia` 弹选择）；③ 打卡→首次直接弹「闪卡筛选」sheet（`startSession(showFilterSheet)`），配置过(`checkinConfigured`)后全屏沿用。
  - **新手锁包加固**：`PackManager.builtinPackDirIfInstalled()`，`_ModeGate._choose`/`settings._switchAppMode` 直接定位内置包目录设激活（不再靠 endsWith 遍历）。
  - ⚠️ 打安卓包仍按配方（注释 `dependency_overrides`+local.properties 指 .flutter-sdk+版本 1.6.21+78，打完恢复 flutter-ohos）。**别用 `git checkout` 恢复**（会吞未提交改动），手动取消注释。

- **2026-06-24 — v1.6.20 实测反馈批 2：新手/自由模式 + 首页三键化 + 闪卡/挑战/数据包/致谢一揽子 + 逐种评级入 App（analyze 全绿、10 测试过；服务器评级接口已上线实测）**：
  - **新手/自由模式（首启二选一，设置可切）**：`StorageService.appMode`（'beginner'/'free'/''）+ `isBeginnerMode`/`hasChosenMode`/`setAppMode`。`main.dart` 加 `_ModeGate`（consent 之后、HomeScreen 之前；未选则全屏二选一卡片）。新手模式=内容与进阶入口都锁在「中国常见鸟 100」：选新手时 `ensureBuiltinPackInstalled`+`setActivePack(china_common_100_v2)`；**设置里隐藏** 数据包管理 / API Key 与上传身份 / 申请上传权限（保留 反馈与通知）；**闪卡筛选隐藏** 数据包下拉 + eBird 地点筛选。设置加「学习模式」入口（`_switchAppMode` bottomsheet）。
  - **首页（progress_screen）三键化 + 瘦身**：今日练习卡由「开始打卡/预习鸟种」两键改为 **打卡 / 预习 / 复习** 三键（各两字）：打卡=数据包继续(`onStartSession all/review/audio`)、预习=`onJumpToPreview`、复习=不熟悉鸟种(`onStartCustom`，无不熟悉则退回 SRS 到期 `dueScis`)。**删独立「到期复习」卡**（`_dueReviewCard` 移除）。**77/252 完成度芯片+进度条可点**→新 `_PackCompletionScreen`（已学/未学明细，未学排前）。**「建议优先复习」并入「学习概览」卡**（底部独立板块删除，`_weakReviewTile` 紧凑行）。**新手教程改可关横幅**（`_tutorialBanner`，仿更新提示，点进 TutorialScreen，`dismissNewUserGuide` 持久化），删旧「新手三步」大卡。删 `_dueReviewCard/_newUserGuideCard/_guideStep/_sectionHeader/_speciesCard/_emptyPanel`。
  - **删「收集图鉴」「主题鸟单」**：删 `collection_screen.dart`/`bird_lists_screen.dart` + 首页「更多玩法」两项 + import（更多玩法现剩：听声挑战/中国鸟选择题/学习周报）。
  - **打卡流程记忆**：`StorageService.checkinConfigured`；首次打卡先停「打卡设置」窗口，点「开始打卡」(`_startFromWindow` 置位)后，之后首页打卡直接全屏沿用上次筛选（`home_screen` autoFocus = `flashcardStartFullscreen || checkinConfigured`）。
  - **闪卡**：①「模式」段 预习/复习 → **学习/测试**（`AnswerMode.learning/review` 标签）；②**停顿时间缩短**（认对 700→450、看答案 1500→1000、选择题 900→650、组完成 1600→1000 等）；③**取消图片绿色边框/内边距**（`bird_card._singleImageView` 去 ColoredBox+Padding+圆角裁切，长图不再超框）。
  - **每日挑战（听声）**：①加**声谱图**（`_Question.spectrogramPath`，本地或服务器 spectrogramUrl，题面音频下展示）；②选项**同属>同科>同目>全局**（`_pickDistractors`，原为纯随机）。
  - **数据包管理**：已安装包**按国家分组**（`_packCountry` 从 region「中国 · 湖北」「CN-42」等推断，`_buildGroupedPackList`，单组退回平铺、多组加国家小标题）。
  - **致谢页**：「上传贡献者致谢」名单**紧跟「感谢」放一起** + 标题行加**刷新**按钮 + 失败时「重新加载」（`_reload`）。
  - **删「二级上传审核界面」**：审核统一走「设置 → 内容审核」；`pack_manage_screen` 删 `uploadReview/uploadHistory` 两 section/enum/switch + import；`upload_section` 的 `onOpenReview` 改可选并删两处审核入口（appbar 待审按钮 + 我的上传卡里的审核入口）。
  - **逐种评级入 App（管理员直接生效 / 内测进待审，管理员审核）**：
    - 新 `lib/screens/rate_species_screen.dart`：读 `assets/data/china_birds.json`(1490)，逐种拉服务器 manifest 图片（`ServerMediaService.fetchSpeciesMedia`），给**物种难度 + 每张图质量/难度**打星，上一/下一/搜索跳转。入口：设置管理员卡「逐种评级」；内测用户单独卡「逐种评级」（注明需审核）。
    - 新 `lib/screens/rate_review_screen.dart`：管理员审核内测提交（通过写入 manifest / 拒绝丢弃）。入口：设置管理员卡「评级审核」。
    - `AdminUploadService` 加 `submitRating`(POST `/api/rate/submit`)、`fetchPendingRatings`、`resolveRating`。
    - **服务器** `upload_server.py` 加 `POST /api/rate/submit`（管理员→`_apply_rating` 直接写 manifest；内测→存 `pending_ratings.json` 待审）、`GET /api/admin/rate/pending`、`POST /api/admin/rate/resolve`（approve 写入 / reject 丢弃）。**已部署 124.223.101.188 + restart + 全链路 curl 实测通过**（unauth 401、内测 pending、管理员 reject 不写、approve 写 manifest difficulty、管理员直评 applied、临时 beta 密钥已清理）。改前备份 `.bak_upload_server_20260624_223844.py`。
  - ⚠️ 发安卓包仍按「安卓打包配方」：注释 pubspec `dependency_overrides` + local.properties 指 `.flutter-sdk` + 版本已 bump `1.6.20+77`，打完恢复 flutter-ohos。本批纯 Dart+资产+服务器，无新原生依赖，鸿蒙安全。

- **2026-06-24 — v1.6.18 实测反馈批：5 处 bug/UI 收口 + 逐种评级后台 + 中国鸟选择题库（App analyze 全绿、10 测试过；后台已上线实测）**：
  - **A1 修「上传权限申请」崩溃**：`admin_upload_service.dart fetchTokenRequests` 原 `jsonDecode(...) as List`，但服务器 `/api/admin/token_requests` 返回 `{"items":[...]}`（dict）→ 崩 `_Map 不是 List`。改成兼容 dict(取 items)/裸列表两种。
  - **A2 修「收集图鉴」目名没中文**：`collection_screen.dart` 原直接显示原始 `order`（英文学名码如 PASSERIFORMES）。改用 `BirdOrderTaxonomy.info(order).label` 翻译**并作为分组键**（英文码与中文名自动合并到同一目），按 `sortWeight` 排序。
  - **A3 「到期复习」去副文案**：`progress_screen._dueReviewCard` 去掉「（按遗忘曲线安排）」。
  - **A4 删「闯关学习路线」**：删 `lib/screens/level_path_screen.dart` + `progress_screen` 的 import 与 `_moreWaysCard` 那一项（理由：应按常见鸟/难度划分，依据未就绪）。
  - **A5 首页瘦身**：「今日听声挑战」独立大卡并入「更多玩法」列表（少 1 张卡）；连同删闯关，首页少 2 张大卡，顶部只留 今日练习/今日目标/到期复习 核心动作。
  - **C 中国鸟选择题库（两个都要）**：
    - 生成脚本 `packager/build_china_quiz_bank.py`：读 `china_birds.json`(1490) + 服务器各 manifest，每种出一道「看图选鸟种」（干扰项优先同科>同目>全局，固定种子可复现，图 URL 重写为 `https://birding.today`）。**在服务器本地跑**（零网络）：`python3 build_china_quiz_bank.py --china-birds china_birds.json --species-dir /data/species --out china_quiz_bank.json` → 当前出题 **1460/1490**（30 种无图）。产物拉进 `assets/data/china_quiz_bank.json`（已加进 pubspec 资产）。**后台逐种评级后重跑此脚本可按 difficulty 分档/过滤低质图**（`--min-quality`）。
    - App 内 `lib/screens/china_quiz_screen.dart`：读该资产，看图(NetworkImage)选鸟种 4 选 1、即时高亮、出分、「再来一组」。入口在首页「更多玩法」（图标 quiz）。纯单机、无社交。
  - **B 后台「逐种评级」页（已上线 birding.today/admin）**：见下「逐种评级」一节。
  - ⚠️ 发版打安卓包仍按「安卓打包配方」：注释 pubspec `dependency_overrides` + local.properties 指 `.flutter-sdk` + bump 1.6.19+76，打完恢复 flutter-ohos。本批纯 Dart+资产，无新原生依赖，鸿蒙安全。
  - **逐种评级（B，服务器端）**：
    - 服务器 `upload_server.py` 新增 `GET /api/admin/rate/queue`（admin）：读同目录 `china_birds.json`，返回 1490 种 `{sci,zh,en,order,family,key,has_manifest,species_difficulty,species_rated,image_count,image_rated}` + `total/rated`。已 scp `china_birds.json` 到 `/data/server/`。
    - `admin.html` 新增「逐种评级」标签页：逐种看图，**键盘 1–5 给物种难度（→`/api/set_difficulty`）、Shift+1–5 给当前选中图质量难度（→`/api/set_image_difficulty`）、←/→/Enter 翻页**，点缩略图切「当前图」，「只看未评」过滤、跳转搜索、进度「已评 N/1490」。图 URL JS 里重写 http://…:8080→https 防混合内容。
    - 复用既有 `set_difficulty`(写 manifest 顶层 `difficulty`=物种难度)/`set_image_difficulty`(写图条目 `difficulty`)；「已评」判定=manifest/图条目是否含 `difficulty` 键。
    - 部署：改前 `cp .bak_upload_server_<ts>.py`/`.bak_admin_<ts>.html`；`systemctl restart birdaholic-upload`；queue/写入全链路 curl 实测通过（unauth→401）。Mac 浏览器开 `https://birding.today/admin`→逐种评级即用。

- **2026-06-24 — 留存第3-6项：SRS到期 + 关卡 + 图鉴 + 鸟单 + 周报（纯单机、不沾社交；analyze 全绿、10 测试过）**：
  - **共享基建**：`FlashcardScreenState.startCustomSession({scis,label})` 学任意物种子集（`_filter='custom'` + `_customScis`，不走「记住上次筛选」）；`home_screen.startCustomFlashcard` + `ProgressScreen.onStartCustom` 穿线。到期复习/关卡/鸟单都走它。
  - **③ SRS 到期复习**：`StorageService.isDue(SpeciesMastery)`（纯函数，间隔 `srsIntervalsDays=[1,2,4,7,15,30]` 按 knownStreak 递增，上次答错则 1 天）；首页 `_dueReviewCard` 显示「到期 N 种」+「去复习」→ `onStartCustom(dueScis,'到期复习')`；无到期显示「已清空」。
  - **④ 关卡路线**：`level_path_screen.dart`——按包顺序每 10 种一关，整关「掌握」(knownStreak≥3)后解锁下一关，进度条/锁/✓；点关卡 `onStartCustom`。
  - **⑤ 收集图鉴**：`collection_screen.dart`——按「目」分组完成度（已掌握=已收集），总完成度环 + 各目展开看物种 chip。
  - **⑥ 主题鸟单**：`bird_lists_screen.dart`——自动生成清单（收藏/不熟悉/未学习/国家一二级/各目≥5种），点清单 `onStartCustom`。**个人周报**：`weekly_report_screen.dart`——近7天打卡条 + 本周打卡天数/连续/累计学习/已掌握/清单/收藏。
  - 首页新增「更多玩法」卡聚合 闯关/图鉴/鸟单/周报 入口。全部纯 Dart、无新依赖、鸿蒙安全。
  - 留存清单 6 项全部完成（1每日目标+提醒、2听声挑战、3SRS、4关卡、5图鉴、6鸟单+周报）。

- **2026-06-24 — 留存第2项：听声每日挑战（纯单机、不沾社交；analyze 全绿、10 测试过）**：
  - 新增 `lib/screens/sound_challenge_screen.dart`：每天 5 道「听鸟鸣选鸟种」选择题，题目与顺序**按日期固定**（`Random(yyyymmdd)`，当天同一套）。从当前包里有可用鸟鸣的种抽题，4 选 1（正确+3 干扰，中文名），用既有 `AudioPlayerWidget`（`autoPlay()`/`stop()`）自动播放、答题即时对错高亮、末尾出分。带鸟鸣的种 <4 时提示去更新媒体。
  - `StorageService` 加 `soundChallengeDoneToday/Score/Total` + `recordSoundChallenge`；**当天已挑战过再玩为练习、不覆盖记录**。
  - 首页 `progress_screen._soundChallengeCard`：未完成「听鸟鸣猜鸟种，每天5题」/ 已完成「得分 X/N ✓」，点进挑战页，返回刷新。
  - 纯 Dart/复用已有音频组件，无新依赖、无构建风险。

- **2026-06-24 — 每日打卡提醒：Android 系统通知（用户定 only 安卓；analyze 全绿、10 测试过；⚠️需安卓构建实测）**：
  - 新增 `lib/services/notification_service.dart`：`flutter_local_notifications` + `flutter_timezone` + `timezone`，**仅 `Platform.isAndroid` 生效**（iOS/鸿蒙/Web 全 no-op）。`scheduleDaily(h,m)` 用 `zonedSchedule` + `matchDateTimeComponents.time` 每日重复、`inexactAllowWhileIdle`（不要精确闹钟权限）。注意 17.2.4 的 `zonedSchedule` 仍**要求** `uiLocalNotificationDateInterpretation`（已传 absoluteTime）。
  - `StorageService` 加 `reminderEnabled/reminderHour(默19)/reminderMinute(默30)`；「闪卡设置」加「每日打卡提醒」开关+时间选择（**`if (Platform.isAndroid)` 才显示**），开启时请通知权限并排程。`main()` 启动时若已开启则重排（防更新/重启丢失）。
  - **依赖/构建改动**：`pubspec.yaml` 加 3 个包；`AndroidManifest.xml` 加 `POST_NOTIFICATIONS`+`RECEIVE_BOOT_COMPLETED` 权限 + flutter_local_notifications 的 `ScheduledNotificationReceiver`/`ScheduledNotificationBootReceiver`；`android/app/build.gradle` 开 `coreLibraryDesugaringEnabled` + 加 `desugar_jdk_libs:2.1.4`（minSdk21 必需）。
  - ⚠️ **鸿蒙(ohos)风险**：这 3 个包无 ohos 实现。打鸿蒙包若 `flutter-ohos pub get`/hvigor 报错，**临时注释掉 pubspec 那段三个依赖再打**（已在 pubspec 注释标注，类比 audioplayers override 的处理）。
  - ⚠️ **本环境没跑安卓构建**：代码 analyze 干净，但通知行为/desugaring/manifest 只能靠真机安卓构建验证。建议下次打 apk 时实测：开关→授权→设时间→后台到点弹通知。

- **2026-06-24 — 服务器闪卡补图收尾：全库零空白 + 零非开放授权图（⚠️ 下一版必改致谢）**：
  - 主会话把服务器 11321 个物种的闪卡图清理补全：非开放授权图（"保留所有权利" + NC/ND）从 4784 张清到 **0**；空白物种逐级兜底补图——iNaturalist 开放图 **+8951**、**Wikimedia Commons +1374**、**GBIF +116**；全网都没开放图的 **159 种放统一占位图「暂无图片」**（manifest 条目 `source=placeholder`、`placeholder=true`，浅灰底+鸟剪影+中英文，可被真实图替换）。终态 **EMPTY=0、非开放图=0**。服务器侧细节见 birding.today handoff。
  - **⚠️ 下一次版本发布必做：改「声明致谢」页（`lib/screens/data_attribution_screen.dart`）**——图片来源**新增两类**，现有致谢页只列了 iNaturalist 等旧来源，会漏标：
    - **Wikimedia Commons**：授权 PD / CC BY / CC BY-SA（含各上传者署名）。
    - **GBIF**：聚合自然史博物馆 / Naturalis / observation.org 等机构，授权 CC0 / CC BY / CC BY-SA。
    - 需在致谢页的**聚合来源清单**里补这两个图源 + 授权说明。（逐图署名 `@作者·地点·时间` 已随 manifest 的 `contributor`/`contributor_url` 自动带出，**无需改**；要补的只是来源清单那一块。）
  - 顺带修了后台「拒了又爬」bug：管理员删/拒的图会记进 manifest `rejected_media` 黑名单，补图脚本去重时跳过、不再重爬送审；并回填了历史删/拒记录、清掉已被爬回的 5 张（服务器 `upload_server.py` + `backfill_inat_photos.py`，详见 birding.today handoff）。

- **2026-06-24 — 留存优化第1项：每日目标 + 连续打卡 + 站内提醒（单机、不沾社交；analyze 全绿、10 测试过）**：
  - `StorageService` 加 `dailyGoal`（默认10，1–200）+ 今日打卡张数（`getTodayStudyCount`，跨天归零，在 `_recordCheckIn` 里随每张答题自增）+ `isDailyGoalMet`。
  - 首页 `progress_screen._dailyGoalCard`：今日 X/N 进度条 + 🔥连续N天 + 达标庆祝；**未达标显示「还差M张」即站内提醒（nudge）**。
  - 「闪卡设置」加「每日目标」选择（5/10/20/30/50）。
  - ⚠️ **真·后台系统推送暂未做**：`flutter_local_notifications` 无 ohos fork，盲加会威胁鸿蒙构建（本仓库每个原生插件都有手配 `_ohos` 版）。先用站内 nudge 替代；要做真推送需先解决 ohos 通知插件或接受仅 Android/iOS（并验鸿蒙构建）。

- **2026-06-24 — 复查修 bug + 备案去社交 + 精选图回推服务器**：
  - **去社交（备案不含社交功能！）**：⑧ 的「用户上传排行榜」（奖牌🥇🥈🥉+排名+用户互比）会被当社交，已改成**「上传贡献者致谢名单」**——`data_attribution_screen` 去掉奖牌/排名，只列贡献者名+可选贡献数；类名 `_UploadLeaderboard`→`_UploadContributors`；服务器路由 `/api/leaderboard`→`/api/contributors`（旧的已 404）。**今后任何"让用户看到/对比/互动其他用户"的功能都不要做**（联赛/周榜/分享社交等）。
  - **复查修 3 处**：① `lifer` 筛选改成只取一次 life list（原来逐种重解析 JSON）；② `PackManager` 对账删除加守卫——服务器该类媒体为空（暂态/未返回）时**跳过不删**，防误删；③「更新已下载媒体」删除勾选框**默认改 false**（destructive 不应默认开）。
  - **精选图回推**：内置 v2 包 200 张服务器缺的精选图已合并进服务器（详见 birding.today handoff），顺带让 ⑥ 对账删除对内置包不再误删。
  - analyze 全绿、10 测试通过。

- **2026-06-24 — 打卡体验 + 鸟种页 + life list + 本地对账（用户 10 项里的 ①②③④⑤⑥⑩，全项 analyze No issues、10 测试通过）**：
  - **① 开始打卡不默认全屏**：`StorageService.flashcardStartFullscreen`（默认 false）；`home_screen._startSession` 的 `autoFocus` 改成读该设置；「闪卡设置」顶部加开关。默认先停在带筛选条窗口，点「开始打卡」按钮才进 focus。
  - **② 退出打卡保留筛选**：`StorageService.lastFlashcardFilter`；`flashcard_screen` initState 从存档恢复 `_filter`（仅 `_restorableFilters` 内的值），筛选下拉 onChanged 持久化，`startSession` 沿用存档值而非硬编码 'all'。
  - **③ 日历放大月历**：`progress_screen._checkInCalendar` 由 14 天横条改成**整月网格**（7 列 GridView + 周一起始 + 上/下月翻页 + 本月打卡天数 + 今天描边/已打卡填充），`_stripDayCell`→`_monthDayCell`，加状态 `_calMonth`。
  - **⑤ 鸟种页辨识/鸟鸣左右滑**：`bird_preview_screen` 把堆叠的 `_buildAudioSection`+`_buildFeaturesSection` 包进 `_buildDetailTabs`——两 Tab 按钮 + 左右滑手势 + AnimatedSwitcher 切换（自然高度，不裁剪），状态 `_detailTab`。
  - **④ eBird life list**：`StorageService` 加 life list（标准化「属 种」小写存 Set）：`getLifeList/hasSeen/setSeen/mergeLifeList/clearLifeList/lifeListCount`。新增 `lib/screens/life_list_screen.dart`（导入 MyEBirdData.csv：自带 CSV 状态机解析、按表头含 "scientific" 的列抽学名、可重复导入去重；清空）。设置「我的观鸟清单」入口；鸟种页 AppBar 加「已见/未见」标记；打卡筛选新增 `lifer`=「未见过（潜在新种）」（叠加 eBird 地点筛选=附近没见过的种）。**API 拿不到他人 life list，只能导出 CSV / 手动标记——已在教程和清单页讲清。**
  - **⑥ 本地图对账删除**：`PackManager.updateActivePackFromServer` 加 `pruneRemoved`；服务器 manifest 里已没有、但本地还留着且**有 contributor_url（可识别服务器身份）**的图/音（含声谱图）会被删（用户本机自加、无 contributor_url 的不动）；`MediaUpdateResult` 加 `imageRemoved/audioRemoved`；「更新已下载媒体」对话框加勾选项（默认勾上）+ 结果提示清除数。
  - **⑩ 新人图文教程**：新增 `lib/screens/tutorial_screen.dart`（8 节：三步上手/打卡/鸟种页/日历/抽象图理念/什么是API+如何申请/eBird life list/反馈）；设置「新手教程」入口 + 首页新手三步卡加「查看完整教程」。
  - 新增文件：`life_list_screen.dart`、`tutorial_screen.dart`。改动文件：`storage.dart`、`home_screen.dart`、`flashcard_screen.dart`、`progress_screen.dart`、`bird_preview_screen.dart`、`settings_screen.dart`、`pack_manager.dart`、`pack_manage_screen.dart`。
  - 全部待下个版本发布生效；与 Batch A（⑦⑧⑨）一起构成用户这轮 10 项需求的完整实现。

- **2026-06-24 — 后台/审核快赢批（用户 10 项需求中的 ⑦⑧⑨，analyze 已过 No issues）**：
  - **⑨ 审核双按钮**：`/api/admin/approve` 加 `pin` 参数——pin=true 置顶为首图（「通过置顶」），否则放数组末尾（「通过」），默认不置顶。改动：服务器 `upload_server.py`（已上线）、web 后台 `admin.html` 待审核页拆「通过置顶/通过」两按钮（已上线）、App `upload_review_section.dart` 拆两按钮 + `AdminUploadService.approve(pin:)`。
  - **⑧ 用户上传排行榜**：新增公开只读 `GET /api/leaderboard`（按署名 contributor 聚合，只计已通过的用户上传，不含 iNat、不暴露 uploader_id；已上线）。App 致谢页 `data_attribution_screen.dart` 末尾加 `_UploadLeaderboard`（拉该接口，奖牌+图/音/种计数）。**注**：本条后被「备案去社交」改成「上传贡献者致谢名单」，`/api/leaderboard`→`/api/contributors`。
  - **⑦ 审核挪到设置一级**：`settings_screen.dart` 顶部加**管理员专属 Card**（`isAdminMode` 才显示）：「内容审核」→ `UploadReviewSection`、「上传权限申请」→ 新增 `_AdminTokenRequestsScreen`（列待处理申请，批准/拒绝，调 `/api/admin/token_requests` + approve/reject）。`AdminUploadService` 新增 `fetchTokenRequests/approveTokenRequest/rejectTokenRequest` + `AdminTokenRequest` 模型。原先审核只藏在「数据包管理」二级里。
  - 服务器端 ⑨⑧ **已直接改线上并 restart 实测**（`/api/leaderboard` 返回正常）；改前 `.bak_20260624_114124`。App 端 ⑦⑧⑨ 代码就绪、随下个版本发布生效。

- **2026-06-24 — 启动匿名上报（装机/活跃统计）**（待发版生效，analyze 已过 No issues）：
  - 新增 `lib/services/usage_service.dart`：`UsageService.recordAppOpen(storage)`，fire-and-forget `POST https://birding.today/api/ping`，body `{client_id, platform=Platform.operatingSystem, app_version=appVersionName, app_build=appBuildNumber}`，8s 超时、异常全吞。复用 `StorageService.ensureFeedbackClientId()` 的匿名 ID + `ServerMediaService.defaultBaseUrl`。**不收个人信息，服务器不存 IP。**
  - `lib/main.dart` `_ConsentGate._check()` 在**三处已同意放行点**（ohos 托管 / 已接受过 / 本次点同意后）各 `unawaited(UsageService.recordAppOpen(...))`；**拒绝隐私协议的分支不上报**。新增 `import 'dart:async';`（unawaited）。
  - 服务器端 `/api/ping` + `/api/admin/usage` + 后台「装机/活跃」页**已上线**（详见 birding.today handoff）。后台看数：`GET /api/admin/usage?days=30&token=birdaholic_admin_2026`。
  - ⚠️ 发版前隐私政策（`lib/screens/privacy_policy_screen.dart`）建议补一句「收集匿名设备标识+版本用于统计装机/活跃度」，AGC「权限申请说明」无需改（不涉新权限）。
  - 统计只从带此上报的新版发布后累积；历史下载量看 GitHub Release（截至 2026-06-24 APK 累计 235）。

- **2026-06-19 — v1.6.18+75 鸿蒙拒回修复 + 重打包**（详情见 HANDOFF「AppGallery 上架自检逐条拒回」节的「名称拒回」「两条非阻塞项」）：
  - 应用显示名统一「鸟瘾综合征」（AppScope `app_name` + entry `EntryAbility_label` base/zh_CN/en_US 共 4 处），修华为「名称与提交名不一致」拒回；`bundleName` 不动。
  - 鸿蒙端跳过自建隐私弹窗（`lib/main.dart` `_ConsentGate._check()` 判 `defaultTargetPlatform.name=='ohos'`），避免与 AGC 平台隐私托管双弹窗；iOS/安卓照旧。
  - 修「本地导入提示导入失败」：`FilePickerGuard` 加 `withData` 透传，`_importPack` 优先用内存字节走 `importPackFromBytes`（鸿蒙 path 可能 null/不可读）。
  - 版本 1.6.17+74 → **1.6.18+75**（pubspec / `lib/app_version.dart` / `ohos/local.properties` 三处同步）。
  - 重打包出 signed `.app`：`releases/Birdaholic_v1.6.18_ohos_api22_release.app`（70MB）。验证全过：pack.info 1.6.18/75、compatible/target API 22、Release；`verify-app success`；resources.index 含「鸟瘾综合征」×4、无 `bird_flashcard` 显示名；libapp.so 22:01 重编含上述 Dart 改动。打包前用 `flutter-ohos pub get`(带 `HOS_SDK_HOME`) 修复了 `.dart_tool` 误指向 `.flutter-sdk`，并删除其写入 `local.properties` 的 `hwsdk.dir` 行。
  - ⏭ 待用户操作：上传该 .app 到 AGC 提交新版本；AGC 后台仍需确认位置权限在「权限申请说明」+隐私政策里已声明。

---

## 更早历史（v1.3.0 时期，仅存档参考）

> 以下两段是早期 handoff 的「当前状态」与 v1.3.0 大改记录，已被 v1.6.x 全面取代，仅作历史留存。

### 旧 analyze 记录（v1.3.0 时期）

`flutter analyze --no-pub` 通过（exit code 0），只剩一个无影响的 warning（species_list_screen.dart 里一个 dead null-aware expression）。

### v1.3.0 新功能（当时的大改）

**首页（ProgressScreen）**

- 移除原来 4 个模式按钮。
- **打卡**按钮（绿色）：开始闪卡复习，行为与原"开始学习"一致。
- **预习**按钮（蓝色）：跳转到鸟种预习页（tab 2）。
- 播客卡片：自动拉取小宇宙「鸟瘾综合征」最新一期，显示封面+标题+日期，点击跳转 App/网页。

**鸟种页（SpeciesListScreen）→ 全新预习浏览界面**

- **当前数据包模式**：整个替换为竖向 PageView，每页展示一种鸟（上半本地图片+服务器图左右滑、致谢、收藏、详情；下半中/英/学名、保护级别 chip、本地音频、辨识特征≤4 行；上下滑翻页；顶部工具栏名录/数据包切换+搜索+按目筛选；「详情」push 完整 `BirdPreviewScreen`；暂无图片显示「从服务器补充」）。
- **鸟种名录模式**：保留原有列表 UI（用于 eBird 地点筛选 + 批量勾选下载）。

**闪卡（FlashcardScreen）**

- 10 鸟一组（完成面板+铃声）、多图切换（>1 张才显示 PageView+点状指示器）、完成音效 `assets/sounds/complete.m4a`、「了解此鸟」push `BirdPreviewScreen`、管理员难度星（持久化到 `species.json`）。

**预习界面（BirdPreviewScreen）—— 新建**：路径 `lib/screens/bird_preview_screen.dart`，两种构造（单种 / `.list`），黑绿暗色主题，上下滑/底部箭头翻页，照片横向 PageView+全屏预览，音频本地+服务器，eBird 地点筛选 sheet，上传（普通用户存本地/管理员推服务器），收藏。

**其他**：Species 模型加 `difficulty`（int 默认 1，omit-if-default）；PackManager 加 `saveSpeciesDifficulty()`；PodcastService 手动解析 RSS；`.claude/settings.json` 新建（flutter analyze 等白名单）。
