import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/bird_species.dart';
import '../models/custom_field.dart';
import '../models/survey_session.dart';
import '../providers/survey_provider.dart';
import '../services/speech_service.dart';
import '../services/tide_service.dart';
import '../widgets/species_tile.dart';
import '../widgets/voice_note_field.dart';

class SurveyScreen extends StatefulWidget {
  const SurveyScreen({super.key});

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();

  // Voice search state (reuses the app-wide singleton)
  bool _listening = false;

  SpeechService get _svc => SpeechService.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    // Ensure singleton is ready; no-op if already initialized.
    _svc.init().then((_) {
      if (mounted) setState(() {});
    });
    _svc.speech.statusListener = (s) {
      if (s == 'done' || s == 'notListening') {
        if (mounted) setState(() => _listening = false);
      }
    };
  }

  Future<void> _toggleListening(SurveyProvider prov) async {
    if (_listening) {
      await _svc.speech.stop();
      setState(() => _listening = false);
      return;
    }
    if (!_svc.available) return;

    // Switch to "附近" tab when using voice search
    _tabController.animateTo(0);

    setState(() => _listening = true);
    await _svc.speech.listen(
      localeId: 'zh_CN',
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      onResult: (result) {
        final text = result.recognizedWords;
        if (text.isNotEmpty) {
          _searchController.text = text;
          prov.setSearchQuery(text);
        }
      },
    );
  }

  /// Returns null = cancelled, non-null String = notes (may be empty).
  /// result carries a 'startNew' flag via a wrapper.
  Future<_EndResult?> _showEndNotesDialog(SurveyProvider prov) async {
    final ctrl = TextEditingController();
    return showDialog<_EndResult>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('结束调查'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '共记录 ${prov.recordedSpecies.length} 种 · '
                  '${prov.currentSession?.totalCount ?? 0} 只',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                VoiceNoteField(
                  controller: ctrl,
                  hintText: '调查总体备注（可选）',
                  maxLines: 3,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('继续调查'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, _EndResult(ctrl.text)),
                child: const Text('仅结束'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                ),
                onPressed:
                    () => Navigator.pop(
                      context,
                      _EndResult(ctrl.text, startNew: true),
                    ),
                child: const Text(
                  '结束并开始新调查',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );
  }

  Future<void> _showCountEditDialog(
    SurveyProvider prov,
    BirdSpecies species,
  ) async {
    final current = prov.getCount(species);
    final result = await _showCountCalculatorDialog(
      title: '输入数量 · ${species.zh}',
      current: current,
    );
    if (result != null && result >= 0) {
      prov.setCount(species, result);
      if (!mounted) return;
      _showUndoSnackBar(
        message: '${species.zh} 数量已改为 $result',
        onUndo: () => prov.setCount(species, current),
      );
    }
  }

  Future<void> _showFieldOptionCountDialog(
    SurveyProvider prov,
    BirdSpecies species,
    CustomField field,
    String option,
  ) async {
    final current =
        prov.getSpeciesFieldCounts(species.ebird, field.id)[option] ?? 0;
    final result = await _showCountCalculatorDialog(
      title: '${field.name}：$option · ${species.zh}',
      current: current,
    );
    if (result != null && result >= 0) {
      prov.setSpeciesFieldOptionCount(species, field.id, option, result);
      if (!mounted) return;
      _showUndoSnackBar(
        message: '${field.name}.$option 已改为 $result',
        onUndo:
            () => prov.setSpeciesFieldOptionCount(
              species,
              field.id,
              option,
              current,
            ),
      );
    }
  }

  Future<void> _showNestedFieldOptionCountDialog(
    SurveyProvider prov,
    BirdSpecies species,
    CustomField field,
    String parent,
    String child,
  ) async {
    final current =
        prov.getNestedSpeciesFieldCounts(
          species.ebird,
          field.id,
        )[parent]?[child] ??
        0;
    final result = await _showCountCalculatorDialog(
      title: '${field.name}：$parent / $child · ${species.zh}',
      current: current,
    );
    if (result != null && result >= 0) {
      prov.setNestedSpeciesFieldOptionCount(
        species,
        field.id,
        parent,
        child,
        result,
      );
      if (!mounted) return;
      _showUndoSnackBar(
        message: '$parent.$child 已改为 $result',
        onUndo:
            () => prov.setNestedSpeciesFieldOptionCount(
              species,
              field.id,
              parent,
              child,
              current,
            ),
      );
    }
  }

  Future<int?> _showCountCalculatorDialog({
    required String title,
    required int current,
  }) async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _CountCalculatorDialog(title: title, current: current),
    );
    return result;
  }

  void _showUndoSnackBar({
    required String message,
    required VoidCallback onUndo,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: '撤回', onPressed: onUndo),
      ),
    );
  }

  Future<void> _showNoteDialog(
    SurveyProvider prov,
    String ebirdCode,
    String zhName,
  ) async {
    final noteCtrl = TextEditingController(
      text: prov.getSpeciesNote(ebirdCode),
    );
    // Snapshot current field values into local state for the dialog
    final fieldDefs = prov.speciesFieldDefs;
    final fieldValues = <String, String>{
      for (final f in fieldDefs)
        f.id: prov.getSpeciesFieldValue(ebirdCode, f.id),
    };

    await showDialog<void>(
      context: context,
      builder:
          (_) => _SpeciesDetailDialog(
            zhName: zhName,
            noteCtrl: noteCtrl,
            fieldDefs: fieldDefs,
            fieldValues: fieldValues,
            onSave: () {
              prov.setSpeciesNote(ebirdCode, noteCtrl.text.trim());
              for (final f in fieldDefs) {
                prov.setSpeciesFieldValue(
                  ebirdCode,
                  f.id,
                  fieldValues[f.id] ?? '',
                );
              }
            },
            onClearNote: () => prov.setSpeciesNote(ebirdCode, ''),
            hasExistingNote: prov.getSpeciesNote(ebirdCode).isNotEmpty,
          ),
    );
  }

  Future<bool> _onWillPop(SurveyProvider prov) async {
    if (prov.isEditingHistory) {
      if (prov.hasUnsavedHistoryEdits) {
        final discard = await _confirmDiscardHistoryEdits();
        if (discard != true) return false;
      }
      await prov.cancelEditedSurvey();
      return true;
    }
    final res = await _showEndNotesDialog(prov);
    if (res == null) return false;
    await prov.endSurvey(notes: res.notes);
    if (!mounted) return true;
    if (res.startNew) {
      Navigator.of(context).pushReplacementNamed('/survey_start');
      return false;
    }
    // Show snackbar on home screen after pop
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('调查已保存'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: '开始新调查',
            onPressed: () => Navigator.of(context).pushNamed('/survey_start'),
          ),
        ),
      );
    });
    return true;
  }

  Future<bool?> _confirmDiscardHistoryEdits() => showDialog<bool>(
    context: context,
    builder:
        (_) => AlertDialog(
          title: const Text('放弃本次修改？'),
          content: const Text('本次编辑还没有保存，放弃后会恢复到原来的历史记录。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('放弃修改', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
  );

  Future<void> _showEditLogSheet(SurveyProvider prov) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        final logs = prov.editLog;
        return SafeArea(
          child:
              logs.isEmpty
                  ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('本次编辑还没有修改记录')),
                  )
                  : ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, i) {
                      return ListTile(
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(logs[i]),
                        trailing: TextButton(
                          onPressed: () {
                            prov.undoToEditIndex(i);
                            Navigator.pop(context);
                          },
                          child: const Text('撤回到此处'),
                        ),
                      );
                    },
                  ),
        );
      },
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    if (_listening) _svc.speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SurveyProvider>();
    final session = prov.currentSession;
    final df = DateFormat('HH:mm');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final shouldPop = await _onWillPop(prov);
          if (shouldPop && context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('鸟类调查', style: TextStyle(fontSize: 16)),
              if (session != null)
                Text(
                  '${df.format(session.startTime)}开始 · '
                  '${prov.recordedSpecies.length}种 / ${session.totalCount}只',
                  style: const TextStyle(fontSize: 11),
                ),
            ],
          ),
          actions: [
            if (prov.isEditingHistory) ...[
              IconButton(
                icon: const Icon(Icons.undo, color: Colors.white),
                tooltip: '撤回上一步',
                onPressed:
                    prov.editLog.isEmpty
                        ? null
                        : () {
                          final ok = prov.undoLastEdit();
                          if (ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已撤回上一步修改')),
                            );
                          }
                        },
              ),
              IconButton(
                icon: const Icon(Icons.history, color: Colors.white),
                tooltip: '修改记录',
                onPressed: () => _showEditLogSheet(prov),
              ),
              TextButton(
                onPressed: () async {
                  final discard =
                      prov.hasUnsavedHistoryEdits
                          ? await _confirmDiscardHistoryEdits()
                          : true;
                  if (discard == true && context.mounted) {
                    await prov.cancelEditedSurvey();
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                child: const Text('取消', style: TextStyle(color: Colors.white)),
              ),
              TextButton(
                onPressed: () async {
                  await prov.saveEditedSurvey();
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('历史记录修改已保存')));
                  }
                },
                child: const Text(
                  '保存修改',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ] else
              TextButton.icon(
                icon: const Icon(Icons.stop_circle, color: Colors.white),
                label: const Text('结束', style: TextStyle(color: Colors.white)),
                onPressed: () async {
                  final res = await _showEndNotesDialog(prov);
                  if (res != null && context.mounted) {
                    await prov.endSurvey(notes: res.notes);
                    if (!context.mounted) return;
                    if (res.startNew) {
                      Navigator.of(
                        context,
                      ).pushReplacementNamed('/survey_start');
                    } else {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('调查已保存'),
                          duration: const Duration(seconds: 4),
                          action: SnackBarAction(
                            label: '开始新调查',
                            onPressed:
                                () => Navigator.of(
                                  context,
                                ).pushNamed('/survey_start'),
                          ),
                        ),
                      );
                    }
                  }
                },
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(90),
            child: Column(
              children: [
                _InfoBar(prov: prov),
                TabBar(
                  controller: _tabController,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: Colors.white,
                  isScrollable: true,
                  tabAlignment: TabAlignment.center,
                  tabs: [
                    Tab(
                      text:
                          (prov.loadingNearby || prov.loadingProvince)
                              ? '附近…'
                              : prov.nearbyMode == NearbyMode.province
                              ? '全省(${prov.provinceSpecies.length})'
                              : '附近(${prov.nearbySpecies.length})',
                    ),
                    const Tab(text: '全部鸟种'),
                    Tab(text: '已记录(${prov.recordedSpecies.length})'),
                    Tab(text: '历史(${prov.history.length})'),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: Column(
          children: [
            if (prov.isTransect) _TransectMapPanel(prov: prov),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _NearbyTab(
                    prov: prov,
                    searchController: _searchController,
                    speechAvailable: _svc.available,
                    listening: _listening,
                    onMicTap: () => _toggleListening(prov),
                    onNote: (code, name) => _showNoteDialog(prov, code, name),
                    onCountEdit: (s) => _showCountEditDialog(prov, s),
                    onFieldOptionCountEdit:
                        (s, field, option) =>
                            _showFieldOptionCountDialog(prov, s, field, option),
                    onNestedFieldOptionCountEdit:
                        (s, field, parent, child) =>
                            _showNestedFieldOptionCountDialog(
                              prov,
                              s,
                              field,
                              parent,
                              child,
                            ),
                  ),
                  _AllSpeciesTab(
                    prov: prov,
                    searchController: _searchController,
                    speechAvailable: _svc.available,
                    listening: _listening,
                    onMicTap: () => _toggleListening(prov),
                    onNote: (code, name) => _showNoteDialog(prov, code, name),
                    onCountEdit: (s) => _showCountEditDialog(prov, s),
                    onFieldOptionCountEdit:
                        (s, field, option) =>
                            _showFieldOptionCountDialog(prov, s, field, option),
                    onNestedFieldOptionCountEdit:
                        (s, field, parent, child) =>
                            _showNestedFieldOptionCountDialog(
                              prov,
                              s,
                              field,
                              parent,
                              child,
                            ),
                  ),
                  _RecordedTab(
                    prov: prov,
                    onNote: (code, name) => _showNoteDialog(prov, code, name),
                    onCountEdit: (s) => _showCountEditDialog(prov, s),
                    onFieldOptionCountEdit:
                        (s, field, option) =>
                            _showFieldOptionCountDialog(prov, s, field, option),
                    onNestedFieldOptionCountEdit:
                        (s, field, parent, child) =>
                            _showNestedFieldOptionCountDialog(
                              prov,
                              s,
                              field,
                              parent,
                              child,
                            ),
                  ),
                  _HistoryTab(
                    prov: prov,
                    onCountEdit: (s) => _showCountEditDialog(prov, s),
                    onFieldOptionCountEdit:
                        (s, field, option) =>
                            _showFieldOptionCountDialog(prov, s, field, option),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransectMapPanel extends StatefulWidget {
  final SurveyProvider prov;

  const _TransectMapPanel({required this.prov});

  @override
  State<_TransectMapPanel> createState() => _TransectMapPanelState();
}

class _TransectMapPanelState extends State<_TransectMapPanel> {
  final _mapController = MapController();

  LatLng get _center {
    final pos = widget.prov.position;
    final session = widget.prov.currentSession;
    return LatLng(
      pos?.latitude ?? session?.latitude ?? 0,
      pos?.longitude ?? session?.longitude ?? 0,
    );
  }

  void _moveToCurrent() {
    _mapController.move(_center, 16);
    widget.prov.retryGps();
  }

  @override
  Widget build(BuildContext context) {
    final prov = widget.prov;
    final center = _center;
    final track = prov.transectTrack;
    final hasActivePoint = prov.activeTransectPointId.isNotEmpty;
    final observations =
        prov.observationEvents.where((e) => e.type == 'species_count').toList();
    final trackPoints =
        track.map((p) => LatLng(p.latitude, p.longitude)).toList();

    return SizedBox(
      height: 190,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: center, initialZoom: 15),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.birdsurvey.app',
              ),
              if (trackPoints.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: trackPoints,
                      color: Colors.teal,
                      strokeWidth: 4,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: center,
                    width: 34,
                    height: 34,
                    child: const Icon(
                      Icons.my_location,
                      color: Colors.blue,
                      size: 26,
                    ),
                  ),
                  ...track.map(
                    (p) => Marker(
                      point: LatLng(p.latitude, p.longitude),
                      width: 26,
                      height: 26,
                      child: Icon(
                        p.endedAt == null
                            ? Icons.fiber_manual_record
                            : Icons.check_circle,
                        color: p.endedAt == null ? Colors.teal : Colors.grey,
                        size: 16,
                      ),
                    ),
                  ),
                  ...observations
                      .take(80)
                      .map(
                        (e) => Marker(
                          point: LatLng(e.latitude, e.longitude),
                          width: 28,
                          height: 28,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.orange,
                            size: 22,
                          ),
                        ),
                      ),
                ],
              ),
            ],
          ),
          Positioned(
            right: 10,
            top: 10,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'transect_locate',
                  onPressed: _moveToCurrent,
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'transect_track',
                  backgroundColor: Colors.green[700],
                  onPressed: () => prov.addTransectTrackPoint(),
                  child: const Icon(Icons.add_location_alt),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'transect_end_point',
                  backgroundColor:
                      hasActivePoint ? Colors.orange[700] : Colors.grey,
                  onPressed:
                      hasActivePoint
                          ? () => prov.endCurrentTransectPoint()
                          : null,
                  child: const Icon(Icons.stop_circle),
                ),
              ],
            ),
          ),
          Positioned(
            left: 10,
            bottom: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Text(
                  '样线  轨迹${track.length}点  记录${observations.length}次',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info Bar ─────────────────────────────────────────────────────────────────

class _InfoBar extends StatelessWidget {
  final SurveyProvider prov;
  const _InfoBar({required this.prov});

  @override
  Widget build(BuildContext context) {
    final pos = prov.position;
    final tide = prov.tideResult;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Colors.green[700],
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Colors.white70, size: 14),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              pos != null
                  ? '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}'
                  : '获取位置中...',
              style: const TextStyle(color: Colors.white, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.waves, color: Colors.white70, size: 14),
          const SizedBox(width: 3),
          Text(
            tide != null
                ? '${tide.height.toStringAsFixed(2)} ${tide.unit}'
                    '${tide.label != null ? ' · ${tide.label}' : ''}'
                : (prov.tideSource == TideSource.local
                    ? '计算中...'
                    : _tideKeyStatus(prov)),
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
          const SizedBox(width: 6),
          StreamBuilder(
            stream: Stream.periodic(const Duration(seconds: 1)),
            builder:
                (_, __) => Text(
                  DateFormat('HH:mm:ss').format(DateTime.now()),
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
          ),
        ],
      ),
    );
  }

  String _tideKeyStatus(SurveyProvider prov) {
    if (prov.tideSource == TideSource.chaoxi365 && prov.chaoxi365Key.isEmpty) {
      return '潮汐(未配置Key)';
    }
    if (prov.tideSource == TideSource.stormglass &&
        prov.stormglassKey.isEmpty) {
      return '潮汐(未配置Key)';
    }
    if (prov.tideSource == TideSource.worldtides &&
        prov.worldtidesKey.isEmpty) {
      return '潮汐(未配置Key)';
    }
    return '获取潮汐...';
  }
}

// ── Tab: Nearby ───────────────────────────────────────────────────────────────

class _NearbyTab extends StatefulWidget {
  final SurveyProvider prov;
  final TextEditingController searchController;
  final bool speechAvailable;
  final bool listening;
  final VoidCallback onMicTap;
  final void Function(String code, String name)? onNote;
  final void Function(BirdSpecies)? onCountEdit;
  final void Function(BirdSpecies species, CustomField field, String option)?
  onFieldOptionCountEdit;
  final void Function(
    BirdSpecies species,
    CustomField field,
    String parent,
    String child,
  )?
  onNestedFieldOptionCountEdit;
  const _NearbyTab({
    required this.prov,
    required this.searchController,
    required this.speechAvailable,
    required this.listening,
    required this.onMicTap,
    this.onNote,
    this.onCountEdit,
    this.onFieldOptionCountEdit,
    this.onNestedFieldOptionCountEdit,
  });
  @override
  State<_NearbyTab> createState() => _NearbyTabState();
}

class _NearbyTabState extends State<_NearbyTab> {
  @override
  Widget build(BuildContext context) {
    final prov = widget.prov;
    final isProvince = prov.nearbyMode == NearbyMode.province;
    final isLoading = isProvince ? prov.loadingProvince : prov.loadingNearby;

    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在从eBird获取附近鸟种...'),
          ],
        ),
      );
    }
    if (prov.ebirdApiKey.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.key, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            const Text('请先在设置中填写eBird API Key'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/settings'),
              child: const Text('前往设置'),
            ),
          ],
        ),
      );
    }

    final nearby = prov.filteredNearbySpecies;
    final province = prov.filteredProvinceSpecies;
    final hasQuery = prov.searchQuery.isNotEmpty;
    final displayList = isProvince ? province : nearby;
    final allSpecies = hasQuery ? prov.filteredAllSpecies : <BirdSpecies>[];
    // fallback list = all-species results not already in displayList
    final displayCodes = displayList.map((s) => s.ebird).toSet();
    final fallbackList =
        allSpecies.where((s) => !displayCodes.contains(s.ebird)).toList();
    final modeLabel =
        prov.nearbyMode == NearbyMode.recent
            ? '附近30km · 30天'
            : prov.nearbyMode == NearbyMode.localHistory
            ? '百公里 · 30天'
            : prov.provinceRegionName.isNotEmpty
            ? prov.provinceRegionName
            : '全省历史';

    Widget buildTile(BirdSpecies s, {int? freq}) => SpeciesTile(
      species: s,
      count: prov.getCount(s),
      ebirdFreq: freq ?? s.ebirdFrequency,
      note: prov.getSpeciesNote(s.ebird),
      speciesAttrs: prov.getSpeciesFieldAttrs(s.ebird),
      quickFields: _tileQuickFields(
        prov,
        s,
        onCountEdit: widget.onFieldOptionCountEdit,
        onNestedCountEdit: widget.onNestedFieldOptionCountEdit,
      ),
      onIncrement: () => prov.incrementCount(s),
      onDecrement: () => prov.decrementCount(s),
      onCountEdit:
          widget.onCountEdit != null ? () => widget.onCountEdit!(s) : null,
      onNote:
          widget.onNote != null ? () => widget.onNote!(s.ebird, s.zh) : null,
    );

    return Column(
      children: [
        // ── Search bar ──
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.searchController,
                  decoration: InputDecoration(
                    hintText: '搜索鸟种...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon:
                        widget.searchController.text.isNotEmpty
                            ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                widget.searchController.clear();
                                prov.setSearchQuery('');
                              },
                            )
                            : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    isDense: true,
                  ),
                  onChanged: prov.setSearchQuery,
                ),
              ),
              const SizedBox(width: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: widget.listening ? Colors.red[50] : Colors.green[50],
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    widget.listening ? Icons.mic : Icons.mic_none,
                    color: widget.listening ? Colors.red : Colors.green[700],
                  ),
                  tooltip: widget.listening ? '停止录音' : '语音搜索鸟种',
                  onPressed: widget.speechAvailable ? widget.onMicTap : null,
                ),
              ),
            ],
          ),
        ),
        if (widget.listening)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Colors.red[50],
            child: Row(
              children: [
                const Icon(Icons.mic, color: Colors.red, size: 14),
                const SizedBox(width: 6),
                const Text(
                  '正在聆听，请说鸟种名称...',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
                const Spacer(),
                TextButton(
                  onPressed: widget.onMicTap,
                  child: const Text(
                    '停止',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        // ── Mode selector ──
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
          child: Row(
            children: [
              for (final mode in NearbyMode.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => prov.setNearbyMode(mode),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            prov.nearbyMode == mode
                                ? Colors.green[700]
                                : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              prov.nearbyMode == mode
                                  ? Colors.green[700]!
                                  : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(
                        mode == NearbyMode.recent
                            ? '30天'
                            : mode == NearbyMode.localHistory
                            ? '百公里'
                            : '全省历史',
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              prov.nearbyMode == mode
                                  ? Colors.white
                                  : Colors.grey[700],
                          fontWeight:
                              prov.nearbyMode == mode
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // ── Species list ──
        Expanded(
          child: ListView(
            children: [
              // Mode results header
              if (displayList.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: Text(
                    '$modeLabel  ${displayList.length}种',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              if (!hasQuery && displayList.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    isProvince
                        ? '${prov.provinceRegionName.isNotEmpty ? prov.provinceRegionName : "全省"}暂无eBird记录'
                        : prov.nearbyMode == NearbyMode.localHistory
                        ? '100km内暂无eBird记录'
                        : '附近30km内暂无eBird记录',
                    style: const TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ),
              ...displayList.map((s) => buildTile(s)),

              // Fallback: all-species results not in mode list
              if (hasQuery && fallbackList.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Text(
                    '全部鸟种  ${fallbackList.length}种',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ),
                ...fallbackList.map((s) => buildTile(s, freq: 0)),
              ],

              // Nothing found anywhere → custom input
              if (hasQuery && displayList.isEmpty && fallbackList.isEmpty)
                _AddCustomSpeciesButton(prov: prov),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Tab: All Species ──────────────────────────────────────────────────────────

class _AllSpeciesTab extends StatelessWidget {
  final SurveyProvider prov;
  final TextEditingController searchController;
  final bool speechAvailable;
  final bool listening;
  final VoidCallback onMicTap;
  final void Function(String code, String name)? onNote;
  final void Function(BirdSpecies)? onCountEdit;
  final void Function(BirdSpecies species, CustomField field, String option)?
  onFieldOptionCountEdit;
  final void Function(
    BirdSpecies species,
    CustomField field,
    String parent,
    String child,
  )?
  onNestedFieldOptionCountEdit;

  const _AllSpeciesTab({
    required this.prov,
    required this.searchController,
    required this.speechAvailable,
    required this.listening,
    required this.onMicTap,
    this.onNote,
    this.onCountEdit,
    this.onFieldOptionCountEdit,
    this.onNestedFieldOptionCountEdit,
  });

  @override
  Widget build(BuildContext context) {
    final list = prov.filteredAllSpecies;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: '搜索中文名/英文名/学名...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon:
                        searchController.text.isNotEmpty
                            ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                searchController.clear();
                                prov.setSearchQuery('');
                              },
                            )
                            : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    isDense: true,
                  ),
                  onChanged: prov.setSearchQuery,
                ),
              ),
              const SizedBox(width: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: listening ? Colors.red[50] : Colors.green[50],
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    listening ? Icons.mic : Icons.mic_none,
                    color: listening ? Colors.red : Colors.green[700],
                  ),
                  tooltip: listening ? '停止录音' : '语音搜索鸟种',
                  onPressed: speechAvailable ? onMicTap : null,
                ),
              ),
            ],
          ),
        ),
        if (listening)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Colors.red[50],
            child: Row(
              children: [
                const Icon(Icons.mic, color: Colors.red, size: 14),
                const SizedBox(width: 6),
                const Text(
                  '正在聆听，请说鸟种名称...',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onMicTap,
                  child: const Text(
                    '停止',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length + 1, // +1 for "add custom" footer
            itemBuilder: (_, i) {
              if (i == list.length) {
                return _AddCustomSpeciesButton(prov: prov);
              }
              final s = list[i];
              final count = prov.getCount(s);
              return SpeciesTile(
                species: s,
                count: count,
                note: prov.getSpeciesNote(s.ebird),
                speciesAttrs: prov.getSpeciesFieldAttrs(s.ebird),
                quickFields: _tileQuickFields(
                  prov,
                  s,
                  onCountEdit: onFieldOptionCountEdit,
                  onNestedCountEdit: onNestedFieldOptionCountEdit,
                ),
                onIncrement: () => prov.incrementCount(s),
                onDecrement: () => prov.decrementCount(s),
                onCountEdit: onCountEdit != null ? () => onCountEdit!(s) : null,
                onNote: onNote != null ? () => onNote!(s.ebird, s.zh) : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Tab: Recorded ─────────────────────────────────────────────────────────────

class _RecordedTab extends StatefulWidget {
  final SurveyProvider prov;
  final void Function(String code, String name)? onNote;
  final void Function(BirdSpecies)? onCountEdit;
  final void Function(BirdSpecies species, CustomField field, String option)?
  onFieldOptionCountEdit;
  final void Function(
    BirdSpecies species,
    CustomField field,
    String parent,
    String child,
  )?
  onNestedFieldOptionCountEdit;
  const _RecordedTab({
    required this.prov,
    this.onNote,
    this.onCountEdit,
    this.onFieldOptionCountEdit,
    this.onNestedFieldOptionCountEdit,
  });

  @override
  State<_RecordedTab> createState() => _RecordedTabState();
}

class _RecordedTabState extends State<_RecordedTab> {
  @override
  Widget build(BuildContext context) {
    final prov = widget.prov;
    final list = prov.recordedSpecies;
    if (list.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.nature, size: 64, color: Colors.grey),
            SizedBox(height: 8),
            Text('尚未记录任何鸟种\n点击鸟种名称开始计数', textAlign: TextAlign.center),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '共 ${list.length} 种 / ${list.fold(0, (a, b) => a + b.count)} 只',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.green[700],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final s = list[i];
              return SpeciesTile(
                species: s,
                count: s.count,
                note: prov.getSpeciesNote(s.ebird),
                speciesAttrs: prov.getSpeciesFieldAttrs(s.ebird),
                quickFields: _tileQuickFields(
                  prov,
                  s,
                  onCountEdit: widget.onFieldOptionCountEdit,
                  onNestedCountEdit: widget.onNestedFieldOptionCountEdit,
                ),
                onIncrement: () => prov.incrementCount(s),
                onDecrement: () => prov.decrementCount(s),
                onCountEdit:
                    widget.onCountEdit != null
                        ? () => widget.onCountEdit!(s)
                        : null,
                onNote:
                    widget.onNote != null
                        ? () => widget.onNote!(s.ebird, s.zh)
                        : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Tab: History ──────────────────────────────────────────────────────────────
// Shows species from all past sessions sorted by historical frequency.
// +/- buttons update the CURRENT session's count (same as nearby/all tabs).

class _HistoryTab extends StatefulWidget {
  final SurveyProvider prov;
  final void Function(BirdSpecies)? onCountEdit;
  final void Function(BirdSpecies species, CustomField field, String option)?
  onFieldOptionCountEdit;
  const _HistoryTab({
    required this.prov,
    this.onCountEdit,
    this.onFieldOptionCountEdit,
  });

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  String _search = '';

  /// Build species list aggregated from history, sorted by frequency.
  List<BirdSpecies> _buildHistorySpecies() {
    final totals = <String, int>{};
    final names = <String, String>{};
    final prov = widget.prov;

    for (final s in prov.history) {
      for (final e in s.observations.entries) {
        final code = SurveySession.speciesCodeForKey(e.key);
        totals[code] = (totals[code] ?? 0) + e.value;
        names[code] = s.speciesNames[e.key] ?? s.speciesNames[code] ?? code;
      }
    }

    // Try to match to real species from master list; fall back to a stub.
    final result = <BirdSpecies>[];
    for (final entry in totals.entries) {
      final match = prov.allSpecies.cast<BirdSpecies?>().firstWhere(
        (s) => s!.ebird == entry.key,
        orElse: () => null,
      );
      if (match != null) {
        result.add(match.copyWith(ebirdFrequency: entry.value));
      } else {
        result.add(
          BirdSpecies(
            id: entry.key.hashCode,
            zh: names[entry.key] ?? entry.key,
            en: '',
            sci: '',
            family: '',
            order: '',
            ebird: entry.key,
            ebirdFrequency: entry.value,
          ),
        );
      }
    }
    result.sort((a, b) => b.ebirdFrequency.compareTo(a.ebirdFrequency));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final prov = widget.prov;
    if (prov.history.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey),
            SizedBox(height: 8),
            Text('暂无历史调查记录', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final all = _buildHistorySpecies();
    final q = _search.toLowerCase();
    final list =
        q.isEmpty
            ? all
            : all
                .where(
                  (s) => s.zh.contains(q) || s.en.toLowerCase().contains(q),
                )
                .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
          child: TextField(
            decoration: InputDecoration(
              hintText: '搜索历史鸟种...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            '历史累计 ${all.length} 种，按出现频率排序  · 点击直接计入本次调查',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final s = list[i];
              return SpeciesTile(
                species: s,
                count: prov.getCount(s),
                ebirdFreq: s.ebirdFrequency,
                note: prov.getSpeciesNote(s.ebird),
                speciesAttrs: prov.getSpeciesFieldAttrs(s.ebird),
                quickFields: _tileQuickFields(
                  prov,
                  s,
                  onCountEdit: widget.onFieldOptionCountEdit,
                ),
                onIncrement: () => prov.incrementCount(s),
                onDecrement: () => prov.decrementCount(s),
                onCountEdit:
                    widget.onCountEdit != null
                        ? () => widget.onCountEdit!(s)
                        : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Species Detail Dialog (fields + note) ─────────────────────────────────────

class _SpeciesDetailDialog extends StatefulWidget {
  final String zhName;
  final TextEditingController noteCtrl;
  final List<CustomField> fieldDefs;
  final Map<String, String> fieldValues; // mutable, updated in-place
  final VoidCallback onSave;
  final VoidCallback onClearNote;
  final bool hasExistingNote;

  const _SpeciesDetailDialog({
    required this.zhName,
    required this.noteCtrl,
    required this.fieldDefs,
    required this.fieldValues,
    required this.onSave,
    required this.onClearNote,
    required this.hasExistingNote,
  });

  @override
  State<_SpeciesDetailDialog> createState() => _SpeciesDetailDialogState();
}

class _SpeciesDetailDialogState extends State<_SpeciesDetailDialog> {
  late Map<String, TextEditingController> _textCtrls;

  @override
  void initState() {
    super.initState();
    _textCtrls = {
      for (final f in widget.fieldDefs.where(
        (f) => f.type == FieldType.text || f.type == FieldType.number,
      ))
        f.id: TextEditingController(text: widget.fieldValues[f.id] ?? ''),
    };
  }

  @override
  void dispose() {
    for (final c in _textCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('详细信息 · ${widget.zhName}'),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Custom field editors ──
            if (widget.fieldDefs.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '可在设置中添加物种自定义字段（如行为、位置等）',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ),
            ...widget.fieldDefs.map((f) {
              if (f.type == FieldType.select && f.options.isNotEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DropdownButtonFormField<String>(
                    value:
                        widget.fieldValues[f.id]?.isEmpty ?? true
                            ? null
                            : widget.fieldValues[f.id],
                    decoration: InputDecoration(
                      labelText: f.name,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('—')),
                      ...f.options.map(
                        (o) => DropdownMenuItem(value: o, child: Text(o)),
                      ),
                    ],
                    onChanged:
                        (v) =>
                            setState(() => widget.fieldValues[f.id] = v ?? ''),
                  ),
                );
              } else {
                final ctrl = _textCtrls[f.id]!;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: ctrl,
                    keyboardType:
                        f.type == FieldType.number
                            ? TextInputType.number
                            : TextInputType.text,
                    decoration: InputDecoration(
                      labelText: f.name,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (v) => widget.fieldValues[f.id] = v,
                  ),
                );
              }
            }),
            // ── Note ──
            if (widget.fieldDefs.isNotEmpty) const Divider(height: 16),
            VoiceNoteField(
              controller: widget.noteCtrl,
              hintText: '输入此鸟种的备注...',
              maxLines: 3,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        if (widget.hasExistingNote)
          TextButton(
            onPressed: () {
              widget.onClearNote();
              Navigator.pop(context);
            },
            child: const Text('删除备注', style: TextStyle(color: Colors.red)),
          ),
        ElevatedButton(
          onPressed: () {
            // Sync text controllers back to fieldValues before saving
            for (final f in widget.fieldDefs.where(
              (f) => f.type == FieldType.text || f.type == FieldType.number,
            )) {
              widget.fieldValues[f.id] = _textCtrls[f.id]!.text;
            }
            widget.onSave();
            Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

// ── Count calculator dialog ──────────────────────────────────────────────────

class _CountCalculatorDialog extends StatefulWidget {
  final String title;
  final int current;

  const _CountCalculatorDialog({required this.title, required this.current});

  @override
  State<_CountCalculatorDialog> createState() => _CountCalculatorDialogState();
}

class _CountCalculatorDialogState extends State<_CountCalculatorDialog> {
  late final TextEditingController _ctrl;
  int? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.current > 0 ? widget.current.toString() : '',
    );
    _ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _ctrl.text.length,
    );
    _ctrl.addListener(_recalculate);
    _recalculate();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _recalculate() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      setState(() {
        _result = 0;
        _error = null;
      });
      return;
    }
    final value = _CountExpressionParser(text).parse();
    if (value == null || value.isNaN || value.isInfinite || value < 0) {
      setState(() {
        _result = null;
        _error = '算式无效';
      });
      return;
    }
    final rounded = value.round();
    if ((value - rounded).abs() > 0.000001) {
      setState(() {
        _result = null;
        _error = '数量需要是整数';
      });
      return;
    }
    setState(() {
      _result = rounded;
      _error = null;
    });
  }

  void _append(String text) {
    final selection = _ctrl.selection;
    final source = _ctrl.text;
    final start = selection.start < 0 ? source.length : selection.start;
    final end = selection.end < 0 ? source.length : selection.end;
    final next = source.replaceRange(start, end, text);
    _ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  void _backspace() {
    final selection = _ctrl.selection;
    final source = _ctrl.text;
    if (source.isEmpty) return;
    if (selection.start != selection.end && selection.start >= 0) {
      final next = source.replaceRange(selection.start, selection.end, '');
      _ctrl.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: selection.start),
      );
      return;
    }
    final cursor = selection.start < 0 ? source.length : selection.start;
    if (cursor <= 0) return;
    final next = source.replaceRange(cursor - 1, cursor, '');
    _ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: cursor - 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrl,
              keyboardType: TextInputType.text,
              autofocus: true,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'[0-9+\-*/xX×÷().\s]'),
                ),
              ],
              decoration: InputDecoration(
                labelText: '数量 / 算式',
                hintText: '例如 32×5+2',
                border: const OutlineInputBorder(),
                errorText: _error,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.backspace_outlined),
                  onPressed: _backspace,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _result == null ? '结果：-' : '结果：$_result',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _result == null ? Colors.red : Colors.green[700],
              ),
            ),
            const SizedBox(height: 10),
            _CalculatorButtons(
              onAppend: _append,
              onClear: () => _ctrl.clear(),
              onRestore: () => _ctrl.text = widget.current.toString(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => _ctrl.text = widget.current.toString(),
          child: const Text('恢复原值'),
        ),
        ElevatedButton(
          onPressed:
              _result == null ? null : () => Navigator.pop(context, _result),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _CalculatorButtons extends StatelessWidget {
  final void Function(String text) onAppend;
  final VoidCallback onClear;
  final VoidCallback onRestore;

  const _CalculatorButtons({
    required this.onAppend,
    required this.onClear,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = [
      '7',
      '8',
      '9',
      '+',
      '4',
      '5',
      '6',
      '-',
      '1',
      '2',
      '3',
      '×',
      '0',
      '(',
      ')',
      '÷',
    ];
    return Column(
      children: [
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1.8,
          children:
              buttons
                  .map(
                    (b) => OutlinedButton(
                      onPressed: () => onAppend(b),
                      child: Text(b, style: const TextStyle(fontSize: 16)),
                    ),
                  )
                  .toList(),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => onAppend('+5'),
                child: const Text('+5'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton(
                onPressed: () => onAppend('+10'),
                child: const Text('+10'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton(
                onPressed: () => onAppend('×5'),
                child: const Text('×5'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton(
                onPressed: () => onAppend('×10'),
                child: const Text('×10'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextButton(onPressed: onClear, child: const Text('清空')),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextButton(onPressed: onRestore, child: const Text('原值')),
            ),
          ],
        ),
      ],
    );
  }
}

class _CountExpressionParser {
  final String source;
  int _pos = 0;

  _CountExpressionParser(String source)
    : source = source
          .replaceAll('×', '*')
          .replaceAll('÷', '/')
          .replaceAll('x', '*')
          .replaceAll('X', '*');

  double? parse() {
    try {
      final value = _parseExpression();
      _skipSpaces();
      if (_pos != source.length) return null;
      return value;
    } catch (_) {
      return null;
    }
  }

  double _parseExpression() {
    var value = _parseTerm();
    while (true) {
      _skipSpaces();
      if (_match('+')) {
        value += _parseTerm();
      } else if (_match('-')) {
        value -= _parseTerm();
      } else {
        return value;
      }
    }
  }

  double _parseTerm() {
    var value = _parseFactor();
    while (true) {
      _skipSpaces();
      if (_match('*')) {
        value *= _parseFactor();
      } else if (_match('/')) {
        value /= _parseFactor();
      } else {
        return value;
      }
    }
  }

  double _parseFactor() {
    _skipSpaces();
    if (_match('+')) return _parseFactor();
    if (_match('-')) return -_parseFactor();
    if (_match('(')) {
      final value = _parseExpression();
      if (!_match(')')) throw const FormatException('missing )');
      return value;
    }
    return _parseNumber();
  }

  double _parseNumber() {
    _skipSpaces();
    final start = _pos;
    while (_pos < source.length) {
      final char = source[_pos];
      if (!RegExp(r'[0-9.]').hasMatch(char)) break;
      _pos++;
    }
    if (start == _pos) throw const FormatException('number expected');
    final value = double.tryParse(source.substring(start, _pos));
    if (value == null) throw const FormatException('invalid number');
    return value;
  }

  bool _match(String token) {
    _skipSpaces();
    if (_pos < source.length && source[_pos] == token) {
      _pos++;
      return true;
    }
    return false;
  }

  void _skipSpaces() {
    while (_pos < source.length && source[_pos].trim().isEmpty) {
      _pos++;
    }
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Builds QuickField list for select-type species field defs.
List<QuickField> _tileQuickFields(
  SurveyProvider prov,
  BirdSpecies s, {
  void Function(BirdSpecies species, CustomField field, String option)?
  onCountEdit,
  void Function(
    BirdSpecies species,
    CustomField field,
    String parent,
    String child,
  )?
  onNestedCountEdit,
}) {
  final result = <QuickField>[];
  if (prov.hasNestedFieldRelation) {
    final parent = prov.speciesFieldById(prov.nestedParentFieldId);
    final child = prov.speciesFieldById(prov.nestedChildFieldId);
    if (parent != null &&
        child != null &&
        parent.options.isNotEmpty &&
        child.options.isNotEmpty) {
      final relationField = CustomField(
        id: prov.nestedRelationFieldId,
        name: '${parent.name}-${child.name}',
        type: FieldType.nestedSelect,
        nestedOptions: {
          for (final option in parent.options) option: child.options,
        },
      );
      result.add(
        QuickField(
          id: relationField.id,
          name: relationField.name,
          options: const [],
          nestedOptions: relationField.nestedOptions,
          currentValue: '',
          optionCounts: const {},
          nestedCounts: prov.getNestedSpeciesFieldCounts(
            s.ebird,
            relationField.id,
          ),
          onChanged: (_) {},
          onIncrement: (_) {},
          onNestedIncrement:
              (parentOption, childOption) =>
                  prov.incrementNestedSpeciesFieldOption(
                    s,
                    relationField.id,
                    parentOption,
                    childOption,
                  ),
          onNestedCountEdit:
              onNestedCountEdit == null
                  ? null
                  : (parentOption, childOption) => onNestedCountEdit(
                    s,
                    relationField,
                    parentOption,
                    childOption,
                  ),
        ),
      );
    }
  }
  result.addAll(
    prov.speciesFieldDefs
        .where((f) {
          if (f.id == prov.nestedParentFieldId ||
              f.id == prov.nestedChildFieldId) {
            return false;
          }
          return (f.type == FieldType.select && f.options.isNotEmpty) ||
              (f.type == FieldType.nestedSelect && f.nestedOptions.isNotEmpty);
        })
        .map(
          (f) => QuickField(
            id: f.id,
            name: f.name,
            options: f.options,
            nestedOptions: f.nestedOptions,
            currentValue: prov.getSpeciesFieldValue(s.ebird, f.id),
            optionCounts: prov.getSpeciesFieldCounts(s.ebird, f.id),
            nestedCounts: prov.getNestedSpeciesFieldCounts(s.ebird, f.id),
            onChanged: (v) => prov.setSpeciesFieldValue(s.ebird, f.id, v),
            onIncrement: (v) => prov.incrementSpeciesFieldOption(s, f.id, v),
            onCountEdit:
                onCountEdit == null ? null : (v) => onCountEdit(s, f, v),
            onNestedIncrement:
                (parent, child) => prov.incrementNestedSpeciesFieldOption(
                  s,
                  f.id,
                  parent,
                  child,
                ),
            onNestedCountEdit:
                onNestedCountEdit == null
                    ? null
                    : (parent, child) => onNestedCountEdit(s, f, parent, child),
          ),
        ),
  );
  return result;
}

/// Wraps end-survey dialog result: notes text + whether to start new survey.
class _EndResult {
  final String notes;
  final bool startNew;
  const _EndResult(this.notes, {this.startNew = false});
}

// ── Add Custom Species Button ─────────────────────────────────────────────────

class _AddCustomSpeciesButton extends StatelessWidget {
  final SurveyProvider prov;
  const _AddCustomSpeciesButton({required this.prov});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.add, size: 18),
        label: const Text('找不到？手动添加鸟种'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onPressed: () => _showAddDialog(context),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final zhCtrl = TextEditingController();
    final enCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('手动添加鸟种'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: zhCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '中文名（必填）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: enCtrl,
                  decoration: const InputDecoration(
                    labelText: '英文名（可选）',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  final zh = zhCtrl.text.trim();
                  if (zh.isEmpty) return;
                  prov.addCustomSpecies(zh, enCtrl.text.trim());
                  Navigator.pop(context);
                },
                child: const Text('添加并计1只'),
              ),
            ],
          ),
    );
  }
}
