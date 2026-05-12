import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../models/species.dart';
import '../services/download_task_service.dart';
import '../services/ebird_service.dart';
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
  static const _chinaChecklistAsset = 'assets/data/world_birds.json';

  List<Species> _activeSpecies = [];
  List<Species> _chinaSpecies = [];
  Map<String, String> _chinaCodeBySci = {};
  final Set<String> _selectedSci = <String>{};
  String _source = 'china';
  String _filter = 'all';
  String _orderFilter = 'all';
  String _search = '';
  String _locationFilterLabel = '';
  Set<String> _locationSpeciesCodes = {};
  Set<String> _locationScientificNames = {};
  Set<String> _locationCommonNames = {};
  bool _locationLoading = false;
  bool _nearbyLoading = false;
  bool _loading = true;
  final _locationController = TextEditingController();
  final _searchController = TextEditingController();
  List<EbirdLocationPreset> _locationResults = EBirdService.presets;

  @override
  void initState() {
    super.initState();
    _loadSpecies();
  }

  @override
  void dispose() {
    _locationController.dispose();
    _searchController.dispose();
    super.dispose();
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
          _chinaCodeBySci = _buildChinaCodeMap();
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
          _chinaCodeBySci = _buildChinaCodeMap();
          _selectedSci.removeWhere(
            (sci) => !_chinaSpecies.any((species) => species.sci == sci),
          );
          _loading = false;
        });
      }
    }
  }

  Map<String, String> _buildChinaCodeMap() {
    final map = <String, String>{};
    for (final species in _chinaSpecies) {
      final code = _extractCodeFromHabitat(species.habitat);
      if (code.isNotEmpty) {
        map[species.sci.trim().toLowerCase()] = code;
      }
    }
    return map;
  }

  Future<List<Species>> _loadChinaSpecies(List<Species> activeList) async {
    final activeBySci = {
      for (final species in activeList)
        species.sci.trim().toLowerCase(): species,
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
            order: (json['order'] as String? ?? '').trim(),
            family: (json['family'] as String? ?? '').trim(),
            cons: _normalizeProtection(
              (json['protection'] as String? ?? '').trim(),
            ),
            habitat: _buildChinaHabitat((json['code'] as String? ?? '').trim()),
            audios: existing?.audios ?? const [],
            image: existing?.image,
            enAlt:
                (json['en_alt'] as List<dynamic>?)?.cast<String>() ?? const [],
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

  String _buildChinaHabitat(String code) {
    if (code.isEmpty) return '';
    return 'ebird:$code';
  }

  String _extractCodeFromHabitat(String habitat) {
    const prefix = 'ebird:';
    if (!habitat.startsWith(prefix)) return '';
    return habitat.substring(prefix.length).trim().toLowerCase();
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
        .map(_speciesEntry)
        .toList();

    if (selected.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先勾选要下载的鸟种')));
      return;
    }

    try {
      final started = DownloadTaskService.instance.start(
        speciesList: selected,
        packName: '服务器鸟种包',
        region: '中国',
        packManager: widget.packManager,
        storage: widget.storage,
        allowApiFallback: false,
        onPackActivated: widget.onPackChanged,
      );
      if (!started) {
        throw Exception('已有下载任务正在进行中');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已开始从服务器后台下载 ${selected.length} 种。')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('启动下载失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  SpeciesEntry _speciesEntry(Species species) {
    return SpeciesEntry(
      cn: species.cn,
      en: species.en,
      sci: species.sci,
      cons: species.cons,
      habitat: species.habitat,
    );
  }

  Future<void> _downloadOneFromServer(Species species) async {
    final packName = _source == 'china' ? '服务器鸟种包' : '当前数据包';
    try {
      final started = DownloadTaskService.instance.start(
        speciesList: [_speciesEntry(species)],
        packName: packName,
        region: '中国',
        packManager: widget.packManager,
        storage: widget.storage,
        allowApiFallback: false,
        onPackActivated: widget.onPackChanged,
      );
      if (!started) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已有下载任务正在后台进行')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已开始从服务器下载「${species.cn}」')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('启动下载失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  List<Species> get _displayedSpecies =>
      _source == 'china' ? _chinaSpecies : _activeSpecies;

  List<Species> get _filteredSpecies {
    var list = <Species>[..._displayedSpecies];

    if (_source == 'china' && _locationSpeciesCodes.isNotEmpty) {
      list = list.where(_matchesLocationFilter).toList();
    }

    switch (_filter) {
      case 'audio':
        list = list.where((species) => species.hasAudio).toList();
        break;
    }

    if (_orderFilter != 'all') {
      list = list.where((species) => species.order == _orderFilter).toList();
    }

    if (_search.isNotEmpty) {
      final query = _search.toLowerCase();
      list = list
          .where(
            (species) =>
                species.cn.contains(_search) ||
                species.en.toLowerCase().contains(query) ||
                species.sci.toLowerCase().contains(query) ||
                species.habitat.toLowerCase().contains(query) ||
                species.enAlt.any((alt) => alt.toLowerCase().contains(query)),
          )
          .toList();
    }

    return list;
  }

  int get _locationMatchedCount {
    if (_source != 'china' || _locationSpeciesCodes.isEmpty) return 0;
    return _displayedSpecies.where(_matchesLocationFilter).length;
  }

  bool _matchesLocationFilter(Species species) {
    final code = _chinaCodeBySci[species.sci.trim().toLowerCase()] ?? '';
    if (code.isNotEmpty && _locationSpeciesCodes.contains(code.toLowerCase())) {
      return true;
    }

    final sci = _normalizeSpeciesText(species.sci);
    if (sci.isNotEmpty && _locationScientificNames.contains(sci)) return true;

    final names = {
      _normalizeSpeciesText(species.en),
      ...species.enAlt.map(_normalizeSpeciesText),
    }..removeWhere((name) => name.isEmpty);
    return names.any(_locationCommonNames.contains);
  }

  String _normalizeSpeciesText(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\u2018\u2019`]'), "'")
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _setLocationMatches(Set<EbirdSpeciesMatch> matches) {
    _locationSpeciesCodes = matches
        .map((item) => item.code.trim().toLowerCase())
        .where((code) => code.isNotEmpty)
        .toSet();
    _locationScientificNames = matches
        .map((item) => _normalizeSpeciesText(item.scientificName))
        .where((name) => name.isNotEmpty)
        .toSet();
    _locationCommonNames = matches
        .map((item) => _normalizeSpeciesText(item.commonName))
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  List<String> get _availableOrders {
    final orders = _displayedSpecies
        .map((species) => species.order)
        .where((order) => order.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return orders;
  }

  String _orderLabel(String order) {
    const labels = {
      'STRUTHIONIFORMES': '鸵鸟目',
      'RHEIFORMES': '美洲鸵目',
      'APTERYGIFORMES': '无翼鸟目',
      'CASUARIIFORMES': '鹤鸵目',
      'TINAMIFORMES': '䳍形目',
      'ANSERIFORMES': '雁形目',
      'GALLIFORMES': '鸡形目',
      'PHOENICOPTERIFORMES': '红鹳目',
      'PODICIPEDIFORMES': '䴙䴘目',
      'COLUMBIFORMES': '鸽形目',
      'PTEROCLIFORMES': '沙鸡目',
      'CUCULIFORMES': '鹃形目',
      'CAPRIMULGIFORMES': '夜鹰目',
      'APODIFORMES': '雨燕目',
      'GRUIFORMES': '鹤形目',
      'CHARADRIIFORMES': '鸻形目',
      'ACCIPITRIFORMES': '鹰形目',
      'STRIGIFORMES': '鸮形目',
      'BUCEROTIFORMES': '犀鸟目',
      'CORACIIFORMES': '佛法僧目',
      'PICIFORMES': '䴕形目',
      'FALCONIFORMES': '隼形目',
      'PSITTACIFORMES': '鹦形目',
      'PASSERIFORMES': '雀形目',
    };
    return labels[order.toUpperCase()] ?? order;
  }

  void _searchLocationPresets(String value) {
    setState(() {
      _locationResults = EBirdService.searchPresets(value);
    });
  }

  Future<void> _applyLocationFilter(String query) async {
    final apiKey = widget.storage.getEBirdApiKey();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在数据包页填写 eBird API key')));
      return;
    }

    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return;

    setState(() => _locationLoading = true);
    try {
      final service = EBirdService(apiKey: apiKey);
      final nearby = _parseCoordinates(normalizedQuery);
      final matches = nearby == null
          ? await service.fetchSpeciesMatches(normalizedQuery)
          : await service.fetchNearbySpeciesMatches(
              latitude: nearby.$1,
              longitude: nearby.$2,
              distanceKm: nearby.$3,
            );
      if (!mounted) return;
      setState(() {
        _source = 'china';
        _filter = 'all';
        _orderFilter = 'all';
        _search = '';
        _searchController.clear();
        _locationFilterLabel = normalizedQuery;
        _setLocationMatches(matches);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已按地点匹配 $_locationMatchedCount 种本地鸟种')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('地点筛选失败: $e')));
    } finally {
      if (mounted) {
        setState(() => _locationLoading = false);
      }
    }
  }

  Future<void> _applyCurrentLocationFilter() async {
    final apiKey = widget.storage.getEBirdApiKey();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在数据包页填写 eBird API key')));
      return;
    }

    setState(() => _nearbyLoading = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('手机定位服务未开启');
      }

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

      final service = EBirdService(apiKey: apiKey);
      final matches = await service.fetchNearbySpeciesMatches(
        latitude: position.latitude,
        longitude: position.longitude,
        distanceKm: 25,
      );
      if (!mounted) return;
      setState(() {
        _source = 'china';
        _filter = 'all';
        _orderFilter = 'all';
        _search = '';
        _searchController.clear();
        _locationFilterLabel =
            '当前位置 ${position.latitude.toStringAsFixed(3)}, ${position.longitude.toStringAsFixed(3)}';
        _setLocationMatches(matches);
        _locationController.text =
            '${position.latitude.toStringAsFixed(5)},${position.longitude.toStringAsFixed(5)}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已按附近 25km 匹配 $_locationMatchedCount 种本地鸟种')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('附近鸟种查询失败: $e')));
    } finally {
      if (mounted) setState(() => _nearbyLoading = false);
    }
  }

  void _clearLocationFilter() {
    setState(() {
      _locationFilterLabel = '';
      _locationSpeciesCodes = {};
      _locationScientificNames = {};
      _locationCommonNames = {};
      _locationController.clear();
      _locationResults = EBirdService.presets;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredSpecies;

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '鸟种页：查看鸟种、按 eBird 地点筛出附近鸟，并选择单个鸟种补充媒体。',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    Expanded(child: _sourceChip('鸟种名录', 'china')),
                    const SizedBox(width: 8),
                    Expanded(child: _sourceChip('当前数据包', 'active')),
                  ],
                ),
              ),
              if (_source == 'china') ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.place_outlined, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                '按地点筛选学习范围',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              if (_locationFilterLabel.isNotEmpty)
                                TextButton(
                                  onPressed: _clearLocationFilter,
                                  child: const Text('清除'),
                                ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _nearbyLoading
                                    ? null
                                    : _applyCurrentLocationFilter,
                                icon: _nearbyLoading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.my_location),
                                label: const Text('使用当前位置查附近鸟种'),
                              ),
                            ),
                          ),
                          TextField(
                            controller: _locationController,
                            onChanged: _searchLocationPresets,
                            decoration: InputDecoration(
                              hintText: '输入云南、那邦、eBird代码，或经纬度 24.7,97.6',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _locationLoading
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.arrow_forward),
                                      onPressed: () => _applyLocationFilter(
                                        _locationController.text,
                                      ),
                                    ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onSubmitted: _applyLocationFilter,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _locationResults.take(5).map((item) {
                              return ActionChip(
                                label: Text(item.label),
                                onPressed: () {
                                  _locationController.text = item.label;
                                  _applyLocationFilter(item.code);
                                },
                              );
                            }).toList(),
                          ),
                          if (_locationFilterLabel.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '当前地点：$_locationFilterLabel · 匹配 $_locationMatchedCount 种',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText:
                        _source == 'china' ? '搜索鸟种名录、中英文名或学名...' : '搜索当前数据包...',
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
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _filterChip('全部', 'all'),
                    _filterChip('已下载', 'audio'),
                    if (_availableOrders.isNotEmpty)
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          value: _orderFilter,
                          isDense: true,
                          decoration: const InputDecoration(
                            labelText: '按目筛选',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          items: [
                            const DropdownMenuItem(
                                value: 'all', child: Text('全部目')),
                            ..._availableOrders.map(
                              (order) => DropdownMenuItem(
                                value: order,
                                child: Text(
                                  _orderLabel(order),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _orderFilter = value);
                          },
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    Text(
                      _source == 'china'
                          ? '鸟种名录 ${filtered.length} 种'
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
                        onPressed:
                            _selectedSci.isEmpty ? null : _downloadSelected,
                        icon: const Icon(Icons.download),
                        label: const Text('补充选中鸟种'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (_loading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (filtered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                _search.isNotEmpty
                    ? '没有匹配的鸟种'
                    : _source == 'china'
                        ? '鸟种名录加载为空'
                        : '当前数据包暂无鸟种',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          SliverList.builder(
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
                isFavorite:
                    !inChinaMode && widget.storage.isFavorite(species.cn),
                onFavoriteToggle: () {
                  if (inChinaMode) return;
                  widget.storage.toggleFavorite(species.cn);
                  setState(() {});
                },
                showFavorite: !inChinaMode,
                showDelete: !inChinaMode,
                showDownload: true,
                onDownload: () => _downloadOneFromServer(species),
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
        const SliverToBoxAdapter(
          child: SizedBox(height: 96),
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

  (double, double, int)? _parseCoordinates(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'[,，\s]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 2) return null;
    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    final dist = parts.length >= 3 ? int.tryParse(parts[2]) ?? 25 : 25;
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return (lat, lng, dist);
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
