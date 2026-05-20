import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/survey_project.dart';
import '../providers/survey_provider.dart';
import '../services/export_service.dart';

class SurveyProjectsScreen extends StatelessWidget {
  const SurveyProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SurveyProvider>();
    final projects = prov.surveyProjects;

    return Scaffold(
      appBar: AppBar(title: const Text('调查项目')),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _showEditDialog(context, prov, null),
      ),
      body: projects.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open, size: 64, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('还没有调查项目'),
                  SizedBox(height: 4),
                  Text(
                    '点击 + 创建项目，可将多个调查点归组并合并导出',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: projects.length,
              itemBuilder: (_, i) => _ProjectCard(project: projects[i]),
            ),
    );
  }

  Future<void> _showEditDialog(
    BuildContext context,
    SurveyProvider prov,
    SurveyProject? existing,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProjectEditSheet(existing: existing),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final SurveyProject project;
  const _ProjectCard({required this.project});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SurveyProvider>();
    final points = prov.pointsForProject(project);
    final sessions = prov.sessionsForProject(project);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.teal[100],
          child: Text(
            '${points.length}',
            style: TextStyle(color: Colors.teal[800], fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(project.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${points.length}个位点 · ${sessions.length}次调查'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (points.isEmpty)
                  const Text('暂无调查位点', style: TextStyle(color: Colors.grey))
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: points
                        .map((p) => Chip(
                              label: Text(p.name, style: const TextStyle(fontSize: 12)),
                              backgroundColor: Colors.green[50],
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                            ))
                        .toList(),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (sessions.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.table_chart, size: 16),
                        label: Text('合并导出(${sessions.length}次)'),
                        onPressed: () => _exportProject(context, sessions, project.name),
                      ),
                    TextButton.icon(
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('编辑'),
                      onPressed: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => _ProjectEditSheet(existing: project),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.delete, color: Colors.red, size: 16),
                      label: const Text('删除', style: TextStyle(color: Colors.red)),
                      onPressed: () => _confirmDelete(context, project),
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

  Future<void> _exportProject(
    BuildContext context,
    List sessions,
    String projectName,
  ) async {
    try {
      await ExportService.exportToExcel(
        sessions.cast(),
        projectName: projectName,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, SurveyProject project) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除项目'),
        content: Text('确认删除"${project.name}"？\n调查记录不会被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      context.read<SurveyProvider>().deleteSurveyProject(project.id);
    }
  }
}

class _ProjectEditSheet extends StatefulWidget {
  final SurveyProject? existing;
  const _ProjectEditSheet({this.existing});

  @override
  State<_ProjectEditSheet> createState() => _ProjectEditSheetState();
}

class _ProjectEditSheetState extends State<_ProjectEditSheet> {
  late final TextEditingController _nameCtrl;
  late Set<String> _selectedIds;
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _selectedIds = (widget.existing?.pointIds ?? []).toSet();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SurveyProvider>();
    final allPoints = prov.surveyPoints;
    final filtered = _filterQuery.isEmpty
        ? allPoints
        : allPoints
            .where((p) =>
                p.name.contains(_filterQuery) ||
                p.county.contains(_filterQuery) ||
                p.windFarm.contains(_filterQuery))
            .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Text(
                    widget.existing == null ? '新建项目' : '编辑项目',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _save,
                    child: const Text('保存', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '项目名称',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Text(
                    '选择调查位点（已选 ${_selectedIds.length}）',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (_selectedIds.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => _selectedIds.clear()),
                      child: const Text('清空'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: '搜索位点、县市、风电场…',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
                onChanged: (v) => setState(() => _filterQuery = v.trim()),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: allPoints.isEmpty
                  ? const Center(child: Text('还没有调查位点，请先导入'))
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final p = filtered[i];
                        final selected = _selectedIds.contains(p.id);
                        return CheckboxListTile(
                          value: selected,
                          dense: true,
                          title: Text(p.name),
                          subtitle: (p.county.isNotEmpty || p.windFarm.isNotEmpty)
                              ? Text(
                                  [p.county, p.windFarm].where((s) => s.isNotEmpty).join(' · '),
                                  style: const TextStyle(fontSize: 11),
                                )
                              : null,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selectedIds.add(p.id);
                            } else {
                              _selectedIds.remove(p.id);
                            }
                          }),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入项目名称')),
      );
      return;
    }
    final prov = context.read<SurveyProvider>();
    final project = SurveyProject(
      id: widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      pointIds: _selectedIds.toList(),
    );
    if (widget.existing == null) {
      await prov.addSurveyProject(project);
    } else {
      await prov.updateSurveyProject(project);
    }
    if (mounted) Navigator.pop(context);
  }
}
