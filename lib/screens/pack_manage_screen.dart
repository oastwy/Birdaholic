import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';

import '../models/data_pack.dart';
import '../services/download_task_service.dart';
import '../services/ebird_service.dart';
import '../services/order_taxonomy.dart';
import '../services/pack_downloader.dart';
import '../services/pack_manager.dart';
import '../services/storage.dart';
import 'online_import_screen.dart';

enum _PackManageSection {
  root,
  localImport,
  onlineImport,
  serverDownload,
  installed
}

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
  String _mediaUpdateSci = '';
  _PackManageSection _section = _PackManageSection.root;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await widget.packManager.ensureBuiltinPackInstalled();
    } catch (_) {
      // 数据包管理页仍然要能打开，后面会显示恢复内置包入口。
    }
    await _loadPacks();
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
        _mediaUpdateSci = '';
      });
      final result = await widget.packManager.updateActivePackFromServer(
        onProgress: (current, total, speciesName) {
          if (!mounted) return;
          setState(() {
            _mediaUpdateStatus = '检查 $current/$total：';
            _mediaUpdateSci = speciesName;
          });
        },
      );
      await _loadPacks();
      widget.onPackChanged?.call();
      if (!mounted) return;
      setState(() {
        _mediaUpdateStatus =
            '完成：新增图片 ${result.imageAdded} 张，音频 ${result.audioAdded} 个，更新 ${result.updatedSpecies} 种';
        _mediaUpdateSci = '';
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
      setState(() {
        _mediaUpdateStatus = '更新失败：$e';
        _mediaUpdateSci = '';
      });
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
                '中国完整名录不需要 eBird API；其它国家/地区可用 eBird 代码取得名录，再逐个从服务器下载。',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, '__china_full__'),
                  icon: const Icon(Icons.list_alt_outlined),
                  label: const Text('下载中国完整名录（无需 eBird）'),
                ),
              ),
              const SizedBox(height: 12),
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
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, '__current_location__'),
                  icon: const Icon(Icons.my_location),
                  label: const Text('使用当前位置（经纬度）'),
                ),
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
    if (countryCode == '__china_full__') {
      await _downloadFullChinaCatalog();
      return;
    }
    await _downloadCountrySpecies(countryCode);
  }

  Future<void> _showLocationSpeciesDownloadSheet() async {
    final controller = TextEditingController(text: 'CN-53');
    final distanceController = TextEditingController(text: '25');
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
                '按地点逐物种下载',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '输入 eBird 地区/热点代码，或输入经纬度。系统会先获取该地点鸟种，再逐个从服务器下载媒体。',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: '地点、热点或经纬度',
                  hintText: '例如 云南、那邦、CN-53、L3124991、24.7,97.6',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: distanceController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '经纬度半径 km',
                  hintText: '1-50，默认 25',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: EBirdService.presets.take(9).map((preset) {
                  return ActionChip(
                    label: Text(preset.label),
                    onPressed: () => controller.text = preset.code,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final value = controller.text.trim();
                    final dist = distanceController.text.trim();
                    Navigator.pop(
                      ctx,
                      dist.isEmpty ? value : '$value|$dist',
                    );
                  },
                  icon: const Icon(Icons.place_outlined),
                  label: const Text('开始按地点下载'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final query = result?.trim();
    final distanceKm = int.tryParse(distanceController.text.trim()) ?? 25;
    controller.dispose();
    distanceController.dispose();
    if (query == null || query.isEmpty) return;
    if (query == '__current_location__') {
      await _downloadFromCurrentLocation(distanceKm: distanceKm);
      return;
    }
    final parts = query.split('|');
    await _downloadLocationSpecies(
      parts.first,
      distanceKm: parts.length > 1 ? int.tryParse(parts[1]) ?? 25 : distanceKm,
    );
  }

  Future<void> _downloadFromCurrentLocation({int distanceKm = 25}) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('手机定位服务未开启');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw Exception('未授予定位权限');
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('定位权限已被永久拒绝，请到系统设置中开启');
      }
      final position = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 20),
            ),
          );
      await _downloadLocationSpecies(
        '${position.latitude.toStringAsFixed(6)},${position.longitude.toStringAsFixed(6)}',
        distanceKm: distanceKm,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('当前位置下载失败: $e'), backgroundColor: Colors.red),
      );
    }
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

  Future<void> _downloadLocationSpecies(
    String locationQuery, {
    int distanceKm = 25,
  }) async {
    final apiKey = widget.storage.getEBirdApiKey();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在设置页填写 eBird API key')));
      return;
    }

    try {
      setState(() => _loading = true);
      final normalized = locationQuery.trim();
      final service = EBirdService(apiKey: apiKey);
      final coords = _parseCoordinates(normalized);
      final matches = coords == null
          ? await service.fetchSpeciesMatches(normalized)
          : await service.fetchNearbySpeciesMatches(
              latitude: coords.$1,
              longitude: coords.$2,
              distanceKm: distanceKm.clamp(1, 50),
            );
      final label = coords == null
          ? EBirdService.normalizeLocationCode(normalized)
          : '${coords.$1.toStringAsFixed(3)},${coords.$2.toStringAsFixed(3)}';
      final speciesList = await _speciesEntriesFromEbirdMatches(matches, label);
      if (!mounted) return;
      if (speciesList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('地点 $label 没有匹配到可下载鸟种')),
        );
        return;
      }

      final started = DownloadTaskService.instance.start(
        speciesList: speciesList,
        packName: '地点-$label 鸟种库',
        region: label,
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
        SnackBar(content: Text('已开始按 $label 逐物种下载 ${speciesList.length} 种')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('启动地点下载失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  (double, double)? _parseCoordinates(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'[,，\s]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 2) return null;
    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return (lat, lng);
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
    final raw =
        await rootBundle.loadString('assets/data/china_birds_zheng.json');
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

  Future<void> _showDifficultyStats(DataPack pack) async {
    final file = File('${pack.packDir}/species.json');
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('这个数据包缺少 species.json')));
      return;
    }
    final rows = (jsonDecode(await file.readAsString()) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .toList();

    // Count per species difficulty
    final speciesByDiff = <int, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final d = ((row['difficulty'] as int?) ?? 1).clamp(1, 5);
      speciesByDiff.putIfAbsent(d, () => []).add(row);
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        int? expanded;
        return StatefulBuilder(
          builder: (ctx, setS) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.92,
            builder: (ctx, ctrl) => ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
              children: [
                Text('${pack.displayName} · 难度统计',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('共 ${rows.length} 种',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                const SizedBox(height: 12),
                ...List.generate(5, (i) {
                  final d = i + 1;
                  final items = speciesByDiff[d] ?? [];
                  final stars = List.filled(d, '⭐').join();
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      children: [
                        ListTile(
                          leading:
                              Text(stars, style: const TextStyle(fontSize: 16)),
                          title: Text('难度 $d · ${items.length} 种'),
                          trailing: items.isEmpty
                              ? null
                              : Icon(expanded == d
                                  ? Icons.expand_less
                                  : Icons.expand_more),
                          onTap: items.isEmpty
                              ? null
                              : () => setS(
                                  () => expanded = expanded == d ? null : d),
                        ),
                        if (expanded == d && items.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: items
                                  .map((r) => Chip(
                                        label: Text(
                                          (r['cn'] as String?)?.isNotEmpty ==
                                                  true
                                              ? r['cn'] as String
                                              : (r['sci'] as String? ?? '?'),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ))
                                  .toList(),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
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
    return switch (_section) {
      _PackManageSection.root => _buildRootSection(),
      _PackManageSection.localImport => _buildLocalImportSection(),
      _PackManageSection.onlineImport => _buildOnlineImportSection(),
      _PackManageSection.serverDownload => _buildServerDownloadSection(),
      _PackManageSection.installed => _buildInstalledSection(),
    };
  }

  Widget _buildRootSection() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(
          '数据包管理',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          '本地包、在线下载和已安装数据包分开管理，学习页只保留学习本身。',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        _PackModuleCard(
          icon: Icons.file_upload_outlined,
          title: '本地导入',
          subtitle: '导入本机 ZIP 数据包或分包',
          onTap: () =>
              setState(() => _section = _PackManageSection.localImport),
        ),
        _PackModuleCard(
          icon: Icons.cloud_download_outlined,
          title: '在线导入',
          subtitle: '按中国名录、地点或自定义批量下载',
          onTap: () =>
              setState(() => _section = _PackManageSection.onlineImport),
        ),
        _PackModuleCard(
          icon: Icons.inventory_2_outlined,
          title: '已有数据包',
          subtitle: '${_packs.length} 个数据包 · 启用、更新、备份和删除',
          onTap: () => setState(() => _section = _PackManageSection.installed),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: () => setState(() => _section = _PackManageSection.root),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalImportSection() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _buildSectionHeader('本地导入', '从本机选择 Birdaholic ZIP 数据包。'),
        FilledButton.icon(
          onPressed: _loading ? null : _importPack,
          icon: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.file_upload_outlined),
          label: Text(_loading ? '导入中...' : '选择本地 ZIP'),
        ),
        const SizedBox(height: 12),
        Text(
          '如果是分包，请一次选择或导入完整分包后再合并。弱网下载建议用“在线导入 > 服务器下载 > 逐物种下载中国名录”。',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildOnlineImportSection() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _buildSectionHeader('在线导入', '推荐逐物种下载，网络中断后可继续补缺失物种。'),
        _PackModuleCard(
          icon: Icons.cloud_queue,
          title: '服务器下载',
          subtitle: '逐物种下载中国名录（推荐）',
          onTap: () =>
              setState(() => _section = _PackManageSection.serverDownload),
        ),
        _PackModuleCard(
          icon: Icons.place_outlined,
          title: '按地点逐物种下载（eBird API）',
          subtitle: '用地区、热点或经纬度筛选附近鸟种',
          onTap: _loading ? null : _showLocationSpeciesDownloadSheet,
        ),
        _PackModuleCard(
          icon: Icons.graphic_eq,
          title: '自定义批量下载（Xeno API）',
          subtitle: '旧版在线导入：按清单补充鸟鸣和图片',
          onTap: _loading
              ? null
              : () {
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
        ),
      ],
    );
  }

  Widget _buildServerDownloadSection() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _buildSectionHeader('服务器下载', '整包下载已移除，避免弱网下反复失败。'),
        _PackModuleCard(
          icon: Icons.list_alt_outlined,
          title: '逐物种下载中国名录（推荐）',
          subtitle: '按物种从服务器补媒体，失败后下次可继续',
          onTap: _loading ? null : _downloadFullChinaCatalog,
        ),
        _PackModuleCard(
          icon: Icons.public,
          title: '按国家/地区名录逐物种下载',
          subtitle: '中国名录无需 eBird；其它地区需要 eBird API',
          onTap: _loading ? null : _showCountrySpeciesDownloadSheet,
        ),
      ],
    );
  }

  Widget _buildInstalledSection() {
    final missingBuiltin = PackManager.builtinPacks.where((info) {
      return !_packs.any((pack) => _isBuiltinPack(pack, info));
    }).toList();

    return Column(
      children: [
        _buildSectionHeader('已有数据包', '启用、设为主包、更新媒体、备份和查看类群。'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _updateInstalledMedia,
              icon: const Icon(Icons.sync),
              label: _mediaUpdateStatus.isEmpty
                  ? const Text('更新已下载媒体（只补新增图片/音频）')
                  : Text.rich(
                      TextSpan(children: [
                        TextSpan(text: _mediaUpdateStatus),
                        if (_mediaUpdateSci.isNotEmpty)
                          TextSpan(
                            text: _mediaUpdateSci,
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                      ]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
        ),
        if (missingBuiltin.isNotEmpty)
          ...missingBuiltin.map((info) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : () => _installBuiltinPack(info),
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: Text('恢复内置包：${info.label}'),
                ),
              )),
        Expanded(
          child: _packs.isEmpty
              ? Center(
                  child: Text(
                    '暂无数据包',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: _packs.length,
                  itemBuilder: (context, i) => _buildPackCard(_packs[i]),
                ),
        ),
      ],
    );
  }

  bool _isBuiltinPack(DataPack pack, [BuiltinPackInfo? info]) {
    final candidates =
        info == null ? PackManager.builtinPacks : <BuiltinPackInfo>[info];
    return candidates
        .any((builtin) => pack.packDir.endsWith('/${builtin.dirName}'));
  }

  Widget _buildPackCard(DataPack pack) {
    final isActive = pack.packDir == _activePackDir;
    final isBuiltin = _isBuiltinPack(pack);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.folder_zip, color: Color(0xFF2d5016)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pack.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _PackStatChip(label: '${pack.speciesCount} 种'),
                          _PackStatChip(label: '${pack.audioCount} 音频'),
                          _PackStatChip(label: '${pack.imageCount} 图片'),
                          if (pack.region.trim().isNotEmpty)
                            _PackStatChip(label: pack.region),
                          _PackStatChip(label: 'v${pack.version}'),
                          if (isBuiltin) const _PackStatChip(label: '内置'),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isActive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '主包',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FutureBuilder<bool>(
                  future: widget.packManager.isPackEnabled(pack.packDir),
                  builder: (context, snapshot) {
                    final enabled = snapshot.data ?? isActive;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
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
                        ),
                        const Text('启用'),
                      ],
                    );
                  },
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.account_tree_outlined, size: 20),
                  tooltip: '类群概览',
                  onPressed: () => _showPackOrderOverview(pack),
                ),
                IconButton(
                  icon: const Icon(Icons.star_half_outlined, size: 20),
                  tooltip: '难度统计',
                  onPressed: () => _showDifficultyStats(pack),
                ),
                IconButton(
                  icon: const Icon(Icons.archive_outlined, size: 20),
                  tooltip: '导出备份',
                  onPressed: _loading ? null : () => _exportPack(pack),
                ),
                IconButton(
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  tooltip: '设为当前主包',
                  onPressed: () => _activatePack(pack),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 20,
                      color: isBuiltin ? Colors.grey : Colors.red[400]),
                  tooltip: isBuiltin ? '内置包默认启用，不能删除' : '删除',
                  onPressed: isBuiltin ? null : () => _deletePack(pack),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PackModuleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _PackModuleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF2d5016), size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackStatChip extends StatelessWidget {
  final String label;

  const _PackStatChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
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

  const _ServerDownloadSheet({
    required this.packManager,
    required this.onInstalled,
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
              '整包适合网络稳定时；如果网络容易中断，建议返回上一层使用逐物种下载。',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
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
                                  onPressed:
                                      DownloadTaskService.instance.cancel,
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
