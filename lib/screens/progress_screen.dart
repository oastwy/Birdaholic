import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_version.dart';
import '../models/species.dart';
import '../services/app_update_service.dart';
import '../services/pack_manager.dart';
import '../services/storage.dart';
import '../widgets/bird_card.dart';
import 'progress_detail_screen.dart';

class ProgressScreen extends StatefulWidget {
  final PackManager packManager;
  final StorageService storage;
  final void Function(String filter, StudyMode mode, PromptMode promptMode)
      onStartSession;
  final void Function(Species species) onJumpToFlashcard;
  final VoidCallback? onJumpToPreview;
  final int refreshToken;
  final bool isActive;

  const ProgressScreen({
    super.key,
    required this.packManager,
    required this.storage,
    required this.onStartSession,
    required this.onJumpToFlashcard,
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

  Widget _updateBanner() {
    final hasNew = !_updateLoading &&
        _updateInfo != null &&
        _updateInfo!.version != appVersionName;
    final bg = hasNew
        ? const Color(0xFF2d5016)
        : Colors.grey.withValues(alpha: 0.10);
    final fg = hasNew ? Colors.white : Colors.grey[700]!;
    final text = _updateLoading
        ? '正在检查更新…'
        : hasNew
            ? '有新版本 ${_updateInfo!.version} · 点击下载'
            : '已是最新版本 v$appVersionName';
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openUrl(
          _updateInfo?.downloadUrl ?? AppUpdateService.downloadUrl,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(
                hasNew ? Icons.system_update_alt : Icons.check_circle_outline,
                size: 18,
                color: fg,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: hasNew ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18, color: fg.withValues(alpha: 0.7)),
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
    final weakSpecies = _buildWeakSpecies(masteryMap);
    final checkInDates = widget.storage.getCheckInDates();

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

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (Platform.isAndroid) ...[
              _updateBanner(),
              const SizedBox(height: 12),
            ],
            _todayPracticeCard(currentPackStudied: currentPackStudied),
            const SizedBox(height: 12),
            if (!_guideDismissed) ...[
              _newUserGuideCard(),
              const SizedBox(height: 12),
            ],
            _studyOverviewCard(
              studied: studied,
              mastered: mastered,
              unfamiliar: unfamiliarNames.length,
              answered: stats.total,
            ),
            const SizedBox(height: 10),
            _checkInCalendar(checkInDates),
            const SizedBox(height: 18),
            _sectionHeader(
              '建议优先复习',
              actionLabel: unfamiliarNames.isEmpty ? null : '清空不熟悉',
              onAction: unfamiliarNames.isEmpty
                  ? null
                  : () async {
                      await widget.storage.clearUnfamiliar();
                      if (!mounted) return;
                      setState(() {});
                    },
            ),
            const SizedBox(height: 8),
            if (weakSpecies.isEmpty)
              _emptyPanel('还没有不熟悉鸟种', '答错或选择“不认识”的鸟会进入这里；连续认识后会移出。')
            else
              ...weakSpecies.take(5).map((entry) {
                final species = entry.$1;
                final mastery = entry.$2;
                return _speciesCard(
                  species: species,
                  subtitle:
                      '不认识 ${mastery.unknownCount} 次 · 连续认识 ${mastery.knownStreak} 次',
                  chipLabel: mastery.unfamiliar ? '建议复习' : '观察中',
                  chipColor:
                      mastery.unfamiliar ? Colors.orange : Colors.blueGrey,
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _todayPracticeCard({required int currentPackStudied}) {
    final total = _species.length;
    final progress = total == 0 ? 0.0 : currentPackStudied / total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFFF7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF2d5016).withValues(alpha: 0.12),
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
                  color: const Color(0xFF2d5016).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.headphones_rounded,
                  color: Color(0xFF2d5016),
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '今日练习',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '听声打卡，预习补图像和特征',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF2d5016).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  total == 0 ? '未安装数据包' : '$currentPackStudied/$total 种',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF2d5016),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 6,
              backgroundColor: const Color(0xFF2d5016).withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF2d7d32),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 22),
                    label: const Text(
                      '开始打卡',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: widget.onJumpToPreview,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1565C0),
                      side: BorderSide(
                        color: const Color(0xFF1565C0).withValues(alpha: 0.35),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.auto_stories_rounded, size: 20),
                    label: const Text(
                      '预习鸟种',
                      style: TextStyle(fontWeight: FontWeight.w800),
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

  Widget _checkInCalendar(Set<String> dates) {
    final streak = _currentStreak(dates);
    final today = DateTime.now();
    final days = List.generate(
      14,
      (i) => today.subtract(Duration(days: 13 - i)),
    );
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_month_outlined, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '打卡日历',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  '连续 $streak 天',
                  style: TextStyle(
                    color: streak > 0 ? Colors.green[700] : Colors.grey[600],
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
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
            const SizedBox(height: 8),
            Row(
              children: days.map((day) {
                final key = day.toIso8601String().substring(0, 10);
                final isToday = key == today.toIso8601String().substring(0, 10);
                return Expanded(
                  child: _stripDayCell(
                    date: day,
                    checked: dates.contains(key),
                    isToday: isToday,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stripDayCell({
    required DateTime date,
    required bool checked,
    required bool isToday,
  }) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          weekdays[date.weekday - 1],
          style: TextStyle(fontSize: 10, color: Colors.grey[500]),
        ),
        const SizedBox(height: 5),
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: checked ? const Color(0xFF2d5016) : Colors.transparent,
            shape: BoxShape.circle,
            border: isToday || (!checked && date.day == 1)
                ? Border.all(color: const Color(0xFF2d5016), width: 1.3)
                : null,
          ),
          child: checked
              ? const Icon(Icons.check, color: Colors.white, size: 14)
              : Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isToday ? const Color(0xFF2d5016) : Colors.grey[700],
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
        ),
      ],
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

  List<(Species, SpeciesMastery)> _buildWeakSpecies(
    Map<String, SpeciesMastery> masteryMap,
  ) {
    final mapped = _species
        .where((species) => masteryMap.containsKey(species.cn))
        .map((species) => (species, masteryMap[species.cn]!))
        .where((entry) => entry.$2.unfamiliar || entry.$2.unknownCount > 0)
        .toList();

    mapped.sort((a, b) {
      final scoreA = a.$2.unknownCount * 10 - a.$2.knownStreak;
      final scoreB = b.$2.unknownCount * 10 - b.$2.knownStreak;
      return scoreB.compareTo(scoreA);
    });
    return mapped;
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

  Widget _newUserGuideCard() {
    return Material(
      elevation: 7,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      color: const Color(0xFFFAFFF7),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF2d5016).withValues(alpha: 0.14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tips_and_updates_outlined,
                    size: 18, color: Color(0xFF2d5016)),
                const SizedBox(width: 8),
                const Text(
                  '新手三步',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '关闭新手引导',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await widget.storage.dismissNewUserGuide();
                    if (mounted) setState(() => _guideDismissed = true);
                  },
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _guideStep('1', '先装“中国常见鸟 100”，不填 API key 也能开始。'),
            const SizedBox(height: 6),
            _guideStep('2', '去“预习”看图、听声、记特征，再回首页打卡。'),
            const SizedBox(height: 6),
            _guideStep('3', '打卡时左右换同种照片，上滑认识，下滑不认识。'),
          ],
        ),
      ),
    );
  }

  Widget _guideStep(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFF2d5016),
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: Colors.grey[800]),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(
    String title, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Row(
      children: [
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Spacer(),
        if (actionLabel != null && onAction != null)
          TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }

  Widget _emptyPanel(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: TextStyle(color: Colors.grey[600], height: 1.4)),
        ],
      ),
    );
  }

  Widget _speciesCard({
    required Species species,
    required String subtitle,
    required String chipLabel,
    required Color chipColor,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: Text(species.cn,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: species.sci,
                style: TextStyle(
                    color: Colors.grey[700],
                    height: 1.35,
                    fontStyle: FontStyle.italic),
              ),
              TextSpan(
                text: '\n$subtitle',
                style: TextStyle(color: Colors.grey[700], height: 1.35),
              ),
            ]),
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: chipColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                chipLabel,
                style: TextStyle(
                    fontSize: 11,
                    color: chipColor,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => widget.onJumpToFlashcard(species),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('去打卡', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
        isThreeLine: true,
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
