import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../models/data_pack.dart';
import '../services/download_task_service.dart';
import '../services/ebird_service.dart';
import '../services/order_taxonomy.dart';
import '../services/pack_downloader.dart';
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
  String _mediaUpdateStatus = '';



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
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null) return;

      setState(() => _loading = true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('正在导入数据包...')));

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ 导入失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _installBuiltinPack(BuiltinPackInfo info) async {
    try {
      setState(() => _loading = true);
      // 大包解压时间较长，先给用户反馈
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('正在安装「${info.label}」，大包可能需要十几秒，请稍候…'),
            duration: const Duration(seconds: 30),
          ),
        );
      }
      final pack = await widget.packManager.installBuiltinPack(info);
      await _loadPacks();
      widget.onPackChanged?.call();

      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ 已安装「${pack.name}」\n'
            '${pack.speciesCount} 种鸟 · ${pack.audioCount} 音频 · ${pack.imageCount} 张图',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 安装失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showServerDownloadSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _ServerDownloadSheet(
        packManager: widget.packManager,
        onDownloadChinaCatalog: _downloadFullChinaCatalog,
        onInstalled: () {
          _loadPacks();
          widget.onPackChanged?.call();
        },
      ),
    );
  }

  Future<void> _updateInstalledMedia() async {
    if (_activePackDir == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择一个已安装数据包')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('更新已下载媒体'),
        content: const Text(
          '会逐个检查当前数据包里的物种，只下载服务器新增的图片/音频，不会清空学习进度。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始更新'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      setState(() {
        _loading = true;
        _mediaUpdateStatus = '正在连接服务器…';
      });
      final result = await widget.packManager.updateActivePackFromServer(
        onProgress: (current, total, speciesName) {
          if (!mounted) return;
          setState(() {
            _mediaUpdateStatus = '检查 $current/$total：$speciesName';
          });
        },
      );
      await _loadPacks();
      widget.onPackChanged?.call();
      if (!mounted) return;
      setState(() {
        _mediaUpdateStatus =
            '完成：新增图片 ${result.imageAdded} 张，音频 ${result.audioAdded} 个，更新 ${result.updatedSpecies} 种';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ 更新完成：新增图片 ${result.imageAdded} 张，音频 ${result.audioAdded} 个'
            '${result.failed > 0 ? '，失败 ${result.failed} 种' : ''}',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _mediaUpdateStatus = '更新失败：$e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 更新失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showCountrySpeciesDownloadSheet() async {
    final controller = TextEditingController(text: 'CN');
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '按国家名录逐物种下载',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '先用 eBird 国家/地区代码取得物种名录，再逐个从自建服务器下载；服务器没有的物种会继续尝试 Xeno-Canto 音频和 iNaturalist/Wikimedia 图片。',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'eBird 国家/地区代码',
                  hintText: '例如 CN、AU、US、JP、CN-53',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CountryCodeChip(
                    label: '中国',
                    code: 'CN',
                    onSelected: (code) => controller.text = code,
                  ),
                  _CountryCodeChip(
                    label: '澳大利亚',
                    code: 'AU',
                    onSelected: (code) => controller.text = code,
                  ),
                  _CountryCodeChip(
                    label: '美国',
                    code: 'US',
                    onSelected: (code) => controller.text = code,
                  ),
                  _CountryCodeChip(
                    label: '日本',
                    code: 'JP',
                    onSelected: (code) => controller.text = code,
                  ),
                  _CountryCodeChip(
                    label: '泰国',
                    code: 'TH',
                    onSelected: (code) => controller.text = code,
                  ),
                  _CountryCodeChip(
                    label: '云南',
                    code: 'CN-53',
                    onSelected: (code) => controller.text = code,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                  icon: const Icon(Icons.cloud_sync_outlined),
                  label: const Text('开始逐物种下载'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    final countryCode = result?.trim();
    if (countryCode == null || countryCode.isEmpty) return;
    await _downloadCountrySpecies(countryCode);
  }

  Future<void> _downloadCountrySpecies(String countryCode) async {
    final apiKey = widget.storage.getEBirdApiKey();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先填写 eBird API key')));
      return;
    }

    try {
      setState(() => _loading = true);
      final normalized = EBirdService.normalizeLocationCode(countryCode);
      final matches =
          await EBirdService(apiKey: apiKey).fetchSpeciesMatches(normalized);
      final speciesList = await _speciesEntriesFromEbirdMatches(
        matches,
        normalized,
      );
      if (!mounted) return;
      if (speciesList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('eBird 名录 $normalized 没有匹配到可下载鸟种')),
        );
        return;
      }

      final started = DownloadTaskService.instance.start(
        speciesList: speciesList,
        packName: 'eBird-$normalized 鸟种库',
        region: normalized,
        packManager: widget.packManager,
        storage: widget.storage,
        allowApiFallback: true,
        onPackActivated: () {
          _loadPacks();
          widget.onPackChanged?.call();
        },
      );
      if (!started) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已有下载任务正在后台进行')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已开始按 $normalized 名录逐物种下载 ${speciesList.length} 种'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('启动国家名录下载失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  Future<void> _downloadChinaSpecies(List<SpeciesEntry> speciesList) async {
    final started = DownloadTaskService.instance.start(
      speciesList: speciesList,
      packName: '我的中国鸟种下载',
      region: '中国名录',
      packManager: widget.packManager,
      storage: widget.storage,
      allowApiFallback: false,
      onPackActivated: () {
        _loadPacks();
        widget.onPackChanged?.call();
      },
    );
    if (!started) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已有下载任务正在后台进行')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已开始按中国名录下载 ${speciesList.length} 种')),
    );
  }

  Future<void> _downloadFullChinaCatalog() async {
    final speciesList = await _speciesEntriesFromChinaCatalog();
    await _downloadChinaSpecies(speciesList);
  }

  Future<List<SpeciesEntry>> _speciesEntriesFromChinaCatalog() async {
    final raw = await rootBundle.loadString('assets/data/china_birds_zheng.json');
    final data = jsonDecode(raw) as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final sci = (item['sci'] as String? ?? '').trim();
          final en = (item['en'] as String? ?? '').trim();
          final cn = (item['zh'] as String? ?? '').trim();
          return SpeciesEntry(
            cn: cn.isNotEmpty ? cn : en,
            en: en.isNotEmpty ? en : sci,
            sci: sci,
            cons: _normalizeProtection(
              (item['protection'] as String? ?? '').trim(),
            ),
          );
        })
        .where((entry) => entry.sci.isNotEmpty)
        .toList()
      ..sort((a, b) => a.cn.compareTo(b.cn));
  }

  Future<List<SpeciesEntry>> _speciesEntriesFromEbirdMatches(
    Set<EbirdSpeciesMatch> matches,
    String region,
  ) async {
    final raw = await rootBundle.loadString('assets/data/world_birds.json');
    final data = jsonDecode(raw) as List<dynamic>;
    final byCode = <String, Map<String, dynamic>>{};
    final bySci = <String, Map<String, dynamic>>{};

    for (final value in data) {
      final item = value as Map<String, dynamic>;
      final code = (item['code'] as String? ?? '').trim().toLowerCase();
      final sci = (item['sci'] as String? ?? '').trim().toLowerCase();
      if (code.isNotEmpty) byCode[code] = item;
      if (sci.isNotEmpty) bySci[sci] = item;
    }

    final entries = <SpeciesEntry>[];
    final seen = <String>{};
    for (final match in matches) {
      final item = byCode[match.code.trim().toLowerCase()] ??
          bySci[match.scientificName.trim().toLowerCase()];
      final sci = ((item?['sci'] as String?) ?? match.scientificName).trim();
      if (sci.isEmpty || !seen.add(sci.toLowerCase())) continue;
      final en = ((item?['en'] as String?) ?? match.commonName).trim();
      final cn = ((item?['zh'] as String?) ?? '').trim();
      entries.add(
        SpeciesEntry(
          cn: cn.isNotEmpty ? cn : en,
          en: en,
          sci: sci,
          cons: _normalizeProtection(
            ((item?['protection'] as String?) ?? '').trim(),
          ),
          habitat: 'ebird:$region',
        ),
      );
    }
    return entries;
  }

  String _normalizeProtection(String value) {
    if (value.contains('一级')) return '1';
    if (value.contains('二级')) return '2';
    return value;
  }

  Future<void> _deletePack(DataPack pack) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除「${pack.name}」吗？\n这将同时删除所有音频和图片文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
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
      final outputDir = await FilePicker.getDirectoryPath(
        dialogTitle: '选择备份保存目录',
      );
      if (outputDir == null || outputDir.isEmpty) return;

      setState(() => _loading = true);
      final zipPath = await widget.packManager.exportPackToDirectory(
        pack.packDir,
        outputDir,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ 备份已导出到:\n$zipPath'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ 导出备份失败: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showPackOrderOverview(DataPack pack) async {
    final file = File('${pack.packDir}/species.json');
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这个数据包缺少 species.json')),
      );
      return;
    }

    final rows = (jsonDecode(await file.readAsString()) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .toList();
    final counts = <String, int>{};
    for (final row in rows) {
      final order = (row['order'] as String? ?? '').trim();
      if (order.isEmpty) continue;
      counts[order] = (counts[order] ?? 0) + 1;
    }
    final orders = BirdOrderTaxonomy.sortOrders(counts.keys);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (ctx, controller) => SafeArea(
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            children: [
              Text(
                '${pack.displayName} · 类群概览',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              if (orders.isEmpty)
                const Text('这个数据包暂时没有目分类信息。')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: orders
                      .map(
                        (order) => Chip(
                          label: Text(
                            '${BirdOrderTaxonomy.shortLabel(order)} '
                            '${BirdOrderTaxonomy.label(order)} ${counts[order]}',
                          ),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 导入按钮
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '数据包管理：可安装内置中国常见鸟 100，也可按内置中国名录逐物种下载；eBird 只作为高级地区筛选。',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _importPack,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
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
        // 内置数据包列表
        ...PackManager.builtinPacks.map((info) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _loading ? null : () => _installBuiltinPack(info),
                  child: Row(
                    children: [
                      const Icon(Icons.download_for_offline_outlined, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(info.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            Text(info.description,
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _showServerDownloadSheet,
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('从服务器下载完整数据包'),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _showCountrySpeciesDownloadSheet,
              icon: const Icon(Icons.public),
              label: const Text('按 eBird 国家名录逐物种下载'),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _updateInstalledMedia,
              icon: const Icon(Icons.sync),
              label: Text(
                _mediaUpdateStatus.isEmpty
                    ? '更新已下载媒体（只补新增图片/音频）'
                    : _mediaUpdateStatus,
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

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Row(
            children: [
              const Icon(Icons.inventory_2_outlined,
                  size: 18, color: Color(0xFF2d5016)),
              const SizedBox(width: 8),
              const Text(
                '已有数据包',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${_packs.length} 个',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        Expanded(
          child: _packs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 64,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '暂无数据包',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '点击上方按钮导入或在线下载',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[400],
                        ),
                      ),
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
                        leading: const Icon(
                          Icons.folder_zip,
                          color: Color(0xFF2d5016),
                        ),
                        title: Text(
                          pack.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${pack.speciesCount} 种鸟 · ${pack.audioCount} 音频 · ${pack.imageCount} 图片\n${pack.region} · v${pack.version} · ${pack.created}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FutureBuilder<bool>(
                              future: widget.packManager.isPackEnabled(pack.packDir),
                              builder: (context, snapshot) {
                                final enabled = snapshot.data ?? isActive;
                                return Switch(
                                  value: enabled,
                                  onChanged: (value) async {
                                    await widget.packManager
                                        .setPackEnabled(pack.packDir, value);
                                    if (value) {
                                      await widget.packManager
                                          .setActivePack(pack.packDir);
                                    }
                                    await _loadPacks();
                                    widget.onPackChanged?.call();
                                  },
                                );
                              },
                            ),
                            if (isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green[50],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '使用中',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.green[700],
                                  ),
                                ),
                              ),
                            IconButton(
                              icon: const Icon(
                                Icons.account_tree_outlined,
                                size: 20,
                              ),
                              tooltip: '类群概览',
                              onPressed: () => _showPackOrderOverview(pack),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.archive_outlined,
                                size: 20,
                              ),
                              tooltip: '导出备份',
                              onPressed:
                                  _loading ? null : () => _exportPack(pack),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.check_circle_outline,
                                size: 20,
                              ),
                              tooltip: '设为当前主包',
                              onPressed: () => _activatePack(pack),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: Colors.red[400],
                              ),
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

class _CountryCodeChip extends StatelessWidget {
  final String label;
  final String code;
  final ValueChanged<String> onSelected;

  const _CountryCodeChip({
    required this.label,
    required this.code,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text('$label $code'),
      onPressed: () => onSelected(code),
    );
  }
}

/// 服务器数据包下载底部弹窗
class _ServerDownloadSheet extends StatefulWidget {
  final PackManager packManager;
  final VoidCallback onInstalled;
  final Future<void> Function() onDownloadChinaCatalog;

  const _ServerDownloadSheet({
    required this.packManager,
    required this.onInstalled,
    required this.onDownloadChinaCatalog,
  });

  @override
  State<_ServerDownloadSheet> createState() => _ServerDownloadSheetState();
}

class _ServerDownloadSheetState extends State<_ServerDownloadSheet> {
  void _download(RemotePackInfo info) {
    try {
      final started = DownloadTaskService.instance.startRemotePack(
        info: info,
        packManager: widget.packManager,
        onPackActivated: widget.onInstalled,
      );
      if (!started) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已有下载任务正在后台进行')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已开始后台下载「${info.label}」'),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('启动下载失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _downloadChinaCatalog() async {
    try {
      if (DownloadTaskService.instance.isRunning) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已有下载任务正在后台进行')),
        );
        return;
      }
      await widget.onDownloadChinaCatalog();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('启动中国名录下载失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '从服务器下载',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '整包适合网络稳定时；逐物种下载更适合长任务，遇到网络异常也方便继续。',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF2d5016)),
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFF2d5016).withValues(alpha: 0.04),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.list_alt_outlined,
                        color: Color(0xFF2d5016)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '按名录逐物种下载（推荐）',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '下载中国完整名录全部物种，不需要 eBird API；已完成物种会保留，适合防止网络异常。',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: DownloadTaskService.instance.isRunning
                          ? null
                          : _downloadChinaCatalog,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2d5016),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('下载全部'),
                    ),
                  ],
                ),
              ),
            ),
            ...PackManager.remotePacks.map((info) {
              final task = DownloadTaskService.instance.snapshot;
              final isDownloading = task.isRunning &&
                  task.kind == DownloadTaskKind.remotePack &&
                  task.packName == info.label;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isDownloading
                          ? const Color(0xFF1565C0)
                          : Colors.grey[300]!,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  info.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${info.description} · ${info.sizeLabel}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (isDownloading)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${(task.progress * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1565C0),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '取消下载',
                                  onPressed: DownloadTaskService.instance.cancel,
                                  icon: const Icon(Icons.close, size: 18),
                                ),
                              ],
                            )
                          else
                            FilledButton(
                              onPressed: DownloadTaskService.instance.isRunning
                                  ? null
                                  : () => _download(info),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF1565C0),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('下载'),
                            ),
                        ],
                      ),
                      if (isDownloading) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${task.byteProgressLabel}'
                          '${task.speedLabel.isEmpty ? '' : ' · ${task.speedLabel} · 剩余 ${task.etaLabel}'}',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[700]),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: task.progress,
                            minHeight: 6,
                            backgroundColor: Colors.grey[200],
                            color: const Color(0xFF1565C0),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
