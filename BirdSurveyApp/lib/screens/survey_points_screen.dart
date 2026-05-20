import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/survey_point.dart';
import '../providers/survey_provider.dart';

class SurveyPointsScreen extends StatefulWidget {
  const SurveyPointsScreen({super.key});

  @override
  State<SurveyPointsScreen> createState() => _SurveyPointsScreenState();
}

class _SurveyPointsScreenState extends State<SurveyPointsScreen> {
  final Set<String> _selectedIds = {};
  bool _selectMode = false;
  String? _countyFilter;
  String? _windFarmFilter;

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) _selectedIds.clear();
    });
  }

  void _toggleItem(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(List<SurveyPoint> points) {
    setState(() => _selectedIds
      ..clear()
      ..addAll(points.map((p) => p.id)));
  }

  void _clearSelection() => setState(() => _selectedIds.clear());

  List<SurveyPoint> _applyFilter(List<SurveyPoint> all) {
    return all.where((p) {
      if (_countyFilter != null && p.county != _countyFilter) return false;
      if (_windFarmFilter != null && p.windFarm != _windFarmFilter) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SurveyProvider>();
    final all = prov.surveyPoints;
    final filtered = _applyFilter(all);
    final counties = prov.surveyPointCounties.toList()..sort();
    final windFarms = prov.surveyPointWindFarms.toList()..sort();
    final hasFilter = _countyFilter != null || _windFarmFilter != null;

    return Scaffold(
      appBar: AppBar(
        title: _selectMode
            ? Text('已选 ${_selectedIds.length} / ${filtered.length}')
            : Text('调查位点（${all.length}个）'),
        actions: [
          if (!_selectMode) ...[
            IconButton(
              icon: const Icon(Icons.upload_file),
              tooltip: '导入CSV/KML',
              onPressed: () => _importFile(context),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '手动添加',
              onPressed: () => _addManual(context),
            ),
            if (all.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.checklist),
                tooltip: '多选',
                onPressed: _toggleSelectMode,
              ),
          ] else ...[
            TextButton(
              onPressed: () => _selectAll(filtered),
              child: const Text('全选', style: TextStyle(color: Colors.white)),
            ),
            TextButton(
              onPressed: _clearSelection,
              child: const Text('清除', style: TextStyle(color: Colors.white)),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _toggleSelectMode,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // ── Filter bar ──────────────────────────────────────────────────
          if (counties.isNotEmpty || windFarms.isNotEmpty)
            Container(
              color: Colors.grey[100],
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Icon(Icons.filter_list,
                        size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    if (counties.isNotEmpty) ...[
                      _FilterChip(
                        label: _countyFilter ?? '县市',
                        active: _countyFilter != null,
                        options: counties,
                        onSelected: (v) =>
                            setState(() => _countyFilter = v),
                        onCleared: () =>
                            setState(() => _countyFilter = null),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (windFarms.isNotEmpty) ...[
                      _FilterChip(
                        label: _windFarmFilter ?? '风电场',
                        active: _windFarmFilter != null,
                        options: windFarms,
                        onSelected: (v) =>
                            setState(() => _windFarmFilter = v),
                        onCleared: () =>
                            setState(() => _windFarmFilter = null),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (hasFilter)
                      TextButton(
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(40, 28)),
                        onPressed: () => setState(() {
                          _countyFilter = null;
                          _windFarmFilter = null;
                        }),
                        child: const Text('清除筛选',
                            style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ),

          // ── List ─────────────────────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? _EmptyHint(
                    hasPoints: all.isNotEmpty,
                    onImport: () => _importFile(context),
                    onAdd: () => _addManual(context),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final p = filtered[i];
                      return _PointTile(
                        point: p,
                        selectMode: _selectMode,
                        selected: _selectedIds.contains(p.id),
                        onTap: () {
                          if (_selectMode) {
                            _toggleItem(p.id);
                          }
                        },
                        onLongPress: () {
                          if (!_selectMode) {
                            setState(() {
                              _selectMode = true;
                              _selectedIds.add(p.id);
                            });
                          }
                        },
                        onToggleVisibility: () async {
                          await context
                              .read<SurveyProvider>()
                              .setSurveyPointsVisibility(
                                  {p.id}, !p.isVisible);
                        },
                        onDelete: () async {
                          final ok = await _confirmDelete(
                              context, '删除「${p.name}」？');
                          if (ok == true && context.mounted) {
                            context
                                .read<SurveyProvider>()
                                .deleteSurveyPoint(p.id);
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),

      // ── Batch action bar ──────────────────────────────────────────────────
      bottomNavigationBar: _selectMode && _selectedIds.isNotEmpty
          ? _BatchBar(
              count: _selectedIds.length,
              onLoad: () async {
                await context
                    .read<SurveyProvider>()
                    .setSurveyPointsVisibility(Set.from(_selectedIds), true);
                setState(() {
                  _selectedIds.clear();
                  _selectMode = false;
                });
              },
              onUnload: () async {
                await context
                    .read<SurveyProvider>()
                    .setSurveyPointsVisibility(Set.from(_selectedIds), false);
                setState(() {
                  _selectedIds.clear();
                  _selectMode = false;
                });
              },
              onDelete: () async {
                final ok = await _confirmDelete(
                    context, '删除选中的 ${_selectedIds.length} 个位点？');
                if (ok == true && context.mounted) {
                  await context
                      .read<SurveyProvider>()
                      .deleteSurveyPoints(Set.from(_selectedIds));
                  setState(() {
                    _selectedIds.clear();
                    _selectMode = false;
                  });
                }
              },
            )
          : null,
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, String message) =>
      showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('确认删除'),
          content: Text(message),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除',
                    style: TextStyle(color: Colors.red))),
          ],
        ),
      );

  Future<void> _importFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt', 'kml'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final text = await File(path).readAsString();
      if (!context.mounted) return;
      final isKml = path.toLowerCase().endsWith('.kml');
      final count = isKml
          ? await context.read<SurveyProvider>().importSurveyPointsKml(text)
          : await context.read<SurveyProvider>().importSurveyPointsCsv(text);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功导入 $count 个位点')),
        );
      }
      return;
    }

    if (!context.mounted) return;
    final csvText = await _showPasteDialog(context);
    if (csvText == null || csvText.trim().isEmpty) return;
    if (!context.mounted) return;
    final count =
        await context.read<SurveyProvider>().importSurveyPointsCsv(csvText);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功导入 $count 个位点')),
      );
    }
  }

  Future<String?> _showPasteDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('粘贴CSV内容'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '格式：位点名称,经度,纬度,县市,风电场\n'
              '例：池塘A,110.1234,21.5678,雷州市,某风电场',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              maxLines: 8,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText:
                    '位点名称,经度,纬度,县市,风电场\n池塘A,110.1234,21.5678,雷州市,某风电场\n...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('导入')),
        ],
      ),
    );
  }

  Future<void> _addManual(BuildContext context) async {
    final point = await showDialog<SurveyPoint>(
      context: context,
      builder: (_) => const _AddPointDialog(),
    );
    if (point != null && context.mounted) {
      await context.read<SurveyProvider>().addSurveyPoint(point);
    }
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final List<String> options;
  final void Function(String) onSelected;
  final VoidCallback onCleared;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.options,
    required this.onSelected,
    required this.onCleared,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        if (active) {
          onCleared();
          return;
        }
        final v = await showDialog<String>(
          context: context,
          builder: (_) => SimpleDialog(
            title: Text('选择${label}'),
            children: options
                .map((o) => SimpleDialogOption(
                      child: Text(o),
                      onPressed: () => Navigator.pop(context, o),
                    ))
                .toList(),
          ),
        );
        if (v != null) onSelected(v);
      },
      child: Chip(
        label: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: active ? Colors.white : Colors.teal[800])),
        backgroundColor: active ? Colors.teal : Colors.teal[50],
        deleteIcon: active
            ? const Icon(Icons.close, size: 14, color: Colors.white)
            : null,
        onDeleted: active ? onCleared : null,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

// ── Batch action bar ──────────────────────────────────────────────────────────

class _BatchBar extends StatelessWidget {
  final int count;
  final VoidCallback onLoad;
  final VoidCallback onUnload;
  final VoidCallback onDelete;

  const _BatchBar({
    required this.count,
    required this.onLoad,
    required this.onUnload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
        ),
        child: Row(
          children: [
            Text('已选 $count 个',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
            const Spacer(),
            _BarBtn(
              icon: Icons.visibility,
              label: '加载',
              color: Colors.teal,
              onTap: onLoad,
            ),
            const SizedBox(width: 8),
            _BarBtn(
              icon: Icons.visibility_off,
              label: '卸载',
              color: Colors.orange,
              onTap: onUnload,
            ),
            const SizedBox(width: 8),
            _BarBtn(
              icon: Icons.delete_outline,
              label: '删除',
              color: Colors.red,
              onTap: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _BarBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _BarBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 13)),
      style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  final bool hasPoints;
  final VoidCallback onImport;
  final VoidCallback onAdd;
  const _EmptyHint(
      {required this.hasPoints,
      required this.onImport,
      required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              hasPoints ? '没有符合筛选条件的位点' : '还没有调查位点',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            if (!hasPoints) ...[
              const SizedBox(height: 6),
              const Text(
                'CSV格式：位点名称,经度,纬度,县市,风电场\n或导入Google Earth导出的KML文件',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('导入CSV / KML文件'),
                onPressed: onImport,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('手动添加位点'),
                onPressed: onAdd,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Point tile ────────────────────────────────────────────────────────────────

class _PointTile extends StatelessWidget {
  final SurveyPoint point;
  final bool selectMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleVisibility;
  final VoidCallback onDelete;

  const _PointTile({
    required this.point,
    required this.selectMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleVisibility,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (point.county.isNotEmpty) point.county,
      if (point.windFarm.isNotEmpty) point.windFarm,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: selected ? Colors.teal[50] : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (selectMode)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? Colors.teal : Colors.grey,
                    size: 22,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.place,
                      color: point.isVisible ? Colors.teal : Colors.grey[400],
                      size: 22),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(point.name,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: point.isVisible
                                ? null
                                : Colors.grey[500])),
                    const SizedBox(height: 2),
                    Text(
                      '${point.latitude.toStringAsFixed(5)}, '
                      '${point.longitude.toStringAsFixed(5)}'
                      '${meta.isNotEmpty ? '  ·  $meta' : ''}',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              if (!selectMode) ...[
                IconButton(
                  icon: Icon(
                    point.isVisible
                        ? Icons.visibility
                        : Icons.visibility_off,
                    color: point.isVisible ? Colors.teal : Colors.grey[400],
                    size: 20,
                  ),
                  tooltip: point.isVisible ? '卸载（隐藏地图）' : '加载（显示地图）',
                  onPressed: onToggleVisibility,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 20),
                  onPressed: onDelete,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Add point dialog ──────────────────────────────────────────────────────────

class _AddPointDialog extends StatefulWidget {
  const _AddPointDialog();

  @override
  State<_AddPointDialog> createState() => _AddPointDialogState();
}

class _AddPointDialogState extends State<_AddPointDialog> {
  final _name = TextEditingController();
  final _lat = TextEditingController();
  final _lon = TextEditingController();
  final _county = TextEditingController();
  final _windFarm = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _lat.dispose();
    _lon.dispose();
    _county.dispose();
    _windFarm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加位点'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(_name, '位点名称', ''),
            const SizedBox(height: 10),
            _field(_lon, '经度', '110.1234',
                type: const TextInputType.numberWithOptions(
                    decimal: true, signed: true)),
            const SizedBox(height: 10),
            _field(_lat, '纬度', '21.5678',
                type: const TextInputType.numberWithOptions(
                    decimal: true, signed: true)),
            const SizedBox(height: 10),
            _field(_county, '县市（选填）', ''),
            const SizedBox(height: 10),
            _field(_windFarm, '风电场（选填）', ''),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        ElevatedButton(
          onPressed: () {
            final lat = double.tryParse(_lat.text.trim());
            final lon = double.tryParse(_lon.text.trim());
            if (_name.text.trim().isEmpty || lat == null || lon == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请填写名称和有效的经纬度')));
              return;
            }
            Navigator.pop(
              context,
              SurveyPoint(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                name: _name.text.trim(),
                latitude: lat,
                longitude: lon,
                county: _county.text.trim(),
                windFarm: _windFarm.text.trim(),
              ),
            );
          },
          child: const Text('添加'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController ctrl, String label, String hint,
      {TextInputType? type}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
