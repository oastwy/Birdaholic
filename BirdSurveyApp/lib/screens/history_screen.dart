import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/history_folder.dart';
import '../models/survey_session.dart';
import '../models/survey_version.dart';
import '../providers/survey_provider.dart';
import '../services/export_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _query = '';
  String _folderId = '';
  bool _ascending = false;
  bool _selectMode = false;
  final Set<int> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SurveyProvider>();
    var displayed =
        prov.history.where((session) {
            if (_folderId.isNotEmpty && session.folderId != _folderId) {
              return false;
            }
            final q = _query.trim().toLowerCase();
            if (q.isEmpty) return true;
            final haystack =
                [
                  _displayTitle(session),
                  session.customValues.values.join(' '),
                  session.speciesNames.values.join(' '),
                  session.notes,
                ].join(' ').toLowerCase();
            return haystack.contains(q);
          }).toList()
          ..sort(
            (a, b) =>
                _ascending
                    ? a.startTime.compareTo(b.startTime)
                    : b.startTime.compareTo(a.startTime),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('历史调查'),
        actions: [
          if (displayed.isNotEmpty)
            IconButton(
              icon: Icon(_selectMode ? Icons.close : Icons.checklist),
              tooltip: _selectMode ? '退出多选' : '多选',
              onPressed:
                  () => setState(() {
                    _selectMode = !_selectMode;
                    _selectedIds.clear();
                  }),
            ),
          if (_selectMode && _selectedIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.table_chart),
              tooltip: '导出已选',
              onPressed:
                  () => _export(
                    displayed
                        .where(
                          (s) => s.id != null && _selectedIds.contains(s.id),
                        )
                        .toList(),
                  ),
            ),
          IconButton(
            icon: Icon(_ascending ? Icons.arrow_upward : Icons.arrow_downward),
            tooltip: _ascending ? '按时间升序' : '按时间降序',
            onPressed: () => setState(() => _ascending = !_ascending),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            tooltip: '新建文件夹',
            onPressed: () => _showFolderDialog(context, prov),
          ),
          if (displayed.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.table_chart),
              tooltip: '导出当前列表',
              onPressed: _selectMode ? null : () => _export(displayed),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索标题、地点、鸟种、备注...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon:
                    _query.isEmpty
                        ? null
                        : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _query = ''),
                        ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          _FolderBar(
            folders: prov.historyFolders,
            selectedId: _folderId,
            sessions: prov.history,
            onSelect: (id) => setState(() => _folderId = id),
            onRename: (folder) => _showFolderDialog(context, prov, folder),
            onDelete: (folder) => _deleteFolder(context, prov, folder),
          ),
          Expanded(
            child:
                displayed.isEmpty
                    ? const Center(child: Text('没有符合条件的调查记录'))
                    : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: displayed.length,
                      itemBuilder:
                          (_, i) => _SurveyCard(
                            session: displayed[i],
                            folders: prov.historyFolders,
                            onRename:
                                () =>
                                    _renameSurvey(context, prov, displayed[i]),
                            onMove:
                                () => _moveSurvey(context, prov, displayed[i]),
                            onVersions:
                                () =>
                                    _showVersions(context, prov, displayed[i]),
                            onResume: () async {
                              await prov.resumeSurvey(displayed[i]);
                              if (context.mounted) {
                                Navigator.of(context).pushNamed('/survey');
                              }
                            },
                            onExport:
                                () =>
                                    ExportService.exportToExcel([displayed[i]]),
                            onDelete:
                                () =>
                                    _deleteSurvey(context, prov, displayed[i]),
                            selectable: _selectMode,
                            selected:
                                displayed[i].id != null &&
                                _selectedIds.contains(displayed[i].id),
                            onSelect:
                                displayed[i].id == null
                                    ? null
                                    : () => setState(() {
                                      final id = displayed[i].id!;
                                      if (_selectedIds.contains(id)) {
                                        _selectedIds.remove(id);
                                      } else {
                                        _selectedIds.add(id);
                                      }
                                    }),
                          ),
                    ),
          ),
        ],
      ),
    );
  }

  Future<void> _export(List<SurveySession> sessions) async {
    try {
      await ExportService.exportToExcel(sessions);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  String _displayTitle(SurveySession session) {
    if (session.title.trim().isNotEmpty) return session.title.trim();
    return DateFormat('yyyy-MM-dd HH:mm').format(session.startTime);
  }

  Future<void> _showFolderDialog(
    BuildContext context,
    SurveyProvider prov, [
    HistoryFolder? folder,
  ]) async {
    final ctrl = TextEditingController(text: folder?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(folder == null ? '新建文件夹' : '重命名文件夹'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '文件夹名称',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, ctrl.text),
                child: const Text('保存'),
              ),
            ],
          ),
    );
    if (name == null || name.trim().isEmpty) return;
    if (folder == null) {
      await prov.addHistoryFolder(name);
    } else {
      await prov.renameHistoryFolder(folder.id, name);
    }
  }

  Future<void> _deleteFolder(
    BuildContext context,
    SurveyProvider prov,
    HistoryFolder folder,
  ) async {
    final ok = await prov.deleteHistoryFolder(folder.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(ok ? '文件夹已删除' : '文件夹内还有记录，不能删除')));
  }

  Future<void> _renameSurvey(
    BuildContext context,
    SurveyProvider prov,
    SurveySession session,
  ) async {
    final ctrl = TextEditingController(text: _displayTitle(session));
    final title = await showDialog<String>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('重命名调查记录'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '记录名称',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, ctrl.text),
                child: const Text('保存'),
              ),
            ],
          ),
    );
    if (title == null || title.trim().isEmpty || session.id == null) return;
    await prov.renameSurvey(session.id!, title);
  }

  Future<void> _moveSurvey(
    BuildContext context,
    SurveyProvider prov,
    SurveySession session,
  ) async {
    final folderId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder:
          (_) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.inbox),
                  title: const Text('未归档'),
                  onTap: () => Navigator.pop(context, ''),
                ),
                ...prov.historyFolders.map(
                  (folder) => ListTile(
                    leading: const Icon(Icons.folder),
                    title: Text(folder.name),
                    onTap: () => Navigator.pop(context, folder.id),
                  ),
                ),
              ],
            ),
          ),
    );
    if (folderId == null || session.id == null) return;
    await prov.moveSurveyToFolder(session.id!, folderId);
  }

  Future<void> _showVersions(
    BuildContext context,
    SurveyProvider prov,
    SurveySession session,
  ) async {
    if (session.id == null) return;
    final versions = await prov.versionsForSurvey(session.id!);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (_) => _VersionsSheet(
            versions: versions,
            onRestore: (version) async {
              await prov.restoreSurveyVersion(version);
              if (context.mounted) Navigator.pop(context);
            },
          ),
    );
  }

  Future<void> _deleteSurvey(
    BuildContext context,
    SurveyProvider prov,
    SurveySession session,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('确认删除'),
            content: const Text('此操作不可撤销，历史版本也会一起删除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );
    if (confirm == true && session.id != null) {
      await prov.deleteSurvey(session.id!);
    }
  }
}

class _FolderBar extends StatelessWidget {
  final List<HistoryFolder> folders;
  final String selectedId;
  final List<SurveySession> sessions;
  final ValueChanged<String> onSelect;
  final ValueChanged<HistoryFolder> onRename;
  final ValueChanged<HistoryFolder> onDelete;

  const _FolderBar({
    required this.folders,
    required this.selectedId,
    required this.sessions,
    required this.onSelect,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text('全部 ${sessions.length}'),
              selected: selectedId.isEmpty,
              onSelected: (_) => onSelect(''),
            ),
          ),
          ...folders.map((folder) {
            final count = sessions.where((s) => s.folderId == folder.id).length;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InputChip(
                label: Text('${folder.name} $count'),
                selected: selectedId == folder.id,
                onSelected: (_) => onSelect(folder.id),
                onPressed: () => onSelect(folder.id),
                onDeleted: () => onDelete(folder),
                deleteIcon: const Icon(Icons.close, size: 16),
                avatar: GestureDetector(
                  onLongPress: () => onRename(folder),
                  child: const Icon(Icons.folder, size: 16),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _SurveyCard extends StatelessWidget {
  final SurveySession session;
  final List<HistoryFolder> folders;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onVersions;
  final VoidCallback onResume;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final bool selectable;
  final bool selected;
  final VoidCallback? onSelect;

  const _SurveyCard({
    required this.session,
    required this.folders,
    required this.onRename,
    required this.onMove,
    required this.onVersions,
    required this.onResume,
    required this.onExport,
    required this.onDelete,
    this.selectable = false,
    this.selected = false,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final title =
        session.title.trim().isNotEmpty
            ? session.title.trim()
            : df.format(session.startTime);
    final duration = session.endTime?.difference(session.startTime);
    final folder = folders.cast<HistoryFolder?>().firstWhere(
      (f) => f?.id == session.folderId,
      orElse: () => null,
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading:
            selectable
                ? Checkbox(value: selected, onChanged: (_) => onSelect?.call())
                : CircleAvatar(
                  backgroundColor: Colors.green[100],
                  child: Text(
                    '${session.speciesCount}',
                    style: TextStyle(
                      color: Colors.green[800],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
        onExpansionChanged: selectable ? (_) => onSelect?.call() : null,
        initiallyExpanded: false,
        title: Text(title),
        subtitle: Text(
          '${session.speciesCount}种 · ${session.totalCount}只'
          '${duration != null ? ' · ${_dur(duration)}' : ''}'
          '${folder != null ? ' · ${folder.name}' : ''}',
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'rename':
                onRename();
                break;
              case 'move':
                onMove();
                break;
              case 'versions':
                onVersions();
                break;
              case 'export':
                onExport();
                break;
              case 'delete':
                onDelete();
                break;
            }
          },
          itemBuilder:
              (_) => const [
                PopupMenuItem(value: 'rename', child: Text('重命名')),
                PopupMenuItem(value: 'move', child: Text('移动到文件夹')),
                PopupMenuItem(value: 'versions', child: Text('历史版本')),
                PopupMenuItem(value: 'export', child: Text('导出 Excel')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Row(
                  icon: Icons.schedule,
                  text:
                      '${df.format(session.startTime)} - '
                      '${session.endTime != null ? df.format(session.endTime!) : '未结束'}',
                ),
                _Row(
                  icon: Icons.location_on,
                  text:
                      '${session.latitude.toStringAsFixed(5)}, ${session.longitude.toStringAsFixed(5)}',
                ),
                if (session.weather?.isNotEmpty == true)
                  _Row(icon: Icons.wb_sunny, text: session.weather!),
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
                          return Chip(
                            label: Text(
                              '${session.speciesNames[e.key] ?? session.speciesNames[code] ?? code} ×${e.value}',
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
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('编辑记录'),
                    onPressed: onResume,
                  ),
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

class _VersionsSheet extends StatelessWidget {
  final List<SurveyVersion> versions;
  final ValueChanged<SurveyVersion> onRestore;

  const _VersionsSheet({required this.versions, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd HH:mm:ss');
    return SafeArea(
      child:
          versions.isEmpty
              ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('还没有历史版本')),
              )
              : ListView.builder(
                itemCount: versions.length,
                itemBuilder: (_, i) {
                  final version = versions[i];
                  return ListTile(
                    leading: const Icon(Icons.restore),
                    title: Text(df.format(version.savedAt)),
                    subtitle: Text(
                      '${version.summary.isEmpty ? '保存前版本' : version.summary} · '
                      '${version.snapshot.speciesCount}种 / ${version.snapshot.totalCount}只',
                    ),
                    trailing: TextButton(
                      onPressed: () => onRestore(version),
                      child: const Text('恢复'),
                    ),
                  );
                },
              ),
    );
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
