import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/species.dart';
import '../services/app_update_service.dart';
import '../services/pack_manager.dart';
import '../services/podcast_service.dart';
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
  PodcastEpisode? _podcastEpisode;
  AppUpdateInfo? _updateInfo;
  bool _podcastLoading = true;
  bool _updateLoading = true;
  int _homeBannerPage = 0;
  bool _guideDismissed = false;
  // 打卡日历当前显示的月份（取该月第一天）
  DateTime _calendarMonth =
      DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _load();
    _loadPodcast();
    _loadUpdateInfo();
    _guideDismissed = widget.storage.isNewUserGuideDismissed;
  }

  Future<void> _loadPodcast() async {
    final ep = await PodcastService.fetchLatestEpisode();
    if (!mounted) return;
    setState(() {
      _podcastEpisode = ep;
      _podcastLoading = false;
    });
  }

  Future<void> _loadUpdateInfo() async {
    final info = await AppUpdateService.fetchLatest();
    if (!mounted) return;
    setState(() {
      _updateInfo = info;
      _updateLoading = false;
    });
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
    final currentPackProgress =
        _species.isEmpty ? 0.0 : currentPackStudied / _species.length;
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
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _species.isEmpty
                          ? null
                          : () => widget.onStartSession(
                                'all',
                                StudyMode.review,
                                PromptMode.audio,
                              ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2d7d32),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey[300],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.headphones_rounded, size: 22),
                      label: const Text(
                        '打卡',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: widget.onJumpToPreview,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.auto_stories_rounded, size: 22),
                      label: const Text(
                        '预习',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (!_guideDismissed) ...[
              _newUserGuideCard(),
              const SizedBox(height: 14),
            ],
            _homeBannerCarousel(
              currentPackStudied: currentPackStudied,
              currentPackTotal: _species.length,
              currentPackProgress: currentPackProgress,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                    child: _compactStatCard('已学习', '$studied', Colors.blue,
                        onTap: () => _openStatSpeciesList('studied'))),
                const SizedBox(width: 10),
                Expanded(
                  child: _compactStatCard(
                    '已掌握',
                    '$mastered',
                    Colors.green,
                    onTap: () => _openStatSpeciesList('mastered'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _compactStatCard(
                      '不熟悉', '${unfamiliarNames.length}', Colors.red,
                      onTap: () => _openStatSpeciesList('unfamiliar')),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: _compactStatCard(
                        '累计答题', '${stats.total}', Colors.amber,
                        onTap: () => _openStatSpeciesList('answered'))),
              ],
            ),
            const SizedBox(height: 10),
            _checkInCalendar(checkInDates),
            const SizedBox(height: 10),
            OutlinedButton.icon(
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
              icon: const Icon(Icons.insights_outlined),
              label: const Text('查看学习详情'),
            ),
            const SizedBox(height: 20),
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

  Widget _checkInCalendar(Set<String> dates) {
    final streak = _currentStreak(dates);
    final today = DateTime.now();
    final todayKey = today.toIso8601String().substring(0, 10);
    final month = _calendarMonth;
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // weekday: Mon=1..Sun=7；本日历以周日为第一列
    final leadingBlanks = firstOfMonth.weekday % 7;
    final thisMonth = DateTime(today.year, today.month);
    final canGoNext = month.isBefore(thisMonth);

    const weekHeaders = ['日', '一', '二', '三', '四', '五', '六'];

    // 构建格子：前导空白 + 当月各天
    final cells = <Widget?>[
      ...List<Widget?>.filled(leadingBlanks, null),
      ...List.generate(daysInMonth, (i) {
        final day = i + 1;
        final date = DateTime(month.year, month.month, day);
        final key = date.toIso8601String().substring(0, 10);
        final checked = dates.contains(key);
        final isToday = key == todayKey;
        return _calendarDayCell(day: day, checked: checked, isToday: isToday);
      }),
    ];
    // 补齐到 7 的倍数
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: List.generate(7, (j) {
            final cell = cells[i + j];
            return Expanded(
              child: Center(child: cell ?? const SizedBox(height: 34)),
            );
          }),
        ),
      ));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_month_outlined, size: 20),
                const SizedBox(width: 8),
                const Text('打卡日历',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(
                  '连续 $streak 天',
                  style: TextStyle(
                    color: streak > 0 ? Colors.green[700] : Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 月份切换条
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left, size: 22),
                  onPressed: () => setState(() {
                    _calendarMonth =
                        DateTime(month.year, month.month - 1, 1);
                  }),
                ),
                Expanded(
                  child: Text(
                    '${month.year} 年 ${month.month} 月',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.chevron_right,
                      size: 22,
                      color: canGoNext ? null : Colors.grey[300]),
                  onPressed: canGoNext
                      ? () => setState(() {
                            _calendarMonth =
                                DateTime(month.year, month.month + 1, 1);
                          })
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: weekHeaders
                  .map((h) => Expanded(
                        child: Center(
                          child: Text(
                            h,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500]),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 4),
            ...rows,
          ],
        ),
      ),
    );
  }

  Widget _calendarDayCell({
    required int day,
    required bool checked,
    required bool isToday,
  }) {
    return SizedBox(
      height: 34,
      child: Center(
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: checked ? const Color(0xFF2d5016) : Colors.transparent,
            shape: BoxShape.circle,
            border: isToday && !checked
                ? Border.all(color: const Color(0xFF2d5016), width: 1.4)
                : null,
          ),
          child: Center(
            child: checked
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 12,
                      color: isToday
                          ? const Color(0xFF2d5016)
                          : Colors.grey[700],
                      fontWeight:
                          isToday ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
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
      list.sort((a, b) =>
          key(masteryMap[a.cn]!).compareTo(key(masteryMap[b.cn]!)));
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2d5016).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF2d5016).withValues(alpha: 0.12),
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
          const SizedBox(height: 10),
          _guideStep('1', '先装“中国常见鸟 100”，不填 API key 也能开始。'),
          const SizedBox(height: 6),
          _guideStep('2', '去“预习”看图、听声、记特征，再回首页打卡。'),
          const SizedBox(height: 6),
          _guideStep('3', '打卡时左右换同种照片，上滑认识，下滑不认识。'),
        ],
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

  Widget _homeBannerCarousel({
    required int currentPackStudied,
    required int currentPackTotal,
    required double currentPackProgress,
  }) {
    return Column(
      children: [
        SizedBox(
          height: 136,
          child: PageView(
            onPageChanged: (index) {
              setState(() => _homeBannerPage = index);
            },
            children: [
              _podcastCard(),
              _updateNoticeCard(
                studied: currentPackStudied,
                total: currentPackTotal,
                progress: currentPackProgress,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(2, (index) {
            final active = _homeBannerPage == index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active ? const Color(0xFF2d5016) : Colors.grey[300],
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _updateNoticeCard({
    required int studied,
    required int total,
    required double progress,
  }) {
    final percent = (progress * 100).round();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => launchUrl(
          Uri.parse(_updateInfo?.downloadUrl ?? AppUpdateService.downloadUrl),
          mode: LaunchMode.externalApplication,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.campaign_outlined,
                      size: 16, color: Color(0xFF2d5016)),
                  SizedBox(width: 6),
                  Text(
                    '更新通知',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2d5016),
                    ),
                  ),
                  Spacer(),
                  Icon(Icons.swipe_rounded, size: 15, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _updateLoading
                              ? '正在检查最新版本...'
                              : (_updateInfo == null
                                  ? '打开下载页查看最新版'
                                  : '${_updateInfo!.title}'
                                      '${_updateInfo!.releaseDate.isEmpty ? '' : ' · ${_updateInfo!.releaseDate}'}'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: progress.clamp(0, 1),
                            minHeight: 8,
                            backgroundColor: Colors.grey[200],
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF2d5016),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _updateInfo?.version ?? '$percent%',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2d5016),
                        ),
                      ),
                      Text(
                        _updateInfo == null ? '$studied/$total 种' : '下载页',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _podcastCard() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => launchUrl(
          Uri.parse(PodcastService.podcastWebUrl),
          mode: LaunchMode.externalApplication,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.mic_none_outlined,
                      size: 16, color: Color(0xFF2d5016)),
                  SizedBox(width: 6),
                  Text(
                    '鸟瘾综合征 · 最新一期',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2d5016),
                    ),
                  ),
                  Spacer(),
                  Icon(Icons.arrow_forward_ios, size: 13, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 10),
              if (_podcastLoading)
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              height: 14,
                              width: double.infinity,
                              color: Colors.grey[200]),
                          const SizedBox(height: 8),
                          Container(
                              height: 12, width: 80, color: Colors.grey[200]),
                        ],
                      ),
                    ),
                  ],
                )
              else if (_podcastEpisode == null)
                Text(
                  '暂时无法加载最新一期，点击前往小宇宙',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_podcastEpisode!.imageUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          _podcastEpisode!.imageUrl,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 60,
                            height: 60,
                            color: Colors.grey[200],
                            child:
                                const Icon(Icons.podcasts, color: Colors.grey),
                          ),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _podcastEpisode!.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _podcastEpisode!.pubDate,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactStatCard(String title, String value, Color color,
      {VoidCallback? onTap}) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: TextStyle(fontSize: 12, color: color)),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, size: 14, color: color),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: card,
      ),
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
                            style:
                                const TextStyle(fontStyle: FontStyle.italic),
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
