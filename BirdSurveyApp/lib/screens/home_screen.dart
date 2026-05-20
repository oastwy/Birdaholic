import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/survey_provider.dart';
import 'survey_screen.dart';
import 'survey_start_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SurveyProvider>();
    final isActive = prov.status == SurveyStatus.active;

    return Scaffold(
      appBar: AppBar(
        title: const Text('中国鸟类调查'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_special),
            tooltip: '调查项目',
            onPressed: () => Navigator.pushNamed(context, '/survey_projects'),
          ),
          IconButton(
            icon: const Icon(Icons.place),
            tooltip: '调查位点',
            onPressed: () => Navigator.pushNamed(context, '/survey_points'),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '历史记录',
            onPressed: () => Navigator.pushNamed(context, '/history'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeroCard(isActive: isActive, prov: prov),
            const SizedBox(height: 20),
            if (!isActive) _StatsRow(prov: prov),
            if (!isActive) const SizedBox(height: 20),
            _RecentSurveys(prov: prov),
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final bool isActive;
  final SurveyProvider prov;
  const _HeroCard({required this.isActive, required this.prov});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isActive
                ? [Colors.green[600]!, Colors.green[800]!]
                : [Colors.teal[400]!, Colors.green[700]!],
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flutter_dash, color: Colors.white, size: 40),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isActive ? '调查进行中' : '准备开始调查',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                    if (isActive && prov.currentSession != null)
                      Text(
                        '${prov.recordedSpecies.length}种 · '
                        '${prov.currentSession!.totalCount}只',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: Icon(isActive ? Icons.open_in_new : Icons.play_arrow),
                label: Text(
                  isActive ? '继续调查' : '开始新调查',
                  style: const TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.green[800],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  if (isActive) {
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SurveyScreen()));
                  } else {
                    Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const SurveyStartScreen()));
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final SurveyProvider prov;
  const _StatsRow({required this.prov});

  @override
  Widget build(BuildContext context) {
    final totalSurveys = prov.history.length;
    final totalSpecies =
        prov.history.expand((s) => s.observations.keys).toSet().length;
    final totalBirds = prov.history.fold(0, (a, b) => a + b.totalCount);

    return Row(
      children: [
        _StatCard('调查次数', '$totalSurveys', Icons.assignment),
        const SizedBox(width: 10),
        _StatCard('累计鸟种', '$totalSpecies', Icons.category),
        const SizedBox(width: 10),
        _StatCard('累计数量', '$totalBirds', Icons.numbers),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _StatCard(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: Colors.green[600], size: 24),
              const SizedBox(height: 4),
              Text(value,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700])),
              Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentSurveys extends StatelessWidget {
  final SurveyProvider prov;
  const _RecentSurveys({required this.prov});

  @override
  Widget build(BuildContext context) {
    final recent = prov.history.take(3).toList();
    if (recent.isEmpty) return const SizedBox();
    final df = DateFormat('MM-dd HH:mm');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('最近调查',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700])),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/history'),
              child: const Text('全部'),
            ),
          ],
        ),
        ...recent.map((s) {
          final pointName = s.customValues['位点名称'] ??
              s.customValues['地点名称'] ?? '';
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.green[100],
              child: Text('${s.speciesCount}',
                  style: TextStyle(
                      color: Colors.green[800],
                      fontWeight: FontWeight.bold)),
            ),
            title: Text(
              pointName.isNotEmpty ? pointName : df.format(s.startTime),
            ),
            subtitle: Text(
              '${df.format(s.startTime)} · ${s.speciesCount}种 · ${s.totalCount}只'
              '${s.tideHeight != null ? ' · 潮${s.tideHeight!.toStringAsFixed(1)}m' : ''}',
            ),
            trailing: const Icon(Icons.chevron_right),
            contentPadding: EdgeInsets.zero,
            onTap: () => Navigator.pushNamed(context, '/history'),
          );
        }),
      ],
    );
  }
}
