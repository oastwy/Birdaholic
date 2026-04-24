import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/species.dart';
import '../services/download_task_service.dart';
import '../services/pack_downloader.dart';
import '../services/pack_manager.dart';
import '../services/storage.dart';
import '../widgets/species_tile.dart';

/// 鸟种列表页面
class SpeciesListScreen extends StatefulWidget {
  final PackManager packManager;
  final StorageService storage;
  final void Function(Species) onJumpToFlashcard;
  final VoidCallback? onPackChanged;
  final int refreshToken;
  final bool isActive;

  const SpeciesListScreen({
    super.key,
    required this.packManager,
    required this.storage,
    required this.onJumpToFlashcard,
    this.onPackChanged,
    required this.refreshToken,
    required this.isActive,
  });

  @override
  State<SpeciesListScreen> createState() => _SpeciesListScreenState();
}

class _SpeciesListScreenState extends State<SpeciesListScreen> {
  static const _chinaChecklistAsset = 'assets/data/china_birds.json';

  List<Species> _activeSpecies = [];
  List<Species> _chinaSpecies = [];
  final Set<String> _selectedSci = <String>{};
  String _source = 'china';
  String _filter = 'all';
  String _search = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSpecies();
  }

  @override
  void didUpdateWidget(covariant SpeciesListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        (!oldWidget.isActive && widget.isActive)) {
      _loadSpecies();
    }
  }

  Future<void> _loadSpecies() async {
    setState(() => _loading = true);
    try {
      final activeList = await widget.packManager.loadSpecies();
      final chinaList = await _loadChinaSpecies(activeList);
      if (mounted) {
        setState(() {
          _activeSpecies = activeList;
          _chinaSpecies = chinaList;
          _selectedSci.removeWhere(
            (sci) => !_chinaSpecies.any((species) => species.sci == sci),
          );
          _loading = false;
        });
      }
    } catch (_) {
      final chinaList = await _loadChinaSpecies(const []);
      if (mounted) {
        setState(() {
          _activeSpecies = [];
          _chinaSpecies = chinaList;
          _selectedSci.removeWhere(
            (sci) => !_chinaSpecies.any((species) => species.sci == sci),
          );
          _loading = false;
        });
      }
    }
  }

  Future<List<Species>> _loadChinaSpecies(List<Species> activeList) async {
    final activeBySci = {
      for (final species in activeList) species.sci.trim().toLowerCase(): species,
    };
    final raw = await rootBundle.loadString(_chinaChecklistAsset);
    final data = jsonDecode(raw) as List<dynamic>;

    final list = data
        .map((item) {
          final json = item as Map<String, dynamic>;
          final sci = (json['sci'] as String? ?? '').trim();
          if (sci.isEmpty) return null;

          final existing = activeBySci[sci.toLowerCase()];
          return Species(
            cn: (json['zh'] as String? ?? '').trim(),
            en: (json['en'] as String? ?? '').trim(),
            sci: sci,
            cons: _normalizeProtection(
              (json['protection'] as String? ?? '').trim(),
            ),
            habitat: existing?.habitat ?? '',
            audios: existing?.audios ?? const [],
            image: existing?.image,
          );
        })
        .whereType<Species>()
        .toList()
      ..sort((a, b) {
        final aName = a.cn.isNotEmpty ? a.cn : a.sci;
        final bName = b.cn.isNotEmpty ? b.cn : b.sci;
        return aName.compareTo(bName);
      });

    return list;
  }

  String _normalizeProtection(String value) {
    if (value.contains('一级')) return '1';
    if (value.contains('二级')) return '2';
    return value;
  }

  Future<void> _deleteSpecies(Species species) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除鸟种数据'),
        content: Text('确定删除「${species.cn}」吗？这会同时移除它的音频和图片文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await widget.packManager.deleteSpeciesFromActivePack(species);
    await _loadSpecies();
    widget.onPackChanged?.call();
  }

  Future<void> _downloadSelected() async {
    final selected = _chinaSpecies
        .where((species) => _selectedSci.contains(species.sci))
        .map(
          (species) => SpeciesEntry(
            cn: species.cn,
            en: species.en,
            sci: species.sci,
            cons: species.cons,
            habitat: species.habitat,
          ),
        )
        .toList();

    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先勾选要下载的鸟种')),
      );
      return;
    }

    try {
      final started = DownloadTaskService.instance.start(
        speciesList: selected,
        packName: '中国鸟类名录',
        region: '中国',
        packManager: widget.packManager,
        storage: widget.storage,
        onPackActivated: widget.onPackChanged,
      );
      if (!started) {
        throw Exception('已有下载任务正在进行中');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已开始后台下载 ${selected.length} 种，可以回到总览查看进度。'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('启动下载失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<Species> get _displayedSpecies =>
      _source == 'china' ? _chinaSpecies : _activeSpecies;

  List<Species> get _filteredSpecies {
    var list = <Species>[..._displayedSpecies];

    switch (_filter) {
      case 'audio':
        list = list.where((species) => species.hasAudio).toList();
        break;
    }

    if (_search.isNotEmpty) {
      final query = _search.toLowerCase();
      list = list
          .where(
            (species) =>
                species.cn.contains(_search) ||
                species.en.toLowerCase().contains(query) ||
                species.sci.toLowerCase().contains(query) ||
                species.habitat.toLowerCase().contains(query),
          )
          .toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredSpecies;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Expanded(child: _sourceChip('全国名录', 'china')),
              const SizedBox(width: 8),
              Expanded(child: _sourceChip('当前数据包', 'active')),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(
              hintText: _source == 'china' ? '搜索全国鸟种...' : '搜索当前数据包...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _search = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _filterChip('全部', 'all'),
              const SizedBox(width: 8),
              _filterChip('已下载', 'audio'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Text(
                _source == 'china'
                    ? '全国名录 ${filtered.length} 种'
                    : '当前数据包 ${filtered.length} 种',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const Spacer(),
              if (_source == 'china')
                Text(
                  '已选 ${_selectedSci.length} 种',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
            ],
          ),
        ),
        if (_source == 'china')
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                TextButton(
                  onPressed: filtered.isEmpty
                      ? null
                      : () {
                          setState(() {
                            for (final species in filtered) {
                              _selectedSci.add(species.sci);
                            }
                          });
                        },
                  child: const Text('勾选当前结果'),
                ),
                TextButton(
                  onPressed: _selectedSci.isEmpty
                      ? null
                      : () => setState(_selectedSci.clear),
                  child: const Text('清空勾选'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _selectedSci.isEmpty ? null : _downloadSelected,
                  icon: const Icon(Icons.download),
                  label: const Text('下载选中'),
                ),
              ],
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                        _search.isNotEmpty
                            ? '没有匹配的鸟种'
                            : _source == 'china'
                                ? '全国名录加载为空'
                                : '当前数据包暂无鸟种',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final species = filtered[index];
                        final inChinaMode = _source == 'china';
                        return SpeciesTile(
                          species: species,
                          onTap: () {
                            if (inChinaMode) {
                              setState(() {
                                if (_selectedSci.contains(species.sci)) {
                                  _selectedSci.remove(species.sci);
                                } else {
                                  _selectedSci.add(species.sci);
                                }
                              });
                            } else {
                              widget.onJumpToFlashcard(species);
                            }
                          },
                          isFavorite: !inChinaMode &&
                              widget.storage.isFavorite(species.cn),
                          onFavoriteToggle: () {
                            if (inChinaMode) return;
                            widget.storage.toggleFavorite(species.cn);
                            setState(() {});
                          },
                          showFavorite: !inChinaMode,
                          showDelete: !inChinaMode,
                          onDelete: inChinaMode ? null : () => _deleteSpecies(species),
                          selected: _selectedSci.contains(species.sci),
                          onSelectedChanged: inChinaMode
                              ? (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedSci.add(species.sci);
                                    } else {
                                      _selectedSci.remove(species.sci);
                                    }
                                  });
                                }
                              : null,
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _sourceChip(String label, String value) {
    final selected = _source == value;
    return FilledButton(
      onPressed: () => setState(() => _source = value),
      style: FilledButton.styleFrom(
        backgroundColor: selected ? const Color(0xFF2d5016) : Colors.grey[200],
        foregroundColor: selected ? Colors.white : Colors.grey[800],
      ),
      child: Text(label),
    );
  }

  Widget _filterChip(String label, String value) {
    final active = _filter == value;
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 13)),
      selected: active,
      onSelected: (_) => setState(() => _filter = value),
    );
  }
}
