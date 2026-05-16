import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../models/species.dart';
import '../services/download_task_service.dart';
import '../services/ebird_service.dart';
import '../services/order_taxonomy.dart';
import '../services/pack_downloader.dart';
import '../services/pack_manager.dart';
import '../services/server_media_service.dart';
import '../services/storage.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/species_tile.dart';
import 'bird_preview_screen.dart';

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
  final _chinaScrollController = ScrollController();
  List<EbirdLocationPreset> _locationResults = EBirdService.presets;
  final Map<String, GlobalKey> _orderHeaderKeys = {};

  // Pack preview mode
  final _packPageController = PageController();
  int _packPageIndex = 0;
  bool _showSearchBar = false;

  @override
  void initState() {
    super.initState();
    _loadSpecies();
  }

  @override
  void dispose() {
    _locationController.dispose();
    _searchController.dispose();
    _chinaScrollController.dispose();
    _packPageController.dispose();
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

    list.sort((a, b) {
      final orderA = BirdOrderTaxonomy.info(a.order);
      final orderB = BirdOrderTaxonomy.info(b.order);
      final byOrder = orderA.sortWeight.compareTo(orderB.sortWeight);
      if (byOrder != 0) return byOrder;
      final aName = a.cn.isNotEmpty ? a.cn : a.sci;
      final bName = b.cn.isNotEmpty ? b.cn : b.sci;
      return aName.compareTo(bName);
    });
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
    return _ordersFor(_displayedSpecies);
  }

  List<String> _ordersFor(List<Species> list) {
    final orders = list
        .map((species) => species.order)
        .where((order) => order.trim().isNotEmpty)
        .toSet()
        .toList();
    return BirdOrderTaxonomy.sortOrders(orders);
  }

  String _orderLabel(String order) => BirdOrderTaxonomy.label(order);

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

  void _jumpToOrder(List<Species> filtered, String order) {
    if (_source == 'active') {
      final index = filtered.indexWhere((species) => species.order == order);
      if (index >= 0) {
        _packPageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }

    final key = _orderHeaderKeys[order];
    final context = key?.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    }
  }

  Future<void> _openSpeciesPreview(List<Species> list, int index) async {
    if (list.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BirdPreviewScreen.list(
          speciesList: list,
          initialIndex: index,
          packManager: widget.packManager,
          storage: widget.storage,
          onDownload: _downloadOneFromServer,
        ),
      ),
    );
    if (mounted) {
      await _loadSpecies();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredSpecies;

    if (_source == 'china') {
      return _buildChinaListView(filtered);
    }
    return _buildPackPreviewView(filtered);
  }

  // ─── Pack preview PageView ────────────────────────────────────────────────

  Widget _buildPackPreviewView(List<Species> filtered) {
    final railOrders = _ordersFor(filtered);
    return Column(
      children: [
        _buildPreviewHeader(filtered),
        if (_showSearchBar)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '搜索中英文名、学名…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                          _packPageController.jumpToPage(0);
                          setState(() => _packPageIndex = 0);
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                isDense: true,
              ),
              onChanged: (value) {
                setState(() => _search = value);
                _packPageController.jumpToPage(0);
                setState(() => _packPageIndex = 0);
              },
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                            _search.isNotEmpty ? '没有匹配的鸟种' : '当前数据包暂无鸟种',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        )
                      : PageView.builder(
                          scrollDirection: Axis.vertical,
                          controller: _packPageController,
                          onPageChanged: (i) =>
                              setState(() => _packPageIndex = i),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) => _BirdInlinePage(
                            key: ValueKey(filtered[i].sci),
                            species: filtered[i],
                            packManager: widget.packManager,
                            storage: widget.storage,
                            onDeleted: () async {
                              await _deleteSpecies(filtered[i]);
                            },
                            onDownload: () =>
                                _downloadOneFromServer(filtered[i]),
                          ),
                        ),
              if (railOrders.length > 1)
                _OrderIndexRail(
                  orders: railOrders,
                  currentOrder: filtered.isNotEmpty &&
                          _packPageIndex >= 0 &&
                          _packPageIndex < filtered.length
                      ? filtered[_packPageIndex].order
                      : null,
                  onOrderSelected: (order) => _jumpToOrder(filtered, order),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewHeader(List<Species> filtered) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          // Source chips
          _sourceChipSmall('名录', 'china'),
          const SizedBox(width: 6),
          _sourceChipSmall('数据包', 'active'),
          const Spacer(),
          // Filter/sort
          if (_availableOrders.isNotEmpty)
            PopupMenuButton<String>(
              icon: Icon(
                Icons.sort,
                size: 20,
                color: _orderFilter != 'all'
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              tooltip: '按目筛选',
              initialValue: _orderFilter,
              onSelected: (value) {
                setState(() => _orderFilter = value);
                _packPageController.jumpToPage(0);
                setState(() => _packPageIndex = 0);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'all', child: Text('全部目')),
                ..._availableOrders.map(
                  (o) => PopupMenuItem(value: o, child: Text(_orderLabel(o))),
                ),
              ],
            ),
          // Search toggle
          IconButton(
            icon: Icon(
              _showSearchBar ? Icons.search_off : Icons.search,
              size: 20,
              color: _search.isNotEmpty
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: '搜索',
            onPressed: () => setState(() => _showSearchBar = !_showSearchBar),
          ),
          // Counter
          if (filtered.isNotEmpty)
            Text(
              '${_packPageIndex + 1} / ${filtered.length}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _sourceChipSmall(String label, String value) {
    final selected = _source == value;
    return GestureDetector(
      onTap: () => setState(() => _source = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF2d5016)
              : Colors.grey.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : Colors.grey[700],
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // ─── China list view (unchanged) ─────────────────────────────────────────

  Widget _buildChinaListView(List<Species> filtered) {
    final railOrders = _ordersFor(filtered);
    final rows = <({String? order, Species? species, int index})>[];
    var previousOrder = '';
    for (var i = 0; i < filtered.length; i++) {
      final species = filtered[i];
      if (species.order.isNotEmpty && species.order != previousOrder) {
        previousOrder = species.order;
        rows.add((order: species.order, species: null, index: i));
      }
      rows.add((order: null, species: species, index: i));
    }

    return Stack(
      children: [
        CustomScrollView(
          controller: _chinaScrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
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
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: '搜索鸟种名录、中英文名或学名...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
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
                          '鸟种名录 ${filtered.length} 种',
                          style:
                              TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                        const Spacer(),
                        Text(
                          '已选 ${_selectedSci.length} 种',
                          style:
                              TextStyle(fontSize: 13, color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
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
                    _search.isNotEmpty ? '没有匹配的鸟种' : '鸟种名录加载为空',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final order = row.order;
                  if (order != null) {
                    final key = _orderHeaderKeys.putIfAbsent(
                      order,
                      GlobalKey.new,
                    );
                    return Container(
                      key: key,
                      padding: const EdgeInsets.fromLTRB(18, 14, 54, 4),
                      child: Text(
                        _orderLabel(order),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2d5016),
                        ),
                      ),
                    );
                  }
                  final species = row.species!;
                  return SpeciesTile(
                    species: species,
                    onTap: () => _openSpeciesPreview(filtered, row.index),
                    isFavorite: false,
                    onFavoriteToggle: () {},
                    showFavorite: false,
                    showDelete: false,
                    showDownload: true,
                    onDownload: () => _downloadOneFromServer(species),
                    selected: _selectedSci.contains(species.sci),
                    onSelectedChanged: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedSci.add(species.sci);
                        } else {
                          _selectedSci.remove(species.sci);
                        }
                      });
                    },
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
        if (railOrders.length > 1)
          _OrderIndexRail(
            orders: railOrders,
            currentOrder: null,
            onOrderSelected: (order) => _jumpToOrder(filtered, order),
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

class _OrderIndexRail extends StatelessWidget {
  final List<String> orders;
  final String? currentOrder;
  final ValueChanged<String> onOrderSelected;

  const _OrderIndexRail({
    required this.orders,
    required this.currentOrder,
    required this.onOrderSelected,
  });

  void _selectByOffset(BuildContext context, Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || orders.isEmpty) return;
    final local = box.globalToLocal(globalPosition);
    final itemHeight = box.size.height / orders.length;
    final index = (local.dy / itemHeight).floor().clamp(0, orders.length - 1);
    onOrderSelected(orders[index]);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 4,
      top: 72,
      bottom: 72,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (details) =>
                _selectByOffset(context, details.globalPosition),
            onTapDown: (details) =>
                _selectByOffset(context, details.globalPosition),
            child: Container(
              width: 34,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: orders.map((order) {
                  final selected = order == currentOrder;
                  return Tooltip(
                    message: BirdOrderTaxonomy.label(order),
                    child: Container(
                      width: 24,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF2d5016)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text(
                        BirdOrderTaxonomy.shortLabel(order),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color:
                              selected ? Colors.white : const Color(0xFF2d5016),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Inline bird preview page ───────────────────────────────────────────────

class _BirdInlinePage extends StatefulWidget {
  final Species species;
  final PackManager packManager;
  final StorageService storage;
  final VoidCallback? onDeleted;
  final VoidCallback? onDownload;

  const _BirdInlinePage({
    super.key,
    required this.species,
    required this.packManager,
    required this.storage,
    this.onDeleted,
    this.onDownload,
  });

  @override
  State<_BirdInlinePage> createState() => _BirdInlinePageState();
}

class _BirdInlinePageState extends State<_BirdInlinePage> {
  String? _localImagePath;
  String? _packDir;
  ServerSpeciesMedia? _serverMedia;
  final _photoController = PageController();
  int _photoIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _photoController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final packDir = await widget.packManager.getActivePackDir();
    if (packDir != null && mounted) {
      setState(() => _packDir = packDir);
      final img = widget.species.image;
      if (img != null && img.isNotEmpty) {
        final path = '$packDir/$img';
        if (await File(path).exists()) {
          if (mounted) setState(() => _localImagePath = path);
        }
      }
    }
    try {
      final media =
          await ServerMediaService().fetchSpeciesMedia(widget.species.sci);
      if (mounted) setState(() => _serverMedia = media);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final sp = widget.species;
    final isFav = widget.storage.isFavorite(sp.cn);

    final images = <({String path, bool isNetwork, String credit})>[];
    if (_localImagePath != null) {
      images.add((
        path: _localImagePath!,
        isNetwork: false,
        credit: sp.imageCredit,
      ));
    }
    for (final img in (_serverMedia?.images ?? [])) {
      images.add((
        path: img.url,
        isNetwork: true,
        credit: img.contributor.isNotEmpty ? img.contributor : img.source,
      ));
    }

    // Audio absolute paths (need packDir prefix)
    final pd = _packDir;
    final localAudioPaths = pd == null
        ? <String>[]
        : sp.audios
            .map((a) => '$pd/${a.file}')
            .where((p) => p.isNotEmpty)
            .toList();
    final localAudioLabels = sp.audios.map((a) => a.displayLabel).toList();

    final features = sp.identificationFeatures;

    return Container(
      color: const Color(0xFF0D1B0A),
      child: Column(
        children: [
          // Photo section
          Expanded(
            flex: 5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                images.isEmpty
                    ? Container(
                        color: const Color(0xFF1A2B17),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.image_not_supported_outlined,
                                  size: 56, color: Colors.white24),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: widget.onDownload,
                                icon: const Icon(Icons.download,
                                    color: Colors.white54),
                                label: const Text('从服务器补充',
                                    style: TextStyle(color: Colors.white54)),
                              ),
                            ],
                          ),
                        ),
                      )
                    : images.length == 1
                        ? _imageWidget(images.first)
                        : PageView.builder(
                            controller: _photoController,
                            itemCount: images.length,
                            onPageChanged: (i) =>
                                setState(() => _photoIndex = i),
                            itemBuilder: (_, i) => _imageWidget(images[i]),
                          ),
                // Dot indicator
                if (images.length > 1)
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(images.length, (i) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: _photoIndex == i ? 14 : 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: _photoIndex == i
                                ? Colors.greenAccent
                                : Colors.white38,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    ),
                  ),
                // Credit
                if (images.isNotEmpty &&
                    _photoIndex < images.length &&
                    images[_photoIndex].credit.isNotEmpty)
                  Positioned(
                    bottom: images.length > 1 ? 22 : 6,
                    left: 0,
                    right: 0,
                    child: Text(
                      '© ${images[_photoIndex].credit}',
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white38),
                    ),
                  ),
                // Favorite + open-full buttons
                Positioned(
                  top: 8,
                  right: 8,
                  child: Row(
                    children: [
                      _iconOverlay(
                        isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                        isFav ? Colors.amber : Colors.white70,
                        () {
                          widget.storage.toggleFavorite(sp.cn);
                          setState(() {});
                        },
                      ),
                      const SizedBox(width: 4),
                      _iconOverlay(
                        Icons.open_in_full,
                        Colors.white70,
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BirdPreviewScreen(
                              species: sp,
                              packManager: widget.packManager,
                              storage: widget.storage,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Info section
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sp.cn.isNotEmpty ? sp.cn : sp.sci,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [if (sp.en.isNotEmpty) sp.en, sp.sci].join('  ·  '),
                    style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                        fontStyle: FontStyle.italic),
                  ),
                  if (sp.consText.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: sp.isGrade1
                            ? Colors.red.withValues(alpha: 0.25)
                            : Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sp.isGrade1
                              ? Colors.red[300]!
                              : Colors.orange[300]!,
                        ),
                      ),
                      child: Text(
                        sp.consText,
                        style: TextStyle(
                          fontSize: 11,
                          color: sp.isGrade1
                              ? Colors.red[200]
                              : Colors.orange[200],
                        ),
                      ),
                    ),
                  ],
                  if (localAudioPaths.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    AudioPlayerWidget(
                      audioPaths: localAudioPaths,
                      audioLabels: localAudioLabels,
                    ),
                  ],
                  if (features.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      features,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13, height: 1.5),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageWidget(({String path, bool isNetwork, String credit}) img) {
    return img.isNetwork
        ? Image.network(
            img.path,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_outlined,
                  color: Colors.white24, size: 40),
            ),
          )
        : Image.file(
            File(img.path),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_outlined,
                  color: Colors.white24, size: 40),
            ),
          );
  }

  Widget _iconOverlay(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}
