import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/survey_point.dart';
import '../providers/survey_provider.dart';

class SurveyPointsScreen extends StatelessWidget {
  const SurveyPointsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SurveyProvider>();
    final points = prov.surveyPoints;

    return Scaffold(
      appBar: AppBar(
        title: Text('调查位点（${points.length}个）'),
        actions: [
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
        ],
      ),
      body: points.isEmpty
          ? _EmptyHint(onImport: () => _importFile(context),
                       onAdd: () => _addManual(context))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: points.length,
              itemBuilder: (_, i) => _PointTile(
                point: points[i],
                onDelete: () =>
                    context.read<SurveyProvider>().deleteSurveyPoint(points[i].id),
              ),
            ),
    );
  }

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

    // Fallback: paste CSV text
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
              '格式：名称,纬度,经度（可含备注列）\n'
              '例：池塘A,31.2345,121.5678',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              maxLines: 8,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '名称,纬度,经度\n池塘A,31.2345,121.5678\n...',
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

// ── Empty state ──────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  final VoidCallback onImport;
  final VoidCallback onAdd;
  const _EmptyHint({required this.onImport, required this.onAdd});

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
            const Text('还没有调查位点',
                style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 6),
            const Text(
              'CSV格式：名称,纬度,经度\n或导入Google Earth导出的KML文件',
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
        ),
      ),
    );
  }
}

// ── Point tile ────────────────────────────────────────────────────────────────

class _PointTile extends StatelessWidget {
  final SurveyPoint point;
  final VoidCallback onDelete;
  const _PointTile({required this.point, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.teal[50],
          child: const Icon(Icons.place, color: Colors.teal),
        ),
        title: Text(point.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${point.latitude.toStringAsFixed(5)}, '
          '${point.longitude.toStringAsFixed(5)}'
          '${point.notes.isNotEmpty ? '\n${point.notes}' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        isThreeLine: point.notes.isNotEmpty,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('删除位点'),
                content: Text('删除「${point.name}」？'),
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
            if (ok == true) onDelete();
          },
        ),
      ),
    );
  }
}

// ── Add point dialog ─────────────────────────────────────────────────────────

class _AddPointDialog extends StatefulWidget {
  const _AddPointDialog();

  @override
  State<_AddPointDialog> createState() => _AddPointDialogState();
}

class _AddPointDialogState extends State<_AddPointDialog> {
  final _name = TextEditingController();
  final _lat = TextEditingController();
  final _lon = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _lat.dispose();
    _lon.dispose();
    _notes.dispose();
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
            _field(_name, '位点名称', '池塘A'),
            const SizedBox(height: 10),
            _field(_lat, '纬度', '31.2345',
                type: const TextInputType.numberWithOptions(decimal: true, signed: true)),
            const SizedBox(height: 10),
            _field(_lon, '经度', '121.5678',
                type: const TextInputType.numberWithOptions(decimal: true, signed: true)),
            const SizedBox(height: 10),
            _field(_notes, '备注（选填）', ''),
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
                notes: _notes.text.trim(),
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
