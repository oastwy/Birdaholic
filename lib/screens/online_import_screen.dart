import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/avilist_species.dart';
import '../services/avilist_service.dart';
import '../services/download_task_service.dart';
import '../services/pack_downloader.dart';
import '../services/pack_manager.dart';
import '../services/storage.dart';

/// 物种清单导入 + 在线下载页面
class OnlineImportScreen extends StatefulWidget {
  final PackManager packManager;
  final StorageService storage;

  const OnlineImportScreen({
    super.key,
    required this.packManager,
    required this.storage,
  });

  @override
  State<OnlineImportScreen> createState() => _OnlineImportScreenState();
}

class _OnlineImportScreenState extends State<OnlineImportScreen> {
  static const _exampleChecklistAsset = 'assets/data/ebird_sample_checklist.csv';
  static const _chinaChecklistAsset = 'assets/data/china_birds.json';

  final AviListService _aviListService = AviListService();
  final _searchController = TextEditingController();
  final _manualInputController = TextEditingController();
  Map<String, Map<String, String>> _chinaBirdBySci = {};
  Map<String, Map<String, String>> _chinaBirdByEnglish = {};

  List<SpeciesEntry> _speciesList = [];
  List<AviListSpecies> _searchResults = [];
  bool _loading = false;
  bool _searching = false;
  bool _aviListReady = false;

  final _packNameController = TextEditingController(text: 'AviList 鸟鸣包');
  final _regionController = TextEditingController(text: '自选物种');

  @override
  void initState() {
    super.initState();
    _prepareAviList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _manualInputController.dispose();
    _packNameController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  Future<void> _prepareAviList() async {
    try {
      await _aviListService.loadAllSpecies();
      await _prepareChinaBirdLookup();
      if (mounted) {
        setState(() => _aviListReady = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AviList 载入失败: $e')),
        );
      }
    }
  }

  Future<void> _prepareChinaBirdLookup() async {
    final raw = await rootBundle.loadString(_chinaChecklistAsset);
    final data = jsonDecode(raw) as List<dynamic>;
    _chinaBirdBySci = {
      for (final item in data.cast<Map<String, dynamic>>())
        ((item['sci'] as String? ?? '').trim().toLowerCase()): {
          'zh': (item['zh'] as String? ?? '').trim(),
          'en': (item['en'] as String? ?? '').trim(),
          'protection': (item['protection'] as String? ?? '').trim(),
        },
    }..remove('');
    _chinaBirdByEnglish = {
      for (final item in data.cast<Map<String, dynamic>>())
        ((item['en'] as String? ?? '').trim().toLowerCase()): {
          'zh': (item['zh'] as String? ?? '').trim(),
          'en': (item['en'] as String? ?? '').trim(),
          'protection': (item['protection'] as String? ?? '').trim(),
        },
    }..remove('');
  }

  Future<void> _importFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'csv', 'json'],
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) return;

    setState(() => _loading = true);
    try {
      final content = await File(path).readAsString();
      final entries = await _parseImportedContent(
        content: content,
        extension: path.split('.').last.toLowerCase(),
      );

      if (mounted) {
        setState(() {
          _speciesList = _dedupeEntries([..._speciesList, ...entries]);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解析失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<SpeciesEntry>> _parseImportedContent({
    required String content,
    required String extension,
  }) async {
    if (extension == 'json') {
      final data = jsonDecode(content) as List<dynamic>;
      return _parseJsonEntries(data);
    }
    if (extension == 'csv') {
      return _parseCsvEntries(content);
    }
    return _parseTextEntries(content);
  }

  Future<List<SpeciesEntry>> _parseCsvEntries(String content) async {
    final lines = content
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return [];

    final rows = lines
        .map((line) => line.split(',').map((item) => item.trim()).toList())
        .where((columns) => columns.any((value) => value.isNotEmpty))
        .toList();
    if (rows.isEmpty) return [];

    final header = rows.first.map((value) => value.trim().toLowerCase()).toList();
    final sciIndex = header.indexOf('scientific name');
    final enIndex = header.indexOf('english name');
    final cnIndex = header.indexOf('中文名');
    final locationIndex = header.indexOf('发现地点');
    final noteIndex = header.indexOf('备注');

    if (sciIndex < 0 && enIndex < 0 && cnIndex < 0) {
      return _parseTextEntries(content);
    }

    final results = <SpeciesEntry>[];
    for (final row in rows.skip(1)) {
      final sci = sciIndex >= 0 && sciIndex < row.length ? row[sciIndex].trim() : '';
      final en = enIndex >= 0 && enIndex < row.length ? row[enIndex].trim() : '';
      final cn = cnIndex >= 0 && cnIndex < row.length ? row[cnIndex].trim() : '';
      final note = locationIndex >= 0 && locationIndex < row.length
          ? row[locationIndex].trim()
          : noteIndex >= 0 && noteIndex < row.length
              ? row[noteIndex].trim()
              : '';

      final resolvedSci = sci.isNotEmpty ? sci : _resolveEnglishName(sci: '', en: en);
      if (!_looksLikeScientificName(resolvedSci)) continue;

      final resolvedEn = _resolveEnglishName(sci: resolvedSci, en: en);
      results.add(
        SpeciesEntry(
          cn: _resolveChineseName(sci: resolvedSci, en: resolvedEn, cn: cn),
          en: resolvedEn,
          sci: resolvedSci,
          cons: _normalizeProtection(
            _lookupChinaBird(sci: resolvedSci, en: resolvedEn)?['protection'] ?? '',
          ),
          habitat: note,
        ),
      );
    }
    return results;
  }

  List<SpeciesEntry> _parseJsonEntries(List<dynamic> data) {
    return data
        .map((item) => _speciesEntryFromMap(item as Map<String, dynamic>))
        .whereType<SpeciesEntry>()
        .where((entry) => entry.sci.trim().isNotEmpty)
        .toList();
  }

  SpeciesEntry? _speciesEntryFromMap(Map<String, dynamic> json) {
    final sci = (json['sci'] as String? ?? '').trim();
    if (sci.isEmpty) return null;

    final cn = _resolveChineseName(
      sci: sci,
      en: (json['en'] as String? ?? '').trim(),
      cn: (json['cn'] as String? ?? json['zh'] as String? ?? '').trim(),
    );
    final en = _resolveEnglishName(
      sci: sci,
      en: (json['en'] as String? ?? '').trim(),
    );
    final cons = _normalizeProtection(
      (json['cons'] as String? ??
              json['protection'] as String? ??
              _lookupChinaBird(sci: sci, en: en)?['protection'] ??
              '')
          .trim(),
    );
    final habitat = (json['habitat'] as String? ??
            json['发现地点'] as String? ??
            json['备注'] as String? ??
            '')
        .trim();

    return SpeciesEntry(
      cn: cn,
      en: en,
      sci: sci,
      cons: cons,
      habitat: habitat,
    );
  }

  Map<String, String>? _lookupChinaBird({
    required String sci,
    required String en,
  }) {
    return _chinaBirdBySci[sci.trim().toLowerCase()] ??
        _chinaBirdByEnglish[en.trim().toLowerCase()];
  }

  String _resolveChineseName({
    required String sci,
    required String en,
    required String cn,
  }) {
    if (cn.isNotEmpty && cn != en) return cn;
    final matched = _lookupChinaBird(sci: sci, en: en);
    final zh = matched?['zh'] ?? '';
    if (zh.isNotEmpty) return zh;
    if (cn.isNotEmpty) return cn;
    if (en.isNotEmpty) return en;
    return sci;
  }

  String _resolveEnglishName({
    required String sci,
    required String en,
  }) {
    if (en.isNotEmpty) return en;
    final matched = _lookupChinaBird(sci: sci, en: en);
    final resolved = matched?['en'] ?? '';
    if (resolved.isNotEmpty) return resolved;
    return sci;
  }

  String _normalizeProtection(String value) {
    switch (value) {
      case '一级':
      case '1':
        return '1';
      case '二级':
      case '2':
        return '2';
      default:
        return '';
    }
  }

  Future<List<SpeciesEntry>> _parseTextEntries(String content) async {
    final lines = content
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final all = await _aviListService.loadAllSpecies();
    final bySci = <String, AviListSpecies>{
      for (final item in all) item.sci.toLowerCase(): item,
    };
    final byEnglish = <String, AviListSpecies>{
      for (final item in all) item.en.toLowerCase(): item,
    };

    final results = <SpeciesEntry>[];
    for (final line in lines) {
      final columns = line
          .split(RegExp(r'[\t,;]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (columns.isEmpty) continue;
      if (_isHeaderRow(columns)) continue;

      final structuredEntry = _parseStructuredTextColumns(columns);
      if (structuredEntry != null) {
        results.add(structuredEntry);
        continue;
      }

      AviListSpecies? matched;
      for (final candidate in columns) {
        matched = bySci[candidate.toLowerCase()] ?? byEnglish[candidate.toLowerCase()];
        if (matched != null) break;
      }
      final raw = columns.first;
      final note = matched == null
          ? (columns.length > 1 ? columns.skip(1).join(' / ') : '')
          : columns
              .where((value) {
                final lowered = value.toLowerCase();
                return lowered != matched!.sci.toLowerCase() &&
                    lowered != matched.en.toLowerCase();
              })
              .join(' / ');
      if (matched != null) {
        final cn = _resolveChineseName(
          sci: matched.sci,
          en: matched.en,
          cn: '',
        );
        results.add(
          SpeciesEntry(
            cn: cn,
            en: matched.en,
            sci: matched.sci,
            cons: _normalizeProtection(
              _lookupChinaBird(sci: matched.sci, en: matched.en)?['protection'] ?? '',
            ),
            habitat: note.isNotEmpty ? note : matched.range,
          ),
        );
      } else if (_looksLikeScientificName(raw)) {
        final en = _resolveEnglishName(sci: raw, en: '');
        results.add(
          SpeciesEntry(
            cn: _resolveChineseName(sci: raw, en: en, cn: ''),
            en: en,
            sci: raw,
            cons: _normalizeProtection(
              _lookupChinaBird(sci: raw, en: en)?['protection'] ?? '',
            ),
            habitat: note,
          ),
        );
      }
    }
    return results;
  }

  SpeciesEntry? _parseStructuredTextColumns(List<String> columns) {
    if (columns.length < 3) return null;

    final sciIndex = columns.indexWhere(_looksLikeScientificName);
    if (sciIndex < 0) return null;

    final sci = columns[sciIndex];
    final beforeSci = columns.take(sciIndex).toList();
    final afterSci = columns.skip(sciIndex + 1).toList();

    String cn = '';
    String en = '';
    if (beforeSci.length >= 2) {
      cn = beforeSci[0];
      en = beforeSci[1];
    } else if (beforeSci.length == 1) {
      final candidate = beforeSci[0];
      if (_containsChinese(candidate)) {
        cn = candidate;
      } else {
        en = candidate;
      }
    }

    cn = _resolveChineseName(sci: sci, en: en, cn: cn);
    en = _resolveEnglishName(sci: sci, en: en);

    return SpeciesEntry(
      cn: cn,
      en: en,
      sci: sci,
      cons: _normalizeProtection(
        _lookupChinaBird(sci: sci, en: en)?['protection'] ?? '',
      ),
      habitat: afterSci.join(' / '),
    );
  }

  bool _isHeaderRow(List<String> columns) {
    final normalized = columns.map((value) => value.trim().toLowerCase()).toSet();
    return normalized.contains('中文名') ||
        normalized.contains('cn') ||
        normalized.contains('zh') ||
        normalized.contains('english name') ||
        normalized.contains('scientific name') ||
        normalized.contains('发现地点') ||
        normalized.contains('备注');
  }

  bool _containsChinese(String value) => RegExp(r'[\u4e00-\u9fff]').hasMatch(value);

  bool _looksLikeScientificName(String value) {
    final parts = value.trim().split(RegExp(r'\s+'));
    return parts.length >= 2 &&
        parts[0].isNotEmpty &&
        parts[0][0] == parts[0][0].toUpperCase();
  }

  Future<void> _addManualInput() async {
    final text = _manualInputController.text.trim();
    if (text.isEmpty) return;
    final parsed = await _parseTextEntries(text);
    if (!mounted) return;
    setState(() {
      _speciesList = _dedupeEntries([..._speciesList, ...parsed]);
    });
    _manualInputController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已加入 ${parsed.length} 个物种')),
    );
  }

  Future<void> _loadExample() async {
    setState(() => _loading = true);
    try {
      final csv = await rootBundle.loadString(_exampleChecklistAsset);
      final parsed = await _parseCsvEntries(csv);
      if (!mounted) return;
      setState(() {
        _speciesList = _dedupeEntries([..._speciesList, ...parsed]);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已加入 eBird 示例清单 ${parsed.length} 种')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载示例清单失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadChinaChecklist() async {
    setState(() => _loading = true);
    try {
      final raw = await rootBundle.loadString(_chinaChecklistAsset);
      final parsed = _parseJsonEntries(jsonDecode(raw) as List<dynamic>);
      if (!mounted) return;
      setState(() {
        _speciesList = _dedupeEntries([..._speciesList, ...parsed]);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已加入中国名录 ${parsed.length} 种')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载中国名录失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _searchAviList(String value) async {
    final query = value.trim();
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _searching = true);
    final results = await _aviListService.search(query);
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _searching = false;
    });
  }

  void _addFromAviList(AviListSpecies species) {
    final cn = _resolveChineseName(
      sci: species.sci,
      en: species.en,
      cn: '',
    );
    final entry = SpeciesEntry(
      cn: cn,
      en: species.en,
      sci: species.sci,
      cons: _normalizeProtection(
        _lookupChinaBird(sci: species.sci, en: species.en)?['protection'] ?? '',
      ),
      habitat: species.range,
    );
    setState(() {
      _speciesList = _dedupeEntries([..._speciesList, entry]);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已加入: $cn')),
    );
  }

  List<SpeciesEntry> _dedupeEntries(List<SpeciesEntry> entries) {
    final seen = <String>{};
    final result = <SpeciesEntry>[];
    for (final entry in entries) {
      final key = entry.sci.trim().toLowerCase();
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      result.add(entry);
    }
    return result;
  }

  Future<void> _startDownload() async {
    if (_speciesList.isEmpty) return;
    final apiKey = widget.storage.getXenoCantoApiKey();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在数据包页填写你的 Xeno-Canto API key')),
      );
      return;
    }

    final packName = _packNameController.text.trim();
    if (packName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入数据包名称')),
      );
      return;
    }

    try {
      final started = DownloadTaskService.instance.start(
        speciesList: _speciesList,
        packName: packName,
        region: _regionController.text.trim(),
        packManager: widget.packManager,
        storage: widget.storage,
        onPackActivated: () {},
      );
      if (!started) {
        throw Exception('已有下载任务正在进行中');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已开始后台下载，现在可以返回总览继续查看进度。'),
          duration: Duration(seconds: 4),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('下载失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('在线导入鸟种数据'),
        backgroundColor: const Color(0xFF2d5016),
        foregroundColor: Colors.white,
      ),
      body: _buildInputView(),
    );
  }

  Widget _buildInputView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Colors.blue[50],
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                leading: Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                title: Text(
                  '使用说明',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.blue[700],
                  ),
                ),
                subtitle: const Text(
                  '支持手输、导入文件、示例清单和中国名录',
                  style: TextStyle(fontSize: 12),
                ),
                children: [
                  Text(
                    '1. 先在“数据包”页填写自己的 Xeno-Canto API key\n'
                    '2. 这里可直接输入、搜索，或导入 txt / csv / json\n'
                    '3. eBird 示例清单和中国名录都可以一键加入\n'
                    '4. 下载会在后台继续进行，完成后自动生成并激活数据包',
                    style: TextStyle(fontSize: 13, color: Colors.blue[900]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _packNameController,
            decoration: InputDecoration(
              labelText: '数据包名称',
              prefixIcon: const Icon(Icons.label),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _regionController,
            decoration: InputDecoration(
              labelText: '地区（可选）',
              prefixIcon: const Icon(Icons.location_on),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '直接输入物种',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _manualInputController,
                    minLines: 4,
                    maxLines: 8,
                    decoration: InputDecoration(
                      hintText: '每行一个英文名或学名，也支持粘贴 csv/txt 内容',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _addManualInput,
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('加入列表'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildAviListSearch(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _importFromFile,
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.file_upload),
                  label: Text(_loading ? '解析中...' : '导入清单 (.txt / .csv / .json)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2d5016),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: _loading ? null : _loadExample,
                icon: const Icon(Icons.science, size: 18),
                label: Text(_loading ? '加载中...' : '加入 eBird 示例清单'),
              ),
              TextButton.icon(
                onPressed: _loading ? null : _loadChinaChecklist,
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: Text(_loading ? '加载中...' : '加入中国名录'),
              ),
            ],
          ),
          if (_speciesList.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '待下载 ${_speciesList.length} 个物种',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _speciesList.clear();
                  }),
                  child: const Text('清空', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _speciesList.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
                itemBuilder: (context, i) {
                  final s = _speciesList[i];
                  return ListTile(
                    dense: true,
                    leading: Text('${i + 1}', style: TextStyle(color: Colors.grey[600])),
                    title: Text(s.cn, style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      '${s.sci}\n${s.en}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _speciesList.removeAt(i)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _speciesList.isNotEmpty ? _startDownload : null,
                icon: const Icon(Icons.cloud_download),
                label: Text('开始下载（${_speciesList.length} 种鸟）'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '使用相同数据包名称再次下载时，会自动跳过已成功的物种，继续补下剩余内容。',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAviListSearch() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.travel_explore, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'AviList 全鸟类搜索',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (_aviListReady)
                  Text(
                    '11131 种',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              onChanged: _searchAviList,
              decoration: InputDecoration(
                hintText: '输入英文名或学名，如 hornbill / Buceros bicornis',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _searchAviList('');
                        },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),
            if (!_aviListReady)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('正在载入 AviList 物种库...'),
              )
            else if (_searching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              )
            else if (_searchController.text.trim().isNotEmpty && _searchResults.isEmpty)
              Text(
                '没有匹配结果，试试更完整的英文名或学名。',
                style: TextStyle(color: Colors.grey[600]),
              )
            else if (_searchResults.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 320),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
                  itemBuilder: (context, index) {
                    final species = _searchResults[index];
                    final alreadyAdded = _speciesList.any(
                      (entry) => entry.sci.toLowerCase() == species.sci.toLowerCase(),
                    );
                    final cn = _resolveChineseName(
                      sci: species.sci,
                      en: species.en,
                      cn: '',
                    );
                    return ListTile(
                      dense: true,
                      title: Text(cn),
                      subtitle: Text(
                        '${species.en}\n${species.sci}\n${species.family} · ${species.iucn.isEmpty ? "IUCN 未知" : species.iucn}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                      isThreeLine: true,
                      trailing: FilledButton(
                        onPressed: alreadyAdded ? null : () => _addFromAviList(species),
                        child: Text(alreadyAdded ? '已加入' : '加入'),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
