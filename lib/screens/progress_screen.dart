import 'package:flutter/material.dart';

import '../models/species.dart';
import '../services/pack_manager.dart';
import '../services/storage.dart';
import '../widgets/bird_card.dart';
import 'progress_detail_screen.dart';

class ProgressScreen extends StatefulWidget {
  final PackManager packManager;
  final StorageService storage;
  final void Function(String filter, StudyMode mode) onStartSession;
  final void Function(Species species) onJumpToFlashcard;
  final int refreshToken;
  final bool isActive;

  const ProgressScreen({
    super.key,
    required this.packManager,
    required this.storage,
    required this.onStartSession,
    required this.onJumpToFlashcard,
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

  @override
  void initState() {
    super.initState();
    _load();
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
    final unfamiliarNames = widget.storage.getUnfamiliarSpecies();
    final weakSpecies = _buildWeakSpecies(masteryMap);

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
                '先去“数据包”安装试用包或导入自己的鸟种包，之后这里会显示复习建议。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF23401A), Color(0xFF426B28)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '开始学习',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _species.isEmpty
                      ? '当前数据包还没有鸟种'
                      : '已加载 ${_species.length} 种鸟，直接开始整组学习或优先练音频与不熟悉物种。',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), height: 1.45),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _heroAction(
                      icon: Icons.play_circle_fill,
                      label: '整组学习',
                      onTap: () => widget.onStartSession('all', StudyMode.preview),
                    ),
                    _heroAction(
                      icon: Icons.hearing,
                      label: '音频强化',
                      onTap: () => widget.onStartSession('audio', StudyMode.review),
                    ),
                    _heroAction(
                      icon: Icons.local_fire_department,
                      label: '复习不熟悉',
                      onTap: () => widget.onStartSession('unfamiliar', StudyMode.review),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _compactStatCard('已学习', '$studied', Colors.green)),
              const SizedBox(width: 10),
              Expanded(
                child: _compactStatCard(
                  '正确率',
                  '${(stats.accuracy * 100).round()}%',
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _compactStatCard('不熟悉', '${unfamiliarNames.length}', Colors.orange),
              ),
              const SizedBox(width: 10),
              Expanded(child: _compactStatCard('总答题', '${stats.total}', Colors.purple)),
            ],
          ),
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
            _emptyPanel('还没有不熟悉鸟种', '当你选择“不认识”时，这里会形成强化复习清单。')
          else
            ...weakSpecies.take(5).map((entry) {
              final species = entry.$1;
              final mastery = entry.$2;
              return _speciesCard(
                species: species,
                subtitle: '不认识 ${mastery.unknownCount} 次 · 连续认识 ${mastery.knownStreak} 次',
                chipLabel: mastery.unfamiliar ? '建议复习' : '观察中',
                chipColor: mastery.unfamiliar ? Colors.orange : Colors.blueGrey,
              );
            }),
        ],
      ),
    );
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

  Widget _heroAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF23401A),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Widget _compactStatCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: color)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
          ),
        ],
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
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
          Text(subtitle, style: TextStyle(color: Colors.grey[600], height: 1.4)),
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
        title: Text(species.cn, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${species.sci}\n$subtitle',
            style: TextStyle(color: Colors.grey[700], height: 1.35),
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
                style: TextStyle(fontSize: 11, color: chipColor, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => widget.onJumpToFlashcard(species),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('去学习', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}
