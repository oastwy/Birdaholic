import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/survey_session.dart';
import '../providers/survey_provider.dart';
import '../services/export_service.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SurveyProvider>();
    final history = prov.history;

    return Scaffold(
      appBar: AppBar(
        title: const Text('历史调查'),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.table_chart),
              tooltip: '导出Excel',
              onPressed: () async {
                try {
                  await ExportService.exportToExcel(history);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
                  }
                }
              },
            ),
        ],
      ),
      body:
          history.isEmpty
              ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.history, size: 64, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('还没有调查记录'),
                  ],
                ),
              )
              : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: history.length,
                itemBuilder: (_, i) => _SurveyCard(session: history[i]),
              ),
    );
  }
}

class _SurveyCard extends StatelessWidget {
  final SurveySession session;
  const _SurveyCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final duration = session.endTime?.difference(session.startTime);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green[100],
          child: Text(
            '${session.speciesCount}',
            style: TextStyle(
              color: Colors.green[800],
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(df.format(session.startTime)),
        subtitle: Text(
          '${session.speciesCount}种 · ${session.totalCount}只'
          '${duration != null ? ' · ${_dur(duration)}' : ''}'
          '${session.tideHeight != null ? ' · 潮${session.tideHeight!.toStringAsFixed(2)}${session.tideUnit}' : ''}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Row(
                  icon: Icons.location_on,
                  text:
                      '${session.latitude.toStringAsFixed(5)}, ${session.longitude.toStringAsFixed(5)}',
                ),
                // Custom fields
                if (session.customValues.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    children:
                        session.customValues.entries
                            .map(
                              (e) => Text(
                                '${e.key}: ${e.value}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ],
                // Species
                if (session.observations.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    '记录鸟种：',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children:
                        session.observations.entries.where((e) => e.value > 0).map((
                          e,
                        ) {
                          final code = SurveySession.speciesCodeForKey(e.key);
                          final attrs = session.speciesFields[e.key] ?? {};
                          final suffix = attrs.values
                              .where((v) => v.isNotEmpty)
                              .join(' · ');
                          return Chip(
                            label: Text(
                              '${session.speciesNames[e.key] ?? session.speciesNames[code] ?? code}'
                              '${suffix.isNotEmpty ? '（$suffix）' : ''} ×${e.value}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            backgroundColor: Colors.green[50],
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            padding: EdgeInsets.zero,
                          );
                        }).toList(),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: Icon(
                        Icons.play_arrow,
                        size: 16,
                        color: Colors.green[700],
                      ),
                      label: Text(
                        '继续调查',
                        style: TextStyle(color: Colors.green[700]),
                      ),
                      onPressed: () async {
                        await context.read<SurveyProvider>().resumeSurvey(
                          session,
                        );
                        if (context.mounted) {
                          Navigator.of(context).pushNamed('/survey');
                        }
                      },
                    ),
                    // Export single survey
                    TextButton.icon(
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('导出Excel'),
                      onPressed: () async {
                        try {
                          await ExportService.exportToExcel([session]);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
                          }
                        }
                      },
                    ),
                    TextButton.icon(
                      icon: const Icon(
                        Icons.delete,
                        color: Colors.red,
                        size: 16,
                      ),
                      label: const Text(
                        '删除',
                        style: TextStyle(color: Colors.red),
                      ),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder:
                              (_) => AlertDialog(
                                title: const Text('确认删除'),
                                content: const Text('此操作不可撤销'),
                                actions: [
                                  TextButton(
                                    onPressed:
                                        () => Navigator.pop(context, false),
                                    child: const Text('取消'),
                                  ),
                                  TextButton(
                                    onPressed:
                                        () => Navigator.pop(context, true),
                                    child: const Text(
                                      '删除',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                        );
                        if (confirm == true &&
                            session.id != null &&
                            context.mounted) {
                          context.read<SurveyProvider>().deleteSurvey(
                            session.id!,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _dur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h${m}m' : '$m分钟';
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Row({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
      ],
    );
  }
}
