import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/species.dart';
import '../services/app_update_service.dart';
import '../services/pack_manager.dart';
import '../services/storage.dart';
import '../widgets/bird_card.dart';
import '../widgets/update_download_dialog.dart';
import 'progress_detail_screen.dart';
import 'sound_challenge_screen.dart';
import 'tutorial_screen.dart';

class ProgressScreen extends StatefulWidget {
  final PackManager packManager;
  final StorageService storage;
  final void Function(String filter, StudyMode mode, PromptMode promptMode)
      onStartSession;
  final void Function(Species species) onJumpToFlashcard;
  final void Function(List<String> scis, String label) onStartCustom;
  final VoidCallback? onJumpToPreview;
  final int refreshToken;
  final bool isActive;

  const ProgressScreen({
    super.key,
    required this.packManager,
    required this.storage,
    required this.onStartSession,
    required this.onJumpToFlashcard,
    required this.onStartCustom,
    this.onJumpToPreview,
    required this.refreshToken,
    required this.isActive,
  });

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  bool _loading = true;
  List<Species> _species = [];
  String? _loadError;
  bool _guideDismissed = false;
  AppUpdateInfo? _updateInfo;
  bool _updateLoading = true;
  /// 打卡日历当前展示的月份（仅看年月），null = 本月。
  DateTime? _calMonth;
  bool _calExpanded = false; // 打卡日历：默认收起（最近两周/2 行），点击展开到整月

  @override
  void initState() {
    super.initState();
    _load();
    _guideDismissed = widget.storage.isNewUserGuideDismissed;
    // 更新通知仅 Android 显示（iOS 走 App Store）。
    if (Platform.isAndroid) _loadUpdateInfo();
  }

  Future<void> _loadUpdateInfo() async {
    final info = await AppUpdateService.fetchLatest();
    if (!mounted) return;
    setState(() {
      _updateInfo = info;
      _updateLoading = false;
    });
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法打开：$url')));
    }
  }

  /// 有直链(GitHub Release .apk 附件)就应用内一键下载装；拿不到才退回打开下载页。
  Future<void> _startUpdate(AppUpdateInfo info) async {
    final apkUrl = info.apkAssetUrl;
    if (apkUrl == null || apkUrl.isEmpty) {
      await _openUrl(info.downloadUrl);
      return;
    }
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDownloadDialog(info: info),
    );
  }

  /// 只在真的有新版本、且用户没忽略过这个版本号时才出这条；没有更新时不产生任何持久 UI噪音。
  Widget? _updateBanner() {
    if (_updateLoading || _updateInfo == null) return null;
    final info = _updateInfo!;
    if (!AppUpdateService.isNewerThanCurrent(info.version)) return null;
    if (widget.storage.dismissedUpdateVersion == info.version) return null;
    const bg = Color(0xFF2d5016);
    const fg = Colors.white;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _startUpdate(info),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.system_update_alt, size: 18, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '有新版本 ${info.version} · 点击下载',
                  style: const TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: '忽略此版本',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                onPressed: () {
                  widget.storage.dismissUpdateVersion(info.version);
                  setState(() {});
                },
                icon: const Icon(Icons.close, size: 18, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant ProgressScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        (!oldWidget.isActive && widget.isActive)) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final species = await widget.packManager.loadSpecies();
      if (!mounted) return;
      setState(() {
        _species = species;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _species = [];
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.storage.getStats();
    final masteryMap = widget.storage.getAllMastery();
    final studied = masteryMap.values
        .where((m) => m.knownCount > 0 || m.unknownCount > 0)
        .length;
    final currentPackStudied = _species.where((species) {
      final mastery = masteryMap[species.cn];
      return mastery != null &&
          (mastery.knownCount > 0 || mastery.unknownCount > 0);
    }).length;
    final unfamiliarNames = widget.storage.getUnfamiliarSpecies();
    final mastered = masteryMap.values.where((m) => m.knownStreak >= 3).length;
    // 「复习」按钮目标 = 不熟悉的种 ∪ 按遗忘曲线到期的种（并集，不是二选一）。
    // 旧逻辑是「有不熟悉就只复习不熟悉」，会把已学好、到期该复习的鸟无限延后——
    // 恰好抽掉间隔重复的核心。这里合并、去重、保持包内顺序。
    final reviewTargets = <String>[
      for (final s in _species)
        if (masteryMap[s.cn]?.unfamiliar == true ||
            (masteryMap[s.cn] != null &&
                StorageService.isDue(masteryMap[s.cn]!)))
          s.sci,
    ];
    final checkInDates = widget.storage.getCheckInDates();
    final streak = _currentStreak(checkInDates);
    final todayCount = widget.storage.getTodayStudyCount();
    final dailyGoal = widget.storage.dailyGoal;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.data_array, size: 64, color: Colors.grey[350]),
              const SizedBox(height: 12),
              const Text(
                '还没有加载学习数据',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                '先去“设置”里的数据包管理安装中国常见鸟 100，之后这里会显示复习建议。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    final updateBanner = Platform.isAndroid ? _updateBanner() : null;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (updateBanner != null) ...[
              updateBanner,
              const SizedBox(height: 12),
            ],
            if (!_guideDismissed) ...[
              _tutorialBanner(),
              const SizedBox(height: 12),
            ],
            _todayPracticeCard(
              currentPackStudied: currentPackStudied,
              reviewTargets: reviewTargets,
              todayCount: todayCount,
              dailyGoal: dailyGoal,
              streak: streak,
            ),
            const SizedBox(height: 12),
            // 今日听声挑战挪到打卡日历上方
            _soundChallengeCard(),
            const SizedBox(height: 12),
            // 打卡日历（连续天数 + 🔥 在日历标题里）
            _checkInCalendar(checkInDates),
            const SizedBox(height: 12),
            _studyOverviewCard(
              studied: studied,
              mastered: mastered,
              unfamiliar: unfamiliarNames.length,
              answered: stats.total,
            ),
          ],
        ),
      ),
    );
  }

  Widget _todayPracticeCard({
    required int currentPackStudied,
    required List<String> reviewTargets,
    required int todayCount,
    required int dailyGoal,
    required int streak,
  }) {
    final total = _species.length;
    // 首页核心 = 今日打卡进度（每次学都动、每天归零），不再是几乎不动的终身包完成度。
    final goalMet = todayCount >= dailyGoal;
    final goalProgress = dailyGoal == 0 ? 0.0 : todayCount / dailyGoal;
    final dueCount = reviewTargets.length;
    const green = Color(0xFF2d5016);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFFF7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: green.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.headphones_rounded,
                  color: green,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '今日练习',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              // 连续打卡天数：打卡 app 的核心习惯信号，放到最显眼的顶栏。
              if (streak > 0) ...[
                const Icon(Icons.local_fire_department,
                    size: 17, color: Colors.deepOrange),
                const SizedBox(width: 1),
                Text(
                  '$streak',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.deepOrange[700],
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              // 本包完成度收成小 chip（次要信息），点开看明细。
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: total == 0 ? null : _openPackCompletion,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        total == 0 ? '未安装数据包' : '$currentPackStudied/$total 种',
                        style: const TextStyle(
                          fontSize: 12,
                          color: green,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (total != 0)
                        const Icon(Icons.chevron_right,
                            size: 15, color: green),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 今日目标进度
          Row(
            children: [
              Text(
                goalMet ? '今日目标已完成 🎉' : '今日目标',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: goalMet ? const Color(0xFF2d7d32) : Colors.grey[700],
                ),
              ),
              const Spacer(),
              Text(
                '$todayCount / $dailyGoal 张',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: goalMet ? const Color(0xFF2d7d32) : green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: goalProgress.clamp(0, 1),
              minHeight: 6,
              backgroundColor: green.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF2d7d32),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // 三键：打卡（数据包继续）/ 预习（鸟种页）/ 复习（不熟悉的鸟种）
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: FilledButton(
                    onPressed: _species.isEmpty
                        ? null
                        : () => widget.onStartSession(
                              'all',
                              StudyMode.review,
                              PromptMode.audio,
                            ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2d7d32),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      '打卡',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: widget.onJumpToPreview,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1565C0),
                      padding: EdgeInsets.zero,
                      side: BorderSide(
                        color: const Color(0xFF1565C0).withValues(alpha: 0.35),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      '预习',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: reviewTargets.isEmpty
                        ? null
                        : () => widget.onStartCustom(reviewTargets, '复习'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepOrange,
                      padding: EdgeInsets.zero,
                      side: BorderSide(
                        color: Colors.deepOrange.withValues(alpha: 0.35),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    // 带待复习数量角标（Anki 式），复习循环一眼可见。
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '复习',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                          if (dueCount > 0) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.deepOrange,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                dueCount > 99 ? '99+' : '$dueCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _studyOverviewCard({
    required int studied,
    required int mastered,
    required int unfamiliar,
    required int answered,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.insights_outlined, size: 19),
                SizedBox(width: 8),
                Text(
                  '学习概览',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _overviewMetric('已学习', '$studied', Colors.blue,
                    () => _openStatSpeciesList('studied')),
                _thinDivider(),
                _overviewMetric('已掌握', '$mastered', Colors.green,
                    () => _openStatSpeciesList('mastered')),
                _thinDivider(),
                _overviewMetric('不熟悉', '$unfamiliar', Colors.red,
                    () => _openStatSpeciesList('unfamiliar')),
                _thinDivider(),
                _overviewMetric('累计答题', '$answered', Colors.amber,
                    () => _openStatSpeciesList('answered')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _overviewMetric(
    String title,
    String value,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 24,
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thinDivider() {
    return Container(
      width: 1,
      height: 42,
      color: Colors.black.withValues(alpha: 0.06),
    );
  }

  Widget _soundChallengeCard() {
    const green = Color(0xFF2d5016);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: ListTile(
        leading: const Icon(Icons.hearing, color: green),
        title: const Text('今日听声挑战',
            style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          widget.storage.soundChallengeDoneToday
              ? '今天已完成 · 得分 ${widget.storage.soundChallengeScore} / ${widget.storage.soundChallengeTotal}'
              : '听鸟鸣猜鸟种，每天 5 题',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => SoundChallengeScreen(
                packManager: widget.packManager,
                storage: widget.storage,
              ),
            ),
          );
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Widget _checkInCalendar(Set<String> dates) {
    final streak = _currentStreak(dates);
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    final month = _calMonth ?? thisMonth;
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadBlanks = firstOfMonth.weekday - 1; // 周一为一周起点
    final todayKey = now.toIso8601String().substring(0, 10);
    // 本月打卡天数
    final monthPrefix =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}-';
    final monthChecked = dates.where((d) => d.startsWith(monthPrefix)).length;
    final canGoNext =
        month.year < now.year || (month.year == now.year && month.month < now.month);

    // 展开：整月网格
    final monthCells = <Widget>[];
    for (var i = 0; i < leadBlanks; i++) {
      monthCells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(month.year, month.month, d);
      final key = date.toIso8601String().substring(0, 10);
      monthCells.add(_monthDayCell(
        day: d,
        checked: dates.contains(key),
        isToday: key == todayKey,
        isFuture: date.isAfter(now),
      ));
    }
    // 收起（默认）：最近两周（含本周，周一对齐），共 14 格 = 2 行
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final stripStart = monday.subtract(const Duration(days: 7));
    final stripCells = <Widget>[];
    for (var i = 0; i < 14; i++) {
      final date =
          DateTime(stripStart.year, stripStart.month, stripStart.day + i);
      final key = date.toIso8601String().substring(0, 10);
      stripCells.add(_monthDayCell(
        day: date.day,
        checked: dates.contains(key),
        isToday: key == todayKey,
        isFuture: date.isAfter(now),
      ));
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_month_outlined, size: 20),
                const SizedBox(width: 8),
                const Text('打卡日历',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const Spacer(),
                if (streak > 0) ...[
                  const Icon(Icons.local_fire_department,
                      size: 18, color: Colors.deepOrange),
                  const SizedBox(width: 2),
                ],
                Text(
                  '连续 $streak 天',
                  style: TextStyle(
                    color:
                        streak > 0 ? Colors.deepOrange[700] : Colors.grey[600],
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final changed = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProgressDetailScreen(
                          storage: widget.storage,
                          species: _species,
                          onJumpToFlashcard: widget.onJumpToFlashcard,
                        ),
                      ),
                    );
                    if (changed == true && mounted) {
                      setState(() {});
                    }
                  },
                  child: const Text('详情'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 月份切换（仅展开整月时显示）
            if (_calExpanded)
              Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_left, size: 22),
                    onPressed: () => setState(
                      () => _calMonth = DateTime(month.year, month.month - 1),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${month.year} 年 ${month.month} 月 · 打卡 $monthChecked 天',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_right, size: 22),
                    onPressed: canGoNext
                        ? () => setState(
                              () => _calMonth =
                                  DateTime(month.year, month.month + 1),
                            )
                        : null,
                  ),
                ],
              ),
            const SizedBox(height: 6),
            Row(
              children: ['一', '二', '三', '四', '五', '六', '日']
                  .map((w) => Expanded(
                        child: Text(
                          w,
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: _calExpanded ? monthCells : stripCells,
            ),
            // 默认 2 行（最近两周），点「展开整月」放大到整月打卡
            Center(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Colors.grey[600],
                ),
                icon: Icon(
                    _calExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18),
                label: Text(_calExpanded ? '收起' : '展开整月'),
                onPressed: () => setState(() {
                  _calExpanded = !_calExpanded;
                  if (_calExpanded) _calMonth = thisMonth; // 展开回到本月
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthDayCell({
    required int day,
    required bool checked,
    required bool isToday,
    required bool isFuture,
  }) {
    const green = Color(0xFF2d5016);
    return Center(
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: checked ? green : Colors.transparent,
          shape: BoxShape.circle,
          border: isToday && !checked
              ? Border.all(color: green, width: 1.6)
              : null,
        ),
        child: Text(
          '$day',
          style: TextStyle(
            fontSize: 13,
            color: checked
                ? Colors.white
                : isFuture
                    ? Colors.grey[350]
                    : (isToday ? green : Colors.grey[800]),
            fontWeight:
                isToday || checked ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  int _currentStreak(Set<String> dates) {
    var streak = 0;
    var cursor = DateTime.now();
    while (true) {
      final key = cursor.toIso8601String().substring(0, 10);
      if (!dates.contains(key)) return streak;
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
  }

  /// 点击统计卡片：打开对应鸟种清单（已学习/已掌握/不熟悉/累计答题）。
  void _openStatSpeciesList(String which) {
    final masteryMap = widget.storage.getAllMastery();
    final unfamiliar = widget.storage.getUnfamiliarSpecies().toSet();
    String title;
    late bool Function(Species) test;
    int Function(SpeciesMastery)? sortKey;
    switch (which) {
      case 'mastered':
        title = '已掌握';
        test = (s) {
          final m = masteryMap[s.cn];
          return m != null && m.knownStreak >= 3;
        };
        break;
      case 'unfamiliar':
        title = '不熟悉';
        test = (s) => unfamiliar.contains(s.cn);
        break;
      case 'answered':
        title = '累计答题';
        test = (s) {
          final m = masteryMap[s.cn];
          return m != null && (m.knownCount + m.unknownCount) > 0;
        };
        sortKey = (m) => -(m.knownCount + m.unknownCount);
        break;
      case 'studied':
      default:
        title = '已学习';
        test = (s) {
          final m = masteryMap[s.cn];
          return m != null && (m.knownCount > 0 || m.unknownCount > 0);
        };
    }
    final list = _species.where(test).toList();
    if (sortKey != null) {
      final key = sortKey;
      list.sort(
          (a, b) => key(masteryMap[a.cn]!).compareTo(key(masteryMap[b.cn]!)));
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _StatSpeciesListScreen(
          title: title,
          species: list,
          storage: widget.storage,
          onJumpToFlashcard: widget.onJumpToFlashcard,
        ),
      ),
    );
  }

  /// 新手教程横幅：与「更新提示」同样式，可关闭，点击进完整图文教程。
  Widget _tutorialBanner() {
    const green = Color(0xFF2d5016);
    return Material(
      color: green.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TutorialScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.menu_book_outlined, size: 18, color: green),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '新手教程 · 点这里看图文上手指南',
                  style: TextStyle(
                    color: green,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () async {
                  await widget.storage.dismissNewUserGuide();
                  if (mounted) setState(() => _guideDismissed = true);
                },
                icon: Icon(Icons.close,
                    size: 18, color: green.withValues(alpha: 0.75)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 打开当前数据包的「完成度」明细：已学 / 未学。
  void _openPackCompletion() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PackCompletionScreen(
          species: _species,
          storage: widget.storage,
          onJumpToFlashcard: widget.onJumpToFlashcard,
        ),
      ),
    );
  }

}

/// 统计卡片点击后展示的鸟种清单（已学习/已掌握/不熟悉/累计答题）。
class _StatSpeciesListScreen extends StatelessWidget {
  final String title;
  final List<Species> species;
  final StorageService storage;
  final void Function(Species species) onJumpToFlashcard;

  const _StatSpeciesListScreen({
    required this.title,
    required this.species,
    required this.storage,
    required this.onJumpToFlashcard,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$title（${species.length}）')),
      body: species.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '这里还没有鸟种',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: species.length,
              itemBuilder: (context, index) {
                final s = species[index];
                final m = storage.getMastery(s.cn);
                final total = m.knownCount + m.unknownCount;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text(s.cn,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text.rich(
                      TextSpan(
                        style: TextStyle(color: Colors.grey[700], height: 1.35),
                        children: [
                          TextSpan(
                            text: s.sci,
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                          TextSpan(
                            text:
                                '\n答对 ${m.knownCount} · 答错 ${m.unknownCount} · 共 $total 次 · 连续认识 ${m.knownStreak}',
                          ),
                        ],
                      ),
                    ),
                    isThreeLine: true,
                    trailing: FilledButton(
                      onPressed: () {
                        Navigator.pop(context);
                        onJumpToFlashcard(s);
                      },
                      child: const Text('去打卡'),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// 当前数据包「完成度」明细：未学的排前面，已学的打勾。
class _PackCompletionScreen extends StatelessWidget {
  final List<Species> species;
  final StorageService storage;
  final void Function(Species species) onJumpToFlashcard;

  const _PackCompletionScreen({
    required this.species,
    required this.storage,
    required this.onJumpToFlashcard,
  });

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF2d5016);
    bool studiedOf(Species s) {
      final m = storage.getMastery(s.cn);
      return m.knownCount > 0 || m.unknownCount > 0;
    }

    final studied = species.where(studiedOf).length;
    final total = species.length;
    final pct = total == 0 ? 0.0 : studied / total;
    // 未学的排前面，方便继续；同组内按中文名排序。
    final ordered = [...species]..sort((a, b) {
        final sa = studiedOf(a), sb = studiedOf(b);
        if (sa != sb) return sa ? 1 : -1;
        return a.cn.compareTo(b.cn);
      });

    return Scaffold(
      appBar: AppBar(title: const Text('学习完成度')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已学 $studied / $total 种 · ${(pct * 100).round()}%',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 8,
                    backgroundColor: green.withValues(alpha: 0.10),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFF2d7d32)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: total == 0
                ? Center(
                    child: Text('当前数据包没有鸟种',
                        style: TextStyle(color: Colors.grey[600])),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                    itemCount: ordered.length,
                    itemBuilder: (context, index) {
                      final s = ordered[index];
                      final done = studiedOf(s);
                      final m = storage.getMastery(s.cn);
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          done
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: done ? Colors.green : Colors.grey[400],
                          size: 20,
                        ),
                        title: Text(s.cn,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          done
                              ? '答对 ${m.knownCount} · 答错 ${m.unknownCount}'
                              : '还没学过',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        trailing: TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            onJumpToFlashcard(s);
                          },
                          child: const Text('去打卡'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
