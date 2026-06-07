import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/species.dart';
import '../services/download_task_service.dart';
import '../services/avilist_service.dart';
import '../services/ecological_group.dart';
import '../services/order_taxonomy.dart';
import '../services/pinyin.dart';
import '../services/pack_downloader.dart';
import '../services/pack_manager.dart';
import '../services/storage.dart';
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
  final Set<String> _selectedSci = <String>{};
  final String _source = 'active';
  String _filter = 'all';
  String _orderFilter = 'all';
  String _groupFilter = 'all'; // 生态类群过滤：all / swimming / wading / ...
  String _search = '';
  bool _loading = true;
  final _searchController = TextEditingController();
  final _chinaScrollController = ScrollController();
  final Map<String, GlobalKey> _orderHeaderKeys = {};
  String? _chinaRailOrder;

  // Pack preview mode
  bool _showSearchBar = false;
  bool _showFavOnly = false;
  Map<String, int> _aviIndex = const {};
  String? _activePackDir; // 用于列表缩略图路径

  @override
  void initState() {
    super.initState();
    _chinaScrollController.addListener(_updateChinaRailOrder);
    _loadSpecies();
    AviListService().getSciIndexMap().then((idx) {
      if (mounted) setState(() => _aviIndex = idx);
    });
    widget.packManager.getActivePackDir().then((dir) {
      if (mounted) setState(() => _activePackDir = dir);
    });
  }

  @override
  void dispose() {
    _chinaScrollController.removeListener(_updateChinaRailOrder);
    _searchController.dispose();
    _chinaScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SpeciesListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
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
            description: (json['description'] as String? ?? '').trim(),
            descriptionSource:
                (json['description_source'] as String? ?? '').trim(),
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

  String _normalizeProtection(String value) {
    if (value.contains('一级')) return '1';
    if (value.contains('二级')) return '2';
    return value;
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

    switch (_filter) {
      case 'audio':
        list = list.where((species) => species.hasAudio).toList();
        break;
    }

    if (_orderFilter != 'all') {
      list = list.where((species) => species.order == _orderFilter).toList();
    }

    if (_groupFilter != 'all') {
      list = list.where((species) {
        final g = EcologicalGroups.resolve(
            order: species.order, family: species.family);
        return g?.code == _groupFilter;
      }).toList();
    }

    if (_showFavOnly) {
      list = list
          .where((species) => widget.storage.isFavorite(species.cn))
          .toList();
    }

    if (_search.isNotEmpty) {
      final query = _search.toLowerCase();
      final isPinyinQuery =
          query.length >= 2 && RegExp(r'^[a-z]+$').hasMatch(query);
      list = list
          .where(
            (species) =>
                species.cn.contains(_search) ||
                species.en.toLowerCase().contains(query) ||
                species.sci.toLowerCase().contains(query) ||
                species.habitat.toLowerCase().contains(query) ||
                species.enAlt.any((alt) => alt.toLowerCase().contains(query)) ||
                (isPinyinQuery && Pinyin.initials(species.cn).contains(query)),
          )
          .toList();
    }

    list.sort((a, b) {
      final orderA = BirdOrderTaxonomy.info(a.order);
      final orderB = BirdOrderTaxonomy.info(b.order);
      final byOrder = orderA.sortWeight.compareTo(orderB.sortWeight);
      if (byOrder != 0) return byOrder;
      // Within same order: sort by AviList index if available
      final idxA = _aviIndex[a.sci.trim().toLowerCase()] ?? 999999;
      final idxB = _aviIndex[b.sci.trim().toLowerCase()] ?? 999999;
      if (idxA != idxB) return idxA.compareTo(idxB);
      final aName = a.cn.isNotEmpty ? a.cn : a.sci;
      final bName = b.cn.isNotEmpty ? b.cn : b.sci;
      return aName.compareTo(bName);
    });
    return list;
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

  void _updateChinaRailOrder() {
    if (_source != 'china' || _orderHeaderKeys.isEmpty) return;
    String? bestOrder;
    double bestTop = double.negativeInfinity;
    for (final entry in _orderHeaderKeys.entries) {
      final context = entry.value.currentContext;
      if (context == null) continue;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top <= 180 && top > bestTop) {
        bestTop = top;
        bestOrder = entry.key;
      }
    }
    if (bestOrder != null && bestOrder != _chinaRailOrder && mounted) {
      setState(() => _chinaRailOrder = bestOrder);
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
    return Column(
      children: [
        _buildMergedBar(filtered),
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
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                        _search.isNotEmpty ? '没有匹配的鸟种' : '当前数据包暂无鸟种',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      controller: _chinaScrollController,
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        thickness: 0.5,
                        indent: 80,
                        color: Colors.grey[200],
                      ),
                      itemBuilder: (ctx, i) => _speciesListRow(filtered[i]),
                    ),
        ),
      ],
    );
  }

  /// Merlin 风格紧凑行：缩略图 + 中文名 + 英文 + 学名，点整行进简介。
  Widget _speciesListRow(Species sp) {
    final isFav = widget.storage.isFavorite(sp.cn);
    final img = sp.image;
    final thumbPath = (_activePackDir != null && img != null && img.isNotEmpty)
        ? '$_activePackDir/$img'
        : null;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BirdPreviewScreen(
            species: sp,
            packManager: widget.packManager,
            storage: widget.storage,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: thumbPath != null
                    ? Image.file(
                        File(thumbPath),
                        fit: BoxFit.cover,
                        cacheWidth: 160,
                        errorBuilder: (_, __, ___) => _thumbPlaceholder(),
                      )
                    : _thumbPlaceholder(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sp.cn.isNotEmpty ? sp.cn : sp.en,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sp.en.isNotEmpty)
                    Text(
                      sp.en,
                      style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    sp.sci,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (sp.hasAudio)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.graphic_eq,
                    size: 16, color: Colors.green[400]),
              ),
            if (isFav)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.star_rounded, size: 16, color: Colors.amber),
              ),
            Icon(Icons.chevron_right, size: 20, color: Colors.grey[350]),
          ],
        ),
      ),
    );
  }

  Widget _thumbPlaceholder() => Container(
        color: const Color(0xFFEAF1E6),
        child: Icon(Icons.photo_outlined,
            size: 22, color: Colors.green[200]),
      );

  /// 合并顶栏：第一行 数量 + 搜索/排序/收藏 图标；第二行 类群 chips。
  Widget _buildMergedBar(List<Species> filtered) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
            child: Row(
              children: [
                Text(
                  '${filtered.length} 种',
                  style:
                      const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    _showSearchBar ? Icons.search_off : Icons.search,
                    size: 20,
                    color: _search.isNotEmpty
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  tooltip: '搜索',
                  onPressed: () =>
                      setState(() => _showSearchBar = !_showSearchBar),
                ),
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
                    onSelected: (value) => setState(() => _orderFilter = value),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'all', child: Text('全部目')),
                      ..._availableOrders.map(
                        (o) =>
                            PopupMenuItem(value: o, child: Text(_orderLabel(o))),
                      ),
                    ],
                  ),
                IconButton(
                  icon: Icon(
                    _showFavOnly
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 20,
                    color: _showFavOnly ? Colors.amber : null,
                  ),
                  tooltip: _showFavOnly ? '显示全部' : '只看收藏',
                  onPressed: () =>
                      setState(() => _showFavOnly = !_showFavOnly),
                ),
              ],
            ),
          ),
          _buildGroupBar(),
        ],
      ),
    );
  }

  Widget _buildGroupBar() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: EcologicalGroups.all.length + 1,
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return _groupChip(
              code: 'all',
              label: '全部',
              selected: _groupFilter == 'all',
            );
          }
          final g = EcologicalGroups.all[i - 1];
          return _groupChip(
            code: g.code,
            label: g.label,
            selected: _groupFilter == g.code,
          );
        },
      ),
    );
  }

  Widget _groupChip({
    required String code,
    required String label,
    required bool selected,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_groupIcon(code), size: 15),
            const SizedBox(width: 4),
            Text(label,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
        selected: selected,
        onSelected: (_) {
          setState(() => _groupFilter = code);
          if (_chinaScrollController.hasClients) {
            _chinaScrollController.jumpTo(0);
          }
        },
        selectedColor: const Color(0xFF2d5016),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.black87,
        ),
      ),
    );
  }

  IconData _groupIcon(String code) {
    switch (code) {
      case 'swimming':
        return Icons.water;
      case 'wading':
        return Icons.waves_outlined;
      case 'ground':
        return Icons.grass_outlined;
      case 'raptor':
        return Icons.visibility_outlined;
      case 'climbing':
        return Icons.park_outlined;
      case 'singing':
        return Icons.music_note_outlined;
      case 'all':
      default:
        return Icons.eco_outlined;
    }
  }

  // ─── China list view (unchanged) ─────────────────────────────────────────

  Widget _buildChinaListView(List<Species> filtered) {
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

    return Column(
      children: [
        _buildGroupBar(),
        Expanded(
          child: Stack(
            children: [
              CustomScrollView(
                controller: _chinaScrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: '搜索当前数据包、中英文名或学名...',
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              isDense: true,
                            ),
                            onChanged: (value) =>
                                setState(() => _search = value),
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
                                '当前数据包 ${filtered.length} 种',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey[600]),
                              ),
                              const Spacer(),
                              Text(
                                '已选 ${_selectedSci.length} 种',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey[700]),
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
                                onPressed: _selectedSci.isEmpty
                                    ? null
                                    : _downloadSelected,
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
            ],
          ),
        ),
      ],
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
