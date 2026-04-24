import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../models/data_pack.dart';
import '../services/pack_manager.dart';
import '../services/storage.dart';
import 'online_import_screen.dart';

/// 数据包管理页面
class PackManageScreen extends StatefulWidget {
  final PackManager packManager;
  final StorageService storage;
  final VoidCallback? onPackChanged;

  const PackManageScreen({
    super.key,
    required this.packManager,
    required this.storage,
    this.onPackChanged,
  });

  @override
  State<PackManageScreen> createState() => _PackManageScreenState();
}

class _PackManageScreenState extends State<PackManageScreen> {
  List<DataPack> _packs = [];
  bool _loading = false;
  String? _activePackDir;

  Future<void> _editXenoSettings() async {
    final controller = TextEditingController(
      text: widget.storage.getXenoCantoApiKey(),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xeno-Canto 设置'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'API Key',
            hintText: '手动填写你自己的 Xeno-Canto API key',
          ),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (saved == true) {
      await widget.storage.setXenoCantoApiKey(controller.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Xeno-Canto API key 已保存')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPacks();
  }

  Future<void> _loadPacks() async {
    final packs = await widget.packManager.getInstalledPacks();
    final activeDir = await widget.packManager.getActivePackDir();
    if (mounted) {
      setState(() {
        _packs = packs;
        _activePackDir = activeDir;
      });
    }
  }

  Future<void> _importPack() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null) return;

      setState(() => _loading = true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在导入数据包...')),
      );

      final pack = await widget.packManager.importPack(path);
      await _loadPacks();
      widget.onPackChanged?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ 导入成功: ${pack.name}\n'
              '${pack.speciesCount} 种鸟, ${pack.audioCount} 个音频, ${pack.imageCount} 张图片',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 导入失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _installBuiltinTrialPack() async {
    try {
      setState(() => _loading = true);
      final pack = await widget.packManager.installBuiltinTrialPack();
      await _loadPacks();
      widget.onPackChanged?.call();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ 已安装内置试用包: ${pack.name}\n'
            '${pack.speciesCount} 种鸟, ${pack.audioCount} 个音频, ${pack.imageCount} 张图片',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 安装内置试用包失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deletePack(DataPack pack) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除「${pack.name}」吗？\n这将同时删除所有音频和图片文件。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await widget.packManager.deletePack(pack.packDir);
      await _loadPacks();
      widget.onPackChanged?.call();
    }
  }

  Future<void> _activatePack(DataPack pack) async {
    await widget.packManager.setActivePack(pack.packDir);
    await _loadPacks();
    widget.onPackChanged?.call();
  }

  Future<void> _exportPack(DataPack pack) async {
    try {
      final outputDir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择备份保存目录',
      );
      if (outputDir == null || outputDir.isEmpty) return;

      setState(() => _loading = true);
      final zipPath =
          await widget.packManager.exportPackToDirectory(pack.packDir, outputDir);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ 备份已导出到:\n$zipPath'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 导出备份失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 导入按钮
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _importPack,
              icon: _loading
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_upload),
              label: Text(_loading ? '导入中...' : '📂 导入数据包 (.zip)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2d5016),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _installBuiltinTrialPack,
              icon: const Icon(Icons.download_for_offline_outlined),
              label: const Text('安装内置试用包（10种）'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _editXenoSettings,
              icon: const Icon(Icons.key),
              label: Text(
                widget.storage.getXenoCantoApiKey().isEmpty
                    ? '填写 Xeno-Canto API Key'
                    : '修改 Xeno-Canto API Key',
              ),
            ),
          ),
        ),

        // 在线导入按钮
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OnlineImportScreen(
                      packManager: widget.packManager,
                      storage: widget.storage,
                    ),
                  ),
                ).then((_) => _loadPacks());
              },
              icon: const Icon(Icons.cloud_download),
              label: const Text('🌐 在线导入（Xeno-Canto）'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),

        // 已安装列表
        Expanded(
          child: _packs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text('暂无数据包',
                          style: TextStyle(color: Colors.grey[500])),
                      const SizedBox(height: 4),
                      Text('点击上方按钮导入或在线下载',
                          style: TextStyle(fontSize: 13, color: Colors.grey[400])),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _packs.length,
                  itemBuilder: (context, i) {
                    final pack = _packs[i];
                    final isActive = pack.packDir == _activePackDir;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.folder_zip, color: Color(0xFF2d5016)),
                        title: Text(pack.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${pack.speciesCount} 种鸟 · ${pack.audioCount} 音频 · ${pack.imageCount} 图片\n${pack.region} · v${pack.version} · ${pack.created}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green[50],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('使用中',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green[700])),
                              ),
                            IconButton(
                              icon: const Icon(Icons.archive_outlined, size: 20),
                              tooltip: '导出备份',
                              onPressed: _loading ? null : () => _exportPack(pack),
                            ),
                            IconButton(
                              icon: const Icon(Icons.check_circle_outline, size: 20),
                              tooltip: '设为当前',
                              onPressed: () => _activatePack(pack),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  size: 20, color: Colors.red[400]),
                              tooltip: '删除',
                              onPressed: () => _deletePack(pack),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
