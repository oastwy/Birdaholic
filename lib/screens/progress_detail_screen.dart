import 'package:flutter/material.dart';

import '../models/species.dart';
import '../services/storage.dart';

class ProgressDetailScreen extends StatelessWidget {
  final StorageService storage;
  final List<Species> species;
  final void Function(Species species) onJumpToFlashcard;

  const ProgressDetailScreen({
    super.key,
    required this.storage,
    required this.species,
    required this.onJumpToFlashcard,
  });

  @override
  Widget build(BuildContext context) {
    final stats = storage.getStats();
    final masteryMap = storage.getAllMastery();
    final studied = masteryMap.values
        .where((m) => m.knownCount > 0 || m.unknownCount > 0)
        .length;
    final unfamiliar = storage.getUnfamiliarSpecies();
    final recentSpecies = _buildRecentSpecies(species, masteryMap);

    return Scaffold(
      appBar: AppBar(title: const Text('学习详情')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1F4A3B), Color(0xFF3E8A63)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '学习详情',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '学习过 $studied 种，累计答题 ${stats.total} 次，当前正确率 ${(stats.accuracy * 100).round()}%。',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9), height: 1.45),
                ),
              ],
            ),
          ),
          // 统计卡片已与主页「学习概览」（可点进对应清单）合并，这里不再重复展示，
          // 详情页只保留下面的「最近学习轨迹」。
          const SizedBox(height: 20),
          Row(
            children: [
              const Text(
                '最近学习轨迹',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (unfamiliar.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    await storage.clearUnfamiliar();
                    if (context.mounted) {
                      Navigator.pop(context, true);
                    }
                  },
                  child: const Text('清空不熟悉'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (recentSpecies.isEmpty)
            _emptyPanel('还没有学习轨迹', '开始一轮学习后，这里会出现最近答题的物种。')
          else
            ...recentSpecies.take(12).map((entry) {
              final item = entry.$1;
              final mastery = entry.$2;
              final knownLast = mastery.lastResult == 'known';
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Text(item.cn,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text.rich(
                    TextSpan(
                      style: TextStyle(color: Colors.grey[700], height: 1.35),
                      children: [
                        TextSpan(
                          text: item.sci,
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        ),
                        TextSpan(
                          text:
                              '\n${knownLast ? "最近一次答对" : "最近一次答错"} · ${_formatTime(mastery.lastTime)}',
                        ),
                      ],
                    ),
                  ),
                  isThreeLine: true,
                  trailing: FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onJumpToFlashcard(item);
                    },
                    child: const Text('去打卡'),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  List<(Species, SpeciesMastery)> _buildRecentSpecies(
    List<Species> species,
    Map<String, SpeciesMastery> masteryMap,
  ) {
    final mapped = species
        .where((item) => masteryMap.containsKey(item.cn))
        .map((item) => (item, masteryMap[item.cn]!))
        .where((entry) => entry.$2.lastTime.isNotEmpty)
        .toList();
    mapped.sort((a, b) => b.$2.lastTime.compareTo(a.$2.lastTime));
    return mapped;
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

  String _formatTime(String value) {
    final time = DateTime.tryParse(value);
    if (time == null) return value;
    return '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
