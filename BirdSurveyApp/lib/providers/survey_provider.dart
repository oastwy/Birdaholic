import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bird_species.dart';
import '../models/custom_field.dart';
import '../models/history_folder.dart';
import '../models/survey_point.dart';
import '../models/survey_project.dart';
import '../models/survey_session.dart';
import '../models/survey_version.dart';
import '../services/database_service.dart';
import '../services/ebird_service.dart';
import '../services/location_service.dart';
import '../services/survey_point_service.dart';
import '../services/survey_project_service.dart';
import '../services/tide_service.dart';
import '../services/transect_event_log_service.dart';
import '../services/weather_service.dart';

enum SurveyStatus { idle, active, saving }

enum NearbyMode { recent, localHistory, province }

enum SurveyMode { point, transect }

class _EditSnapshot {
  final SurveySession session;
  final String summary;

  const _EditSnapshot(this.session, this.summary);
}

class SurveyProvider extends ChangeNotifier {
  List<BirdSpecies> _allSpecies = [];
  List<BirdSpecies> _nearbySpecies = [];
  List<SurveySession> _history = [];
  SurveySession? _currentSession;
  SurveyStatus _status = SurveyStatus.idle;
  Position? _position;
  StreamSubscription<Position>? _transectPositionSub;
  TideResult? _tideResult;
  String _searchQuery = '';
  bool _loadingNearby = false;
  NearbyMode _nearbyMode = NearbyMode.recent;
  String? _error;

  // Settings
  String _ebirdApiKey = '';
  String _chaoxi365Key = '';
  String _chaoxi365Endpoint = TideService.defaultChaoxi365Endpoint;
  String _stormglassKey = '';
  String _worldtidesKey = '';
  String _qweatherKey = '';
  TideSource _tideSource = TideSource.local;
  List<CustomField> _customFields = [];
  List<SurveyPoint> _surveyPoints = [];
  List<SurveyProject> _surveyProjects = [];
  List<HistoryFolder> _historyFolders = [];
  String _tiandituKey = '';

  // Per-species custom field definitions
  List<CustomField> _speciesFieldDefs = [];
  String _nestedParentFieldId = '';
  String _nestedChildFieldId = '';

  // Recent species (from last completed survey)
  Set<String> _recentEbirdCodes = {};
  final Map<String, String> _activeObservationKeys = {};

  // Stable insertion-order tracking for 已记录 tab
  final List<String> _recordedOrder = [];
  final List<_EditSnapshot> _editSnapshots = [];
  SurveySession? _editingOriginalSession;
  bool _editingHistory = false;
  bool _hasUnsavedHistoryEdits = false;

  // First-launch setup flag
  bool _setupDone = false;

  // Province / national eBird fallback
  List<BirdSpecies> _provinceSpecies = [];
  List<BirdSpecies> _nationalSpecies = [];
  bool _loadingProvince = false;
  bool _loadingNational = false;
  String _provinceRegionCode = '';
  String _provinceRegionName = '';

  // Getters
  List<BirdSpecies> get allSpecies => _allSpecies;
  List<BirdSpecies> get nearbySpecies => _nearbySpecies;
  List<SurveySession> get history => _history;
  SurveySession? get currentSession => _currentSession;
  SurveyStatus get status => _status;
  Position? get position => _position;
  TideResult? get tideResult => _tideResult;
  bool get loadingNearby => _loadingNearby;
  NearbyMode get nearbyMode => _nearbyMode;
  String? get error => _error;
  String get ebirdApiKey => _ebirdApiKey;
  String get chaoxi365Key => _chaoxi365Key;
  String get chaoxi365Endpoint => _chaoxi365Endpoint;
  String get stormglassKey => _stormglassKey;
  String get worldtidesKey => _worldtidesKey;
  String get qweatherKey => _qweatherKey;
  TideSource get tideSource => _tideSource;
  List<CustomField> get customFields => _customFields;
  List<SurveyPoint> get surveyPoints => _surveyPoints;
  List<SurveyProject> get surveyProjects => _surveyProjects;
  List<HistoryFolder> get historyFolders => _historyFolders;
  List<SurveyPoint> get visibleSurveyPoints =>
      _surveyPoints.where((p) => p.isVisible).toList();
  Set<String> get surveyPointCounties =>
      _surveyPoints.map((p) => p.county).where((c) => c.isNotEmpty).toSet();
  Set<String> get surveyPointWindFarms =>
      _surveyPoints.map((p) => p.windFarm).where((w) => w.isNotEmpty).toSet();
  String get tiandituKey => _tiandituKey;
  bool get isTransect => _currentSession?.surveyMode == 'transect';
  List<TransectTrackPoint> get transectTrack =>
      _currentSession?.transectTrack ?? const [];
  List<SpeciesObservationEvent> get observationEvents =>
      _currentSession?.observationEvents ?? const [];
  String get activeTransectPointId {
    final session = _currentSession;
    if (session == null || session.surveyMode != 'transect') return '';
    return session.activeTransectPointId;
  }

  List<CustomField> get speciesFieldDefs => _speciesFieldDefs;
  String get nestedParentFieldId => _nestedParentFieldId;
  String get nestedChildFieldId => _nestedChildFieldId;
  bool get hasNestedFieldRelation =>
      _nestedParentFieldId.isNotEmpty &&
      _nestedChildFieldId.isNotEmpty &&
      _nestedParentFieldId != _nestedChildFieldId;
  String get nestedRelationFieldId =>
      '${_nestedParentFieldId}__nested__$_nestedChildFieldId';
  bool get setupDone => _setupDone;
  String get searchQuery => _searchQuery;
  bool get isEditingHistory => _editingHistory;
  bool get hasUnsavedHistoryEdits => _hasUnsavedHistoryEdits;
  List<String> get editLog => _editSnapshots.map((s) => s.summary).toList();
  List<BirdSpecies> get provinceSpecies => _provinceSpecies;
  List<BirdSpecies> get nationalSpecies => _nationalSpecies;
  bool get loadingProvince => _loadingProvince;
  bool get loadingNational => _loadingNational;
  String get provinceRegionName => _provinceRegionName;

  List<BirdSpecies> get filteredNearbySpecies {
    final result =
        _searchQuery.isEmpty
            ? List<BirdSpecies>.from(_nearbySpecies)
            : _applyFilter(_nearbySpecies, _searchQuery);
    final priorityCodes = _previousTransectPointSpeciesOrder();
    if (priorityCodes.isNotEmpty) {
      result.sort((a, b) {
        final ai = priorityCodes[a.ebird] ?? 1 << 30;
        final bi = priorityCodes[b.ebird] ?? 1 << 30;
        if (ai != bi) return ai.compareTo(bi);
        return b.ebirdFrequency.compareTo(a.ebirdFrequency);
      });
    }
    return result;
  }

  List<BirdSpecies> get filteredProvinceSpecies {
    if (_searchQuery.isEmpty) return _provinceSpecies;
    return _applyFilter(_provinceSpecies, _searchQuery);
  }

  List<BirdSpecies> get filteredNationalSpecies {
    if (_searchQuery.isEmpty) return _nationalSpecies;
    return _applyFilter(_nationalSpecies, _searchQuery);
  }

  static List<BirdSpecies> _applyFilter(List<BirdSpecies> list, String query) {
    final q = query.toLowerCase().trim();
    final isPinyin =
        q.isNotEmpty && RegExp(r'^[a-z]+$').hasMatch(q) && !q.contains(' ');
    return list.where((s) {
      if (s.zh.contains(q)) return true;
      if (s.zhAlt.isNotEmpty && s.zhAlt.contains(q)) return true;
      if (s.en.toLowerCase().contains(q)) return true;
      if (s.sci.toLowerCase().contains(q)) return true;
      if (s.sciAlt.isNotEmpty && s.sciAlt.toLowerCase().contains(q)) {
        return true;
      }
      if (isPinyin) {
        if (PinyinHelper.getShortPinyin(s.zh).toLowerCase().contains(q)) {
          return true;
        }
        if (s.zhAlt.isNotEmpty &&
            PinyinHelper.getShortPinyin(s.zhAlt).toLowerCase().contains(q)) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  Map<String, int> _previousTransectPointSpeciesOrder() {
    final session = _currentSession;
    if (session == null || session.surveyMode != 'transect') return {};
    final activeId = session.activeTransectPointId;
    if (activeId.isEmpty) return {};
    final activeIndex = session.transectTrack.indexWhere(
      (p) => p.id == activeId,
    );
    if (activeIndex <= 0) return {};
    final previousId = session.transectTrack[activeIndex - 1].id;
    final order = <String, int>{};
    for (final event in session.observationEvents.where(
      (e) =>
          e.trackPointId == previousId &&
          (e.type == 'species_count' ||
              e.type == 'field_count' ||
              e.type == 'nested_field_count') &&
          e.delta > 0,
    )) {
      order.putIfAbsent(event.ebirdCode, () => order.length);
    }
    return order;
  }

  List<BirdSpecies> get recordedSpecies {
    // Remove species whose count dropped to 0
    _recordedOrder.removeWhere(
      (code) => !_allSpecies.any((s) => s.ebird == code && s.count > 0),
    );
    // Append any newly recorded species not yet tracked
    for (final s in _allSpecies.where((s) => s.count > 0)) {
      if (!_recordedOrder.contains(s.ebird)) _recordedOrder.add(s.ebird);
    }
    final byCode = {for (final s in _allSpecies) s.ebird: s};
    return [
      for (final code in _recordedOrder)
        if (byCode[code] != null) byCode[code]!,
    ];
  }

  List<BirdSpecies> get filteredAllSpecies {
    final List<BirdSpecies> result =
        _searchQuery.isEmpty
            ? List<BirdSpecies>.from(_allSpecies)
            : _applyFilter(_allSpecies, _searchQuery);
    // Recent species (from last survey) float to the top
    if (_recentEbirdCodes.isNotEmpty) {
      result.sort((a, b) {
        final aR = _recentEbirdCodes.contains(a.ebird) ? 0 : 1;
        final bR = _recentEbirdCodes.contains(b.ebird) ? 0 : 1;
        return aR.compareTo(bR);
      });
    }
    return result;
  }

  Future<void> init() async {
    await _loadPrefs();
    await _loadBirdData();
    await _loadHistory();
    await _recoverTransectEventLog();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _ebirdApiKey = prefs.getString('ebird_api_key') ?? '';
    _chaoxi365Key = prefs.getString('chaoxi365_key') ?? '';
    _chaoxi365Endpoint =
        prefs.getString('chaoxi365_endpoint') ??
        TideService.defaultChaoxi365Endpoint;
    _stormglassKey = prefs.getString('stormglass_key') ?? '';
    _worldtidesKey = prefs.getString('worldtides_key') ?? '';
    _qweatherKey = prefs.getString('qweather_key') ?? '';
    _tiandituKey = prefs.getString('tianditu_key') ?? '';
    _tideSource = TideSourceLabel.fromName(
      prefs.getString('tide_source') ?? 'local',
    );
    final fieldsJson = prefs.getString('custom_fields') ?? '';
    _customFields = CustomField.decodeList(fieldsJson);
    _surveyPoints = await SurveyPointService.load();
    final recentJson = prefs.getString('recent_ebird_codes') ?? '';
    if (recentJson.isNotEmpty) {
      final list = (jsonDecode(recentJson) as List).cast<String>();
      _recentEbirdCodes = list.toSet();
    }
    _setupDone = prefs.getBool('setup_done') ?? false;
    final speciesFieldsJson = prefs.getString('species_field_defs') ?? '';
    _speciesFieldDefs = CustomField.decodeList(speciesFieldsJson);
    _nestedParentFieldId = prefs.getString('nested_parent_field_id') ?? '';
    _nestedChildFieldId = prefs.getString('nested_child_field_id') ?? '';
    _surveyProjects = await SurveyProjectService.load();
    _historyFolders = HistoryFolder.decodeList(
      prefs.getString('history_folders') ?? '',
    );
  }

  Future<void> saveSettings({
    required String ebird,
    required String chaoxi365,
    required String chaoxi365Endpoint,
    required String stormglass,
    required String worldtides,
    required String tianditu,
    required String qweather,
    required TideSource tideSource,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ebird_api_key', ebird);
    await prefs.setString('chaoxi365_key', chaoxi365);
    await prefs.setString('chaoxi365_endpoint', chaoxi365Endpoint);
    await prefs.setString('stormglass_key', stormglass);
    await prefs.setString('worldtides_key', worldtides);
    await prefs.setString('tianditu_key', tianditu);
    await prefs.setString('qweather_key', qweather);
    await prefs.setString('tide_source', tideSource.name);
    _ebirdApiKey = ebird;
    _chaoxi365Key = chaoxi365;
    _chaoxi365Endpoint =
        chaoxi365Endpoint.isEmpty
            ? TideService.defaultChaoxi365Endpoint
            : chaoxi365Endpoint;
    _stormglassKey = stormglass;
    _worldtidesKey = worldtides;
    _tiandituKey = tianditu;
    _qweatherKey = qweather;
    _tideSource = tideSource;
    notifyListeners();
  }

  // ── Survey Points ──────────────────────────────────────────────────────────

  Future<void> retryGps() async {
    final pos = await LocationService.getCurrentPosition();
    _position = pos;
    notifyListeners();
  }

  void _startTransectPositionStream() {
    _transectPositionSub?.cancel();
    _transectPositionSub = LocationService.getPositionStream().listen((pos) {
      _position = pos;
      notifyListeners();
    }, onError: (_) {});
  }

  void _stopTransectPositionStream() {
    _transectPositionSub?.cancel();
    _transectPositionSub = null;
  }

  Future<void> addTransectTrackPoint({String note = ''}) async {
    final session = _currentSession;
    if (session == null || !isTransect) return;
    final pos = await LocationService.getCurrentPosition();
    if (pos != null) _position = pos;
    _createTransectPoint(note: note);
    _saveCurrentSession();
    notifyListeners();
  }

  Future<void> endCurrentTransectPoint() async {
    final session = _currentSession;
    final pointId = activeTransectPointId;
    if (session == null || !isTransect || pointId.isEmpty) return;
    final index = session.transectTrack.indexWhere((p) => p.id == pointId);
    if (index < 0) return;
    final endedAt = DateTime.now();
    final updatedTrack = [...session.transectTrack];
    updatedTrack[index] = updatedTrack[index].copyWith(endedAt: () => endedAt);
    _currentSession = session.copyWith(
      activeTransectPointId: '',
      transectTrack: updatedTrack,
    );
    _resetCounts();
    _recordedOrder.clear();
    await TransectEventLogService.append({
      'eventId': _newEventId('track_end'),
      'sessionId': session.id,
      'type': 'track_point_end',
      'trackPointId': pointId,
      'endedAt': endedAt.toIso8601String(),
    });
    _saveCurrentSession();
    notifyListeners();
  }

  void _createTransectPoint({String note = ''}) {
    final session = _currentSession;
    if (session == null || !isTransect) return;
    final lat = _position?.latitude ?? session.latitude;
    final lon = _position?.longitude ?? session.longitude;
    final point = TransectTrackPoint(
      id: _newEventId('track'),
      time: DateTime.now(),
      latitude: lat,
      longitude: lon,
      note: note,
    );
    _currentSession = session.copyWith(
      activeTransectPointId: point.id,
      transectTrack: [...session.transectTrack, point],
    );
    _resetCounts();
    _recordedOrder.clear();
    _appendTransectLog({
      'eventId': point.id,
      'type': 'track_point',
      ...point.toJson(),
    });
  }

  bool _ensureActiveTransectPoint() {
    if (!isTransect) return true;
    if (activeTransectPointId.isNotEmpty) return true;
    _createTransectPoint();
    return activeTransectPointId.isNotEmpty;
  }

  Future<void> markSetupDone() async {
    _setupDone = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setup_done', true);
    notifyListeners();
  }

  Future<void> fetchProvinceSpecies(double lat, double lon) async {
    if (_ebirdApiKey.isEmpty) return;
    _loadingProvince = true;
    _provinceSpecies = [];
    notifyListeners();
    try {
      final service = EbirdService(_ebirdApiKey);
      _provinceRegionCode = EbirdService.getRegionCode(lat, lon);
      _provinceRegionName =
          EbirdService.regionNames[_provinceRegionCode] ?? '本省';
      final freq = await service.getRegionSpeciesFrequency(
        regionCode: _provinceRegionCode,
      );
      _provinceSpecies =
          _allSpecies
              .where((s) => freq.containsKey(s.ebird))
              .map((s) => s.copyWith(ebirdFrequency: freq[s.ebird] ?? 0))
              .toList()
            ..sort((a, b) => b.ebirdFrequency.compareTo(a.ebirdFrequency));
    } catch (e) {
      _error = '省级eBird加载失败: $e';
    }
    _loadingProvince = false;
    notifyListeners();
  }

  Future<void> fetchNationalSpecies() async {
    if (_ebirdApiKey.isEmpty) return;
    _loadingNational = true;
    _nationalSpecies = [];
    notifyListeners();
    try {
      final service = EbirdService(_ebirdApiKey);
      final freq = await service.getRegionSpeciesFrequency(
        regionCode: 'CN',
        back: 14,
      );
      _nationalSpecies =
          _allSpecies
              .where((s) => freq.containsKey(s.ebird))
              .map((s) => s.copyWith(ebirdFrequency: freq[s.ebird] ?? 0))
              .toList()
            ..sort((a, b) => b.ebirdFrequency.compareTo(a.ebirdFrequency));
    } catch (e) {
      _error = '全国eBird加载失败: $e';
    }
    _loadingNational = false;
    notifyListeners();
  }

  void clearProvinceFallback() {
    _provinceSpecies = [];
    _nationalSpecies = [];
    notifyListeners();
  }

  Future<void> reloadSurveyPoints() async {
    _surveyPoints = await SurveyPointService.load();
    notifyListeners();
  }

  Future<void> addSurveyPoint(SurveyPoint point) async {
    await SurveyPointService.add(point);
    await reloadSurveyPoints();
  }

  Future<void> deleteSurveyPoint(String id) async {
    await SurveyPointService.delete(id);
    await reloadSurveyPoints();
  }

  Future<void> deleteSurveyPoints(Set<String> ids) async {
    await SurveyPointService.deleteMany(ids);
    await reloadSurveyPoints();
  }

  Future<void> deleteAllSurveyPoints() async {
    await SurveyPointService.deleteAll();
    await reloadSurveyPoints();
  }

  Future<void> setSurveyPointsVisibility(Set<String> ids, bool visible) async {
    await SurveyPointService.setVisibility(ids, visible);
    await reloadSurveyPoints();
  }

  Future<void> setAllSurveyPointsVisibility(bool visible) async {
    await SurveyPointService.setAllVisibility(visible);
    await reloadSurveyPoints();
  }

  // ── Survey Projects ────────────────────────────────────────────────────────

  Future<void> reloadSurveyProjects() async {
    _surveyProjects = await SurveyProjectService.load();
    notifyListeners();
  }

  Future<void> addSurveyProject(SurveyProject project) async {
    await SurveyProjectService.add(project);
    await reloadSurveyProjects();
  }

  Future<void> updateSurveyProject(SurveyProject project) async {
    await SurveyProjectService.update(project);
    await reloadSurveyProjects();
  }

  Future<void> deleteSurveyProject(String id) async {
    await SurveyProjectService.delete(id);
    await reloadSurveyProjects();
  }

  /// Returns the survey points belonging to a project.
  List<SurveyPoint> pointsForProject(SurveyProject project) {
    final ids = project.pointIds.toSet();
    return _surveyPoints.where((p) => ids.contains(p.id)).toList();
  }

  /// Returns all history sessions whose point name matches any point in the project.
  List<SurveySession> sessionsForProject(SurveyProject project) {
    final points = pointsForProject(project);
    final names = points.map((p) => p.name).toSet();
    return _history.where((s) {
      final name = s.customValues['位点名称'] ?? s.customValues['地点名称'] ?? '';
      return names.contains(name);
    }).toList();
  }

  Future<int> importSurveyPointsCsv(String csv) async {
    final count = await SurveyPointService.importFromCsv(csv);
    await reloadSurveyPoints();
    return count;
  }

  Future<int> importSurveyPointsKml(String kml) async {
    final count = await SurveyPointService.importFromKml(kml);
    await reloadSurveyPoints();
    return count;
  }

  /// Returns points sorted by distance from [lat],[lon], with distanceM attached.
  /// Optionally scoped to a project's points via [projectId].
  List<SurveyPoint> nearbyPoints(
    double lat,
    double lon, {
    int maxCount = 5,
    String? projectId,
  }) {
    var pool = _surveyPoints;
    if (projectId != null) {
      final proj = _surveyProjects.firstWhere(
        (p) => p.id == projectId,
        orElse: () => SurveyProject(id: '', name: '', pointIds: []),
      );
      final ids = proj.pointIds.toSet();
      pool = pool.where((p) => ids.contains(p.id)).toList();
    }
    return (pool
            .map((p) => p.copyWith(distanceM: p.distanceTo(lat, lon)))
            .toList()
          ..sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0)))
        .take(maxCount)
        .toList();
  }

  Future<void> saveCustomFields(List<CustomField> fields) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_fields', CustomField.encodeList(fields));
    _customFields = fields;
    notifyListeners();
  }

  Future<void> saveSpeciesFieldDefs(List<CustomField> fields) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('species_field_defs', CustomField.encodeList(fields));
    _speciesFieldDefs = fields;
    final ids = fields.map((f) => f.id).toSet();
    if (!ids.contains(_nestedParentFieldId)) {
      _nestedParentFieldId = '';
      await prefs.setString('nested_parent_field_id', '');
    }
    if (!ids.contains(_nestedChildFieldId)) {
      _nestedChildFieldId = '';
      await prefs.setString('nested_child_field_id', '');
    }
    notifyListeners();
  }

  Future<void> saveNestedFieldRelation({
    required String parentFieldId,
    required String childFieldId,
  }) async {
    final safeParent = parentFieldId == childFieldId ? '' : parentFieldId;
    final safeChild = parentFieldId == childFieldId ? '' : childFieldId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nested_parent_field_id', safeParent);
    await prefs.setString('nested_child_field_id', safeChild);
    _nestedParentFieldId = safeParent;
    _nestedChildFieldId = safeChild;
    notifyListeners();
  }

  CustomField? speciesFieldById(String id) {
    for (final field in _speciesFieldDefs) {
      if (field.id == id) return field;
    }
    return null;
  }

  Future<void> saveHistoryFolders(List<HistoryFolder> folders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('history_folders', HistoryFolder.encodeList(folders));
    _historyFolders = folders;
    notifyListeners();
  }

  Future<void> addHistoryFolder(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final folders = List<HistoryFolder>.from(_historyFolders)..add(
      HistoryFolder(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: trimmed,
      ),
    );
    await saveHistoryFolders(folders);
  }

  Future<void> renameHistoryFolder(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final folders =
        _historyFolders
            .map((f) => f.id == id ? f.copyWith(name: trimmed) : f)
            .toList();
    await saveHistoryFolders(folders);
  }

  Future<bool> deleteHistoryFolder(String id) async {
    if (_history.any((s) => s.folderId == id)) return false;
    await saveHistoryFolders(_historyFolders.where((f) => f.id != id).toList());
    return true;
  }

  String getSpeciesFieldValue(String ebirdCode, String fieldId) =>
      _currentSession?.speciesFields[_activeKeyFor(ebirdCode)]?[fieldId] ?? '';

  void setSpeciesFieldValue(String ebirdCode, String fieldId, String value) {
    if (_currentSession == null) return;
    _recordEditSnapshot('$ebirdCode 字段修改');
    final observationKey = _keyForFieldValue(ebirdCode, fieldId, value);
    _activeObservationKeys[ebirdCode] = observationKey;
    _currentSession!.speciesFields.putIfAbsent(observationKey, () => {});
    if (value.isEmpty) {
      _currentSession!.speciesFields[observationKey]!.remove(fieldId);
    } else {
      _currentSession!.speciesFields[observationKey]![fieldId] = value;
    }
    _saveCurrentSession();
    notifyListeners();
  }

  /// Returns all non-empty field values for a species as {fieldName: value}.
  Map<String, String> getSpeciesFieldAttrs(String ebirdCode) {
    final fieldMap =
        _currentSession?.speciesFields[_activeKeyFor(ebirdCode)] ?? {};
    final result = <String, String>{};
    for (final def in _speciesFieldDefs) {
      final v = fieldMap[def.id] ?? '';
      if (v.isNotEmpty) result[def.name] = v;
    }
    return result;
  }

  Map<String, int> getSpeciesFieldCounts(String ebirdCode, String fieldId) {
    final session = _currentSession;
    if (session == null) return {};
    if (isTransect) {
      final result = _currentTransectFieldCounts(
        ebirdCode,
        type: 'field_count',
        fieldId: fieldId,
      );
      CustomField? field;
      for (final def in _speciesFieldDefs) {
        if (def.id == fieldId) {
          field = def;
          break;
        }
      }
      if (field != null && field.options.contains('其他')) {
        final nonOther = result.entries
            .where((e) => e.key != '其他')
            .fold(0, (sum, e) => sum + e.value);
        final remainder = _currentTransectSpeciesTotal(ebirdCode) - nonOther;
        result['其他'] = remainder > 0 ? remainder : 0;
      }
      return result;
    }
    final result = Map<String, int>.from(
      session.speciesFieldCounts[ebirdCode]?[fieldId] ?? {},
    );
    CustomField? field;
    for (final def in _speciesFieldDefs) {
      if (def.id == fieldId) {
        field = def;
        break;
      }
    }
    if (field != null && field.options.contains('其他')) {
      final nonOther = result.entries
          .where((e) => e.key != '其他')
          .fold(0, (sum, e) => sum + e.value);
      final remainder = _currentSpeciesTotal(ebirdCode) - nonOther;
      result['其他'] = remainder > 0 ? remainder : 0;
    }
    return result;
  }

  Map<String, Map<String, int>> getNestedSpeciesFieldCounts(
    String ebirdCode,
    String fieldId,
  ) {
    final session = _currentSession;
    if (session == null) return {};
    if (isTransect) {
      return _currentTransectNestedCounts(ebirdCode, fieldId);
    }
    return {
      for (final parent
          in (session.nestedSpeciesFieldCounts[ebirdCode]?[fieldId] ?? {})
              .entries)
        parent.key: Map<String, int>.from(parent.value),
    };
  }

  Future<void> _loadBirdData() async {
    final jsonStr = await rootBundle.loadString(
      'assets/data/chinese_birds.json',
    );
    final list = jsonDecode(jsonStr) as List<dynamic>;
    _allSpecies =
        list
            .map((e) => BirdSpecies.fromJson(e as Map<String, dynamic>))
            .toList();
    notifyListeners();
  }

  Future<void> _loadHistory() async {
    _history = await DatabaseService.getAllSurveys();
    notifyListeners();
  }

  Future<void> _recoverTransectEventLog() async {
    final events = await TransectEventLogService.readAll();
    if (events.isEmpty) return;
    var changed = false;
    final byId = {
      for (final s in _history.where((s) => s.id != null)) s.id!: s,
    };

    for (final raw in events) {
      final sessionId = int.tryParse(raw['sessionId']?.toString() ?? '');
      final eventId = raw['eventId']?.toString() ?? raw['id']?.toString() ?? '';
      final type = raw['type']?.toString() ?? '';
      if (sessionId == null || eventId.isEmpty) continue;
      var session = byId[sessionId];
      if (session == null || session.surveyMode != 'transect') continue;

      final seen =
          session.transectTrack.any((p) => p.id == eventId) ||
          session.observationEvents.any((e) => e.eventId == eventId);
      if (seen) continue;

      if (type == 'track_point') {
        session.transectTrack.add(
          TransectTrackPoint(
            id: eventId,
            time:
                DateTime.tryParse(raw['time']?.toString() ?? '') ??
                DateTime.now(),
            latitude: (raw['latitude'] as num?)?.toDouble() ?? 0,
            longitude: (raw['longitude'] as num?)?.toDouble() ?? 0,
            note: raw['note']?.toString() ?? '',
          ),
        );
        session = session.copyWith(activeTransectPointId: eventId);
        byId[sessionId] = session;
        changed = true;
      } else if (type == 'track_point_end') {
        final pointId = raw['trackPointId']?.toString() ?? '';
        final endedAt = DateTime.tryParse(raw['endedAt']?.toString() ?? '');
        if (pointId.isEmpty || endedAt == null) continue;
        final updatedTrack = [...session.transectTrack];
        final index = updatedTrack.indexWhere((p) => p.id == pointId);
        if (index < 0) continue;
        if (updatedTrack[index].endedAt != null) continue;
        updatedTrack[index] = updatedTrack[index].copyWith(
          endedAt: () => endedAt,
        );
        session = session.copyWith(
          activeTransectPointId: '',
          transectTrack: updatedTrack,
        );
        byId[sessionId] = session;
        changed = true;
      } else if (type == 'species_count' ||
          type == 'field_count' ||
          type == 'nested_field_count') {
        final code = raw['ebirdCode']?.toString() ?? '';
        if (code.isEmpty) continue;
        final delta = int.tryParse(raw['delta']?.toString() ?? '') ?? 0;
        final name = raw['speciesName']?.toString() ?? code;
        if (type == 'species_count') {
          final current = session.speciesTotals()[code] ?? 0;
          final next = current + delta;
          if (next > 0) {
            session.observations[code] = next;
            session.speciesNames[code] = name;
          } else {
            session.observations.remove(code);
            session.speciesNames.remove(code);
          }
        } else {
          session.speciesNames[code] = name;
          if (type == 'field_count') {
            final fieldId = raw['fieldId']?.toString() ?? '';
            final option = raw['option']?.toString() ?? '';
            if (fieldId.isNotEmpty && option.isNotEmpty) {
              session.speciesFieldCounts.putIfAbsent(code, () => {});
              session.speciesFieldCounts[code]!.putIfAbsent(fieldId, () => {});
              final counts = session.speciesFieldCounts[code]![fieldId]!;
              final value = (counts[option] ?? 0) + delta;
              counts[option] = value < 0 ? 0 : value;
              if (counts[option] == 0) counts.remove(option);
            }
          } else if (type == 'nested_field_count') {
            final fieldId = raw['fieldId']?.toString() ?? '';
            final parent = raw['parentOption']?.toString() ?? '';
            final child = raw['childOption']?.toString() ?? '';
            if (fieldId.isNotEmpty && parent.isNotEmpty && child.isNotEmpty) {
              session.nestedSpeciesFieldCounts.putIfAbsent(code, () => {});
              session.nestedSpeciesFieldCounts[code]!.putIfAbsent(
                fieldId,
                () => {},
              );
              session.nestedSpeciesFieldCounts[code]![fieldId]!.putIfAbsent(
                parent,
                () => {},
              );
              final counts =
                  session.nestedSpeciesFieldCounts[code]![fieldId]![parent]!;
              final value = (counts[child] ?? 0) + delta;
              counts[child] = value < 0 ? 0 : value;
              if (counts[child] == 0) counts.remove(child);
            }
          }
        }
        session.observationEvents.add(SpeciesObservationEvent.fromJson(raw));
        changed = true;
      }
    }

    if (changed) {
      for (final session in byId.values) {
        await DatabaseService.updateSurvey(session);
      }
      await _loadHistory();
    }
    await TransectEventLogService.clear();
  }

  Future<void> startSurvey(
    Map<String, String> customValues, {
    double? manualLat,
    double? manualLon,
    SurveyMode mode = SurveyMode.point,
  }) async {
    _error = null;
    _resetCounts();
    _recordedOrder.clear();
    _nearbySpecies = [];
    _provinceSpecies = [];
    _nearbyMode = NearbyMode.recent;
    _tideResult = null;
    _editingHistory = false;
    _editingOriginalSession = null;
    _hasUnsavedHistoryEdits = false;
    _editSnapshots.clear();

    double lat, lon;
    if (manualLat != null && manualLon != null) {
      // User picked location on map — skip GPS
      lat = manualLat;
      lon = manualLon;
      _position = null;
    } else {
      final pos = await LocationService.getCurrentPosition();
      _position = pos;
      lat = pos?.latitude ?? 0;
      lon = pos?.longitude ?? 0;
    }

    final session = SurveySession(
      startTime: DateTime.now(),
      latitude: lat,
      longitude: lon,
      customValues: customValues,
      surveyMode: mode.name,
    );
    final id = await DatabaseService.insertSurvey(session);
    final initialTrack =
        mode == SurveyMode.transect
            ? TransectTrackPoint(
              id: _newEventId('track'),
              time: session.startTime,
              latitude: lat,
              longitude: lon,
            )
            : null;
    _currentSession = SurveySession(
      id: id,
      startTime: session.startTime,
      latitude: lat,
      longitude: lon,
      customValues: Map.from(customValues),
      surveyMode: mode.name,
      activeTransectPointId: initialTrack?.id ?? '',
      transectTrack: initialTrack == null ? const [] : [initialTrack],
    );
    if (initialTrack != null) {
      await DatabaseService.updateSurvey(_currentSession!);
      await TransectEventLogService.append({
        'eventId': initialTrack.id,
        'sessionId': id,
        'type': 'track_point',
        ...initialTrack.toJson(),
      });
      _startTransectPositionStream();
    }
    _status = SurveyStatus.active;
    notifyListeners();

    if (lat != 0 || lon != 0) {
      _fetchNearbySpecies(lat, lon);
      _fetchTide(lat, lon);
      _fetchWeather(lat, lon);
    }
  }

  void setNearbyMode(NearbyMode mode) {
    if (_nearbyMode == mode) return;
    _nearbyMode = mode;
    if (isTransect) {
      notifyListeners();
      return;
    }
    final lat = _currentSession?.latitude ?? _position?.latitude;
    final lon = _currentSession?.longitude ?? _position?.longitude;
    if (lat == null || lon == null) {
      notifyListeners();
      return;
    }
    if (mode == NearbyMode.recent) {
      _fetchNearbySpecies(lat, lon, distKm: 30);
    } else if (mode == NearbyMode.localHistory) {
      _fetchNearbySpecies(lat, lon, distKm: 100);
    } else {
      fetchProvinceSpecies(lat, lon);
    }
    notifyListeners();
  }

  Future<void> _fetchNearbySpecies(
    double lat,
    double lng, {
    int distKm = 30,
  }) async {
    _loadingNearby = true;
    notifyListeners();
    try {
      final service = EbirdService(_ebirdApiKey);
      final freq = await service.getNearbySpeciesFrequency(
        lat: lat,
        lng: lng,
        distKm: distKm,
        back: 30,
      );
      _nearbySpecies =
          _allSpecies
              .where((s) => freq.containsKey(s.ebird))
              .map((s) => s.copyWith(ebirdFrequency: freq[s.ebird] ?? 0))
              .toList()
            ..sort((a, b) => b.ebirdFrequency.compareTo(a.ebirdFrequency));
      for (final ns in _nearbySpecies) {
        final original = _allSpecies.firstWhere(
          (s) => s.id == ns.id,
          orElse: () => ns,
        );
        ns.count = original.count;
      }
    } catch (e) {
      _error = 'eBird加载失败: $e';
    }
    _loadingNearby = false;
    notifyListeners();
  }

  Future<void> _fetchTide(double lat, double lng) async {
    final service = TideService(
      source: _tideSource,
      chaoxi365Key: _chaoxi365Key,
      chaoxi365Endpoint: _chaoxi365Endpoint,
      stormglassKey: _stormglassKey,
      worldtidesKey: _worldtidesKey,
    );
    final result = await service.getCurrentTide(lat, lng);
    _tideResult = result;
    if (result != null && _currentSession != null) {
      _currentSession = _currentSession!.copyWith(
        tideHeight: () => result.height,
        tideUnit: () => result.unit,
        tideDirection:
            () =>
                result.direction.isNotEmpty
                    ? result.direction
                    : _currentSession!.tideDirection,
      );
      DatabaseService.updateSurvey(_currentSession!);
    }
    notifyListeners();
  }

  Future<void> _fetchWeather(double lat, double lon) async {
    final service = WeatherService(_qweatherKey);
    final result = await service.getCurrentWeather(lat, lon);
    if (result != null && _currentSession != null) {
      _currentSession = _currentSession!.copyWith(weather: () => result);
      DatabaseService.updateSurvey(_currentSession!);
      notifyListeners();
    }
  }

  void incrementCount(BirdSpecies species) {
    _recordEditSnapshot('${species.zh} 数量 +1');
    if (isTransect) {
      if (!_ensureActiveTransectPoint()) return;
      _applyTransectSpeciesDelta(species, 1);
      _saveCurrentSession();
      notifyListeners();
      return;
    }
    _setSpeciesTotal(species, _currentSpeciesTotal(species.ebird) + 1);
    _saveCurrentSession();
    notifyListeners();
  }

  void incrementSpeciesFieldOption(
    BirdSpecies species,
    String fieldId,
    String value,
  ) {
    if (_currentSession == null || value.isEmpty) return;
    _recordEditSnapshot('${species.zh} / $fieldId / $value +1');
    if (isTransect) {
      if (!_ensureActiveTransectPoint()) return;
      _applyTransectFieldDelta(species, 1, fieldId: fieldId, option: value);
      _saveCurrentSession();
      notifyListeners();
      return;
    }
    if (value == '其他') {
      _setSpeciesTotal(species, _currentSpeciesTotal(species.ebird) + 1);
    } else {
      final counts = _fieldOptionCountsFor(species.ebird, fieldId);
      counts[value] = (counts[value] ?? 0) + 1;
      _ensureSpeciesTotalCoversAllocated(species, fieldId);
    }
    _saveCurrentSession();
    notifyListeners();
  }

  void setSpeciesFieldOptionCount(
    BirdSpecies species,
    String fieldId,
    String value,
    int count,
  ) {
    if (_currentSession == null || value.isEmpty) return;
    final old = getSpeciesFieldCounts(species.ebird, fieldId)[value] ?? 0;
    _recordEditSnapshot('${species.zh} / $fieldId / $value：$old -> $count');
    final safeCount = count < 0 ? 0 : count;
    if (isTransect) {
      if (safeCount > 0 && !_ensureActiveTransectPoint()) return;
      _applyTransectFieldDelta(
        species,
        safeCount - old,
        fieldId: fieldId,
        option: value,
      );
      if (safeCount == 0) {
        _removeTransectCurrentFieldEvents(
          species.ebird,
          type: 'field_count',
          fieldId: fieldId,
          option: value,
        );
      }
      _saveCurrentSession();
      notifyListeners();
      return;
    }
    if (value == '其他') {
      final allocated = _allocatedFieldCount(species.ebird, fieldId);
      _setSpeciesTotal(species, allocated + safeCount);
    } else {
      final counts = _fieldOptionCountsFor(species.ebird, fieldId);
      if (safeCount > 0) {
        counts[value] = safeCount;
      } else {
        counts.remove(value);
      }
      _ensureSpeciesTotalCoversAllocated(species, fieldId);
    }
    _saveCurrentSession();
    notifyListeners();
  }

  void incrementNestedSpeciesFieldOption(
    BirdSpecies species,
    String fieldId,
    String parent,
    String child,
  ) {
    if (_currentSession == null || parent.isEmpty || child.isEmpty) return;
    _recordEditSnapshot('${species.zh} / $parent / $child +1');
    if (isTransect) {
      if (!_ensureActiveTransectPoint()) return;
      _applyTransectFieldDelta(
        species,
        1,
        type: 'nested_field_count',
        fieldId: fieldId,
        parentOption: parent,
        childOption: child,
      );
      _saveCurrentSession();
      notifyListeners();
      return;
    }
    final counts = _nestedFieldCountsFor(species.ebird, fieldId, parent);
    counts[child] = (counts[child] ?? 0) + 1;
    _ensureSpeciesTotalCoversNestedAllocated(species, fieldId);
    _saveCurrentSession();
    notifyListeners();
  }

  void setNestedSpeciesFieldOptionCount(
    BirdSpecies species,
    String fieldId,
    String parent,
    String child,
    int count,
  ) {
    if (_currentSession == null || parent.isEmpty || child.isEmpty) return;
    final old =
        _currentSession?.nestedSpeciesFieldCounts[species
            .ebird]?[fieldId]?[parent]?[child] ??
        0;
    _recordEditSnapshot('${species.zh} / $parent / $child：$old -> $count');
    final safeCount = count < 0 ? 0 : count;
    if (isTransect) {
      if (safeCount > 0 && !_ensureActiveTransectPoint()) return;
      _applyTransectFieldDelta(
        species,
        safeCount - old,
        type: 'nested_field_count',
        fieldId: fieldId,
        parentOption: parent,
        childOption: child,
      );
      if (safeCount == 0) {
        _removeTransectCurrentFieldEvents(
          species.ebird,
          type: 'nested_field_count',
          fieldId: fieldId,
          parentOption: parent,
          childOption: child,
        );
      }
      _saveCurrentSession();
      notifyListeners();
      return;
    }
    final counts = _nestedFieldCountsFor(species.ebird, fieldId, parent);
    if (safeCount > 0) {
      counts[child] = safeCount;
    } else {
      counts.remove(child);
    }
    _ensureSpeciesTotalCoversNestedAllocated(species, fieldId);
    _saveCurrentSession();
    notifyListeners();
  }

  void setCount(BirdSpecies species, int value) {
    final old =
        isTransect
            ? _currentTransectSpeciesTotal(species.ebird)
            : _currentSpeciesTotal(species.ebird);
    _recordEditSnapshot('${species.zh} 数量：$old -> $value');
    if (isTransect) {
      final safeValue = value < 0 ? 0 : value;
      if (safeValue > 0 && !_ensureActiveTransectPoint()) return;
      if (safeValue == 0) {
        _clearTransectCurrentSpecies(species);
      } else {
        _applyTransectSpeciesDelta(species, safeValue - old);
      }
      _saveCurrentSession();
      notifyListeners();
      return;
    }
    if (value <= 0) {
      _removeSpeciesEntries(species.ebird);
    } else {
      _setSpeciesTotal(species, value);
    }
    _saveCurrentSession();
    notifyListeners();
  }

  void decrementCount(BirdSpecies species) {
    _recordEditSnapshot('${species.zh} 数量 -1');
    if (isTransect) {
      final next = _currentTransectSpeciesTotal(species.ebird) - 1;
      if (next <= 0) {
        _clearTransectCurrentSpecies(species);
      } else {
        _applyTransectSpeciesDelta(species, -1);
      }
      _saveCurrentSession();
      notifyListeners();
      return;
    }
    final next = _currentSpeciesTotal(species.ebird) - 1;
    if (next <= 0) {
      _removeSpeciesEntries(species.ebird);
    } else {
      _setSpeciesTotal(species, next);
    }
    _saveCurrentSession();
    notifyListeners();
  }

  void setSpeciesNote(String ebirdCode, String note) {
    if (_currentSession == null) return;
    _recordEditSnapshot('$ebirdCode 备注修改');
    final observationKey = _activeKeyFor(ebirdCode);
    if (note.isEmpty) {
      _currentSession!.speciesNotes.remove(observationKey);
    } else {
      _currentSession!.speciesNotes[observationKey] = note;
    }
    _appendTransectLog({'type': 'note', 'ebirdCode': ebirdCode, 'note': note});
    _saveCurrentSession();
    notifyListeners();
  }

  String getSpeciesNote(String ebirdCode) =>
      _currentSession?.speciesNotes[_activeKeyFor(ebirdCode)] ?? '';

  void _saveCurrentSession() {
    if (_currentSession == null) return;
    if (_editingHistory) {
      _hasUnsavedHistoryEdits = true;
      return;
    }
    DatabaseService.updateSurvey(_currentSession!);
  }

  Future<void> endSurvey({String notes = ''}) async {
    if (_currentSession == null) return;
    _status = SurveyStatus.saving;
    notifyListeners();
    final ended = _currentSession!.copyWith(
      endTime: () => DateTime.now(),
      notes: notes,
    );
    await DatabaseService.updateSurvey(ended);

    // Persist recorded species so next session shows them first
    final recordedCodes =
        ended.observations.keys
            .map(SurveySession.speciesCodeForKey)
            .toSet()
            .toList();
    if (recordedCodes.isNotEmpty) {
      _recentEbirdCodes = recordedCodes.toSet();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('recent_ebird_codes', jsonEncode(recordedCodes));
    }

    _currentSession = null;
    _stopTransectPositionStream();
    _status = SurveyStatus.idle;
    _editingHistory = false;
    _editingOriginalSession = null;
    _hasUnsavedHistoryEdits = false;
    _editSnapshots.clear();
    _resetCounts();
    _nearbySpecies = [];
    _tideResult = null;
    await _loadHistory();
    notifyListeners();
  }

  /// Reopen a completed survey so the user can add more observations.
  /// The session's endTime is cleared and counts are restored from its observations.
  Future<void> resumeSurvey(SurveySession session) async {
    _editingOriginalSession = session.copyWith();
    _currentSession = session.copyWith();
    if (_currentSession?.surveyMode == 'transect') {
      _startTransectPositionStream();
    }
    // Restore counts into the species list
    _restoreSpeciesListCounts(session);
    _restoreActiveObservationKeys();
    _editingHistory = true;
    _hasUnsavedHistoryEdits = false;
    _editSnapshots.clear();
    _status = SurveyStatus.active;
    notifyListeners();
  }

  Future<void> saveEditedSurvey() async {
    final current = _currentSession;
    final original = _editingOriginalSession;
    if (!_editingHistory || current == null || current.id == null) return;
    if (original != null && original.id != null) {
      await DatabaseService.insertVersion(
        SurveyVersion(
          surveyId: original.id!,
          savedAt: DateTime.now(),
          summary:
              _editSnapshots.isEmpty ? '保存前版本' : _editSnapshots.last.summary,
          snapshot: original,
        ),
      );
    }
    await DatabaseService.updateSurvey(current);
    _stopTransectPositionStream();
    _editingOriginalSession = current.copyWith();
    _hasUnsavedHistoryEdits = false;
    _editSnapshots.clear();
    await _loadHistory();
    notifyListeners();
  }

  Future<void> cancelEditedSurvey() async {
    final original = _editingOriginalSession;
    _currentSession = null;
    _stopTransectPositionStream();
    _editingOriginalSession = null;
    _editingHistory = false;
    _hasUnsavedHistoryEdits = false;
    _editSnapshots.clear();
    if (original != null) _restoreSpeciesListCounts(original);
    _resetCounts();
    _status = SurveyStatus.idle;
    notifyListeners();
  }

  Future<List<SurveyVersion>> versionsForSurvey(int surveyId) =>
      DatabaseService.getVersions(surveyId);

  Future<void> restoreSurveyVersion(SurveyVersion version) async {
    final current = _history.firstWhere(
      (s) => s.id == version.surveyId,
      orElse: () => version.snapshot,
    );
    if (current.id != null) {
      await DatabaseService.insertVersion(
        SurveyVersion(
          surveyId: current.id!,
          savedAt: DateTime.now(),
          summary: '恢复版本前自动保存',
          snapshot: current,
        ),
      );
      await DatabaseService.updateSurvey(version.snapshot.copyWith());
      await _loadHistory();
      notifyListeners();
    }
  }

  Future<void> deleteSurvey(int id) async {
    await DatabaseService.deleteSurvey(id);
    await _loadHistory();
    notifyListeners();
  }

  Future<void> renameSurvey(int id, String title) async {
    final idx = _history.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final updated = _history[idx].copyWith(title: title.trim());
    await DatabaseService.updateSurvey(updated);
    await _loadHistory();
    notifyListeners();
  }

  Future<void> moveSurveyToFolder(int id, String folderId) async {
    final idx = _history.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final updated = _history[idx].copyWith(folderId: folderId);
    await DatabaseService.updateSurvey(updated);
    await _loadHistory();
    notifyListeners();
  }

  void setSearchQuery(String q) {
    _searchQuery = q;
    if (q.isEmpty) {
      _provinceSpecies = [];
      _nationalSpecies = [];
    }
    notifyListeners();
  }

  /// Add a species not in the master list to the current session.
  void addCustomSpecies(String zh, String en) {
    _recordEditSnapshot('添加自定义鸟种：$zh');
    final id = -DateTime.now().millisecondsSinceEpoch;
    final ebird = 'custom_${id.abs()}';
    final species = BirdSpecies(
      id: id,
      zh: zh,
      en: en.isEmpty ? zh : en,
      sci: '',
      family: '自定义',
      order: '',
      ebird: ebird,
      count: 1,
    );
    _allSpecies.insert(0, species);
    _currentSession?.observations[ebird] = 1;
    _currentSession?.speciesNames[ebird] = zh;
    _saveCurrentSession();
    notifyListeners();
  }

  void _resetCounts() {
    for (final s in _allSpecies) {
      s.count = 0;
    }
    _activeObservationKeys.clear();
  }

  int getCount(BirdSpecies species) {
    if (isTransect) return _currentTransectSpeciesTotal(species.ebird);
    final sessionTotal = _currentSpeciesTotal(species.ebird);
    if (sessionTotal > 0) return sessionTotal;
    return _allSpecies
        .firstWhere((s) => s.id == species.id, orElse: () => species)
        .count;
  }

  String _activeKeyFor(String ebirdCode) =>
      _activeObservationKeys[ebirdCode] ?? ebirdCode;

  void _setSpeciesTotal(BirdSpecies species, int total) {
    final session = _currentSession;
    if (session == null) return;
    final keys =
        session.observations.keys
            .where((k) => SurveySession.speciesCodeForKey(k) == species.ebird)
            .toList();
    for (final key in keys) {
      session.observations.remove(key);
      if (key != species.ebird) {
        session.speciesNames.remove(key);
        session.speciesNotes.remove(key);
        session.speciesFields.remove(key);
      }
    }
    if (total > 0) {
      session.observations[species.ebird] = total;
      session.speciesNames[species.ebird] = species.zh;
      _activeObservationKeys[species.ebird] = species.ebird;
    } else {
      session.speciesNames.remove(species.ebird);
      session.speciesNotes.remove(species.ebird);
      session.speciesFields.remove(species.ebird);
      session.speciesFieldCounts.remove(species.ebird);
      _activeObservationKeys.remove(species.ebird);
    }
    _setSpeciesListCount(species, total > 0 ? total : 0);
  }

  void _setSpeciesListCount(BirdSpecies species, int count) {
    final idx = _allSpecies.indexWhere((s) => s.id == species.id);
    if (idx >= 0) _allSpecies[idx].count = count;
    final nIdx = _nearbySpecies.indexWhere((s) => s.id == species.id);
    if (nIdx >= 0) _nearbySpecies[nIdx].count = count;
  }

  void _clearSpeciesListCount(String ebirdCode) {
    for (final list in [_allSpecies, _nearbySpecies, _provinceSpecies]) {
      for (final species in list.where((s) => s.ebird == ebirdCode)) {
        species.count = 0;
      }
    }
    _recordedOrder.remove(ebirdCode);
  }

  TransectTrackPoint? _activeTransectPoint() {
    final session = _currentSession;
    if (session == null || session.surveyMode != 'transect') return null;
    final id = activeTransectPointId;
    if (id.isEmpty) return null;
    for (final point in session.transectTrack.reversed) {
      if (point.id == id) return point;
    }
    return null;
  }

  int _currentTransectSpeciesTotal(String ebirdCode) {
    final session = _currentSession;
    final pointId = activeTransectPointId;
    if (session == null || pointId.isEmpty) return 0;
    return session.observationEvents
        .where(
          (e) =>
              (e.type == 'species_count' ||
                  e.type == 'field_count' ||
                  e.type == 'nested_field_count') &&
              e.trackPointId == pointId &&
              e.ebirdCode == ebirdCode,
        )
        .fold(0, (sum, e) => sum + e.delta);
  }

  Map<String, int> _currentTransectFieldCounts(
    String ebirdCode, {
    required String type,
    required String fieldId,
  }) {
    final session = _currentSession;
    final pointId = activeTransectPointId;
    if (session == null || pointId.isEmpty) return {};
    final result = <String, int>{};
    for (final e in session.observationEvents.where(
      (e) =>
          e.type == type &&
          e.trackPointId == pointId &&
          e.ebirdCode == ebirdCode &&
          e.fieldId == fieldId,
    )) {
      final key = e.option;
      if (key.isEmpty) continue;
      final next = (result[key] ?? 0) + e.delta;
      if (next > 0) {
        result[key] = next;
      } else {
        result.remove(key);
      }
    }
    return result;
  }

  Map<String, Map<String, int>> _currentTransectNestedCounts(
    String ebirdCode,
    String fieldId,
  ) {
    final session = _currentSession;
    final pointId = activeTransectPointId;
    if (session == null || pointId.isEmpty) return {};
    final result = <String, Map<String, int>>{};
    for (final e in session.observationEvents.where(
      (e) =>
          e.type == 'nested_field_count' &&
          e.trackPointId == pointId &&
          e.ebirdCode == ebirdCode &&
          e.fieldId == fieldId,
    )) {
      if (e.parentOption.isEmpty || e.childOption.isEmpty) continue;
      result.putIfAbsent(e.parentOption, () => {});
      final children = result[e.parentOption]!;
      final next = (children[e.childOption] ?? 0) + e.delta;
      if (next > 0) {
        children[e.childOption] = next;
      } else {
        children.remove(e.childOption);
      }
    }
    result.removeWhere((_, children) => children.isEmpty);
    return result;
  }

  void _applyTransectSpeciesDelta(BirdSpecies species, int delta) {
    if (delta == 0) return;
    final session = _currentSession;
    final point = _activeTransectPoint();
    if (session == null || point == null) return;
    final aggregate = _currentSpeciesTotal(species.ebird);
    final nextAggregate = aggregate + delta;
    if (nextAggregate > 0) {
      session.observations[species.ebird] = nextAggregate;
      session.speciesNames[species.ebird] = species.zh;
      _activeObservationKeys[species.ebird] = species.ebird;
    } else {
      _removeSpeciesEntries(species.ebird);
      return;
    }
    _recordTransectSpeciesEvent(species, delta: delta, type: 'species_count');
    _setSpeciesListCount(species, _currentTransectSpeciesTotal(species.ebird));
  }

  void _applyTransectFieldDelta(
    BirdSpecies species,
    int delta, {
    String type = 'field_count',
    required String fieldId,
    String option = '',
    String parentOption = '',
    String childOption = '',
  }) {
    if (delta == 0) return;
    final session = _currentSession;
    final point = _activeTransectPoint();
    if (session == null || point == null) return;
    if (type == 'nested_field_count') {
      final counts = _nestedFieldCountsFor(
        species.ebird,
        fieldId,
        parentOption,
      );
      final next = (counts[childOption] ?? 0) + delta;
      if (next > 0) {
        counts[childOption] = next;
      } else {
        counts.remove(childOption);
      }
    } else {
      final counts = _fieldOptionCountsFor(species.ebird, fieldId);
      final next = (counts[option] ?? 0) + delta;
      if (next > 0) {
        counts[option] = next;
      } else {
        counts.remove(option);
      }
    }
    final aggregate = _currentSpeciesTotal(species.ebird);
    final nextAggregate = aggregate + delta;
    if (nextAggregate > 0) {
      session.observations[species.ebird] = nextAggregate;
      session.speciesNames[species.ebird] = species.zh;
      _activeObservationKeys[species.ebird] = species.ebird;
    } else {
      session.observations.remove(species.ebird);
      session.speciesNames.remove(species.ebird);
    }
    _recordTransectSpeciesEvent(
      species,
      delta: delta,
      type: type,
      fieldId: fieldId,
      option: option,
      parentOption: parentOption,
      childOption: childOption,
    );
    _setSpeciesListCount(species, _currentTransectSpeciesTotal(species.ebird));
  }

  void _removeTransectCurrentFieldEvents(
    String ebirdCode, {
    required String type,
    required String fieldId,
    String option = '',
    String parentOption = '',
    String childOption = '',
  }) {
    final session = _currentSession;
    final pointId = activeTransectPointId;
    if (session == null || pointId.isEmpty) return;
    session.observationEvents.removeWhere(
      (e) =>
          e.trackPointId == pointId &&
          e.ebirdCode == ebirdCode &&
          e.type == type &&
          e.fieldId == fieldId &&
          (option.isEmpty || e.option == option) &&
          (parentOption.isEmpty || e.parentOption == parentOption) &&
          (childOption.isEmpty || e.childOption == childOption),
    );
  }

  void _clearTransectCurrentSpecies(BirdSpecies species) {
    final session = _currentSession;
    final pointId = activeTransectPointId;
    if (session == null || pointId.isEmpty) return;
    final old = _currentTransectSpeciesTotal(species.ebird);
    if (old <= 0) {
      _setSpeciesListCount(species, 0);
      _recordedOrder.remove(species.ebird);
      return;
    }
    session.observationEvents.removeWhere(
      (e) => e.trackPointId == pointId && e.ebirdCode == species.ebird,
    );
    final aggregate = _currentSpeciesTotal(species.ebird) - old;
    if (aggregate > 0) {
      session.observations[species.ebird] = aggregate;
      session.speciesNames[species.ebird] = species.zh;
    } else {
      session.observations.remove(species.ebird);
      session.speciesNames.remove(species.ebird);
      session.speciesNotes.remove(species.ebird);
      session.speciesFields.remove(species.ebird);
      session.speciesFieldCounts.remove(species.ebird);
      session.nestedSpeciesFieldCounts.remove(species.ebird);
      _activeObservationKeys.remove(species.ebird);
    }
    _setSpeciesListCount(species, 0);
    _recordedOrder.remove(species.ebird);
    _appendTransectLog({
      'type': 'species_count',
      'ebirdCode': species.ebird,
      'speciesName': species.zh,
      'delta': -old,
      'countAfter': 0,
      'trackPointId': pointId,
    });
  }

  String _newEventId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}';

  void _recordTransectSpeciesEvent(
    BirdSpecies species, {
    required int delta,
    String type = 'species_count',
    String fieldId = '',
    String option = '',
    String parentOption = '',
    String childOption = '',
  }) {
    final session = _currentSession;
    if (session == null || !isTransect || delta == 0) return;
    final point = _activeTransectPoint();
    if (point == null) return;
    final event = SpeciesObservationEvent(
      eventId: _newEventId(type),
      time: point.time,
      latitude: point.latitude,
      longitude: point.longitude,
      ebirdCode: species.ebird,
      speciesName: species.zh,
      delta: delta,
      countAfter: _currentTransectSpeciesTotal(species.ebird) + delta,
      type: type,
      trackPointId: point.id,
      fieldId: fieldId,
      option: option,
      parentOption: parentOption,
      childOption: childOption,
    );
    session.observationEvents.add(event);
    _appendTransectLog({
      'eventId': event.eventId,
      'sessionId': session.id,
      ...event.toJson(),
    });
  }

  void _appendTransectLog(Map<String, dynamic> event) {
    final session = _currentSession;
    if (session == null || !isTransect) return;
    final now = DateTime.now();
    unawaited(
      TransectEventLogService.append({
        'eventId': event['eventId']?.toString() ?? _newEventId('event'),
        'sessionId': session.id,
        'time': event['time']?.toString() ?? now.toIso8601String(),
        'latitude':
            event['latitude'] ?? _position?.latitude ?? session.latitude,
        'longitude':
            event['longitude'] ?? _position?.longitude ?? session.longitude,
        ...event,
      }),
    );
  }

  Map<String, int> _fieldOptionCountsFor(String ebirdCode, String fieldId) {
    final session = _currentSession!;
    session.speciesFieldCounts.putIfAbsent(ebirdCode, () => {});
    session.speciesFieldCounts[ebirdCode]!.putIfAbsent(fieldId, () => {});
    return session.speciesFieldCounts[ebirdCode]![fieldId]!;
  }

  Map<String, int> _nestedFieldCountsFor(
    String ebirdCode,
    String fieldId,
    String parent,
  ) {
    final session = _currentSession!;
    session.nestedSpeciesFieldCounts.putIfAbsent(ebirdCode, () => {});
    session.nestedSpeciesFieldCounts[ebirdCode]!.putIfAbsent(fieldId, () => {});
    session.nestedSpeciesFieldCounts[ebirdCode]![fieldId]!.putIfAbsent(
      parent,
      () => {},
    );
    return session.nestedSpeciesFieldCounts[ebirdCode]![fieldId]![parent]!;
  }

  int _allocatedFieldCount(String ebirdCode, String fieldId) {
    final counts = _currentSession?.speciesFieldCounts[ebirdCode]?[fieldId];
    if (counts == null) return 0;
    return counts.entries
        .where((e) => e.key != '其他')
        .fold(0, (sum, e) => sum + e.value);
  }

  void _ensureSpeciesTotalCoversAllocated(BirdSpecies species, String fieldId) {
    final allocated = _allocatedFieldCount(species.ebird, fieldId);
    final total = _currentSpeciesTotal(species.ebird);
    if (total <= 0) {
      _setSpeciesTotal(species, allocated);
    } else if (allocated > total) {
      _setSpeciesTotal(species, allocated);
    } else {
      _setSpeciesListCount(species, total);
      _currentSession?.speciesNames[species.ebird] = species.zh;
    }
  }

  int _allocatedNestedFieldCount(String ebirdCode, String fieldId) {
    final parents =
        _currentSession?.nestedSpeciesFieldCounts[ebirdCode]?[fieldId];
    if (parents == null) return 0;
    return parents.values.fold(
      0,
      (sum, children) =>
          sum + children.values.fold(0, (childSum, value) => childSum + value),
    );
  }

  void _ensureSpeciesTotalCoversNestedAllocated(
    BirdSpecies species,
    String fieldId,
  ) {
    final allocated = _allocatedNestedFieldCount(species.ebird, fieldId);
    final total = _currentSpeciesTotal(species.ebird);
    if (total <= 0 || allocated > total) {
      _setSpeciesTotal(species, allocated);
    } else {
      _setSpeciesListCount(species, total);
      _currentSession?.speciesNames[species.ebird] = species.zh;
    }
  }

  String _keyForFieldValue(String ebirdCode, String fieldId, String value) {
    final session = _currentSession;
    if (session == null || value.isEmpty) return _activeKeyFor(ebirdCode);

    for (final e in session.speciesFields.entries) {
      if (SurveySession.speciesCodeForKey(e.key) == ebirdCode &&
          e.value[fieldId] == value) {
        return e.key;
      }
    }

    final activeKey = _activeKeyFor(ebirdCode);
    final activeFields = session.speciesFields[activeKey] ?? {};
    final activeCount = session.observations[activeKey] ?? 0;
    final currentValue = activeFields[fieldId] ?? '';
    if (activeCount == 0 || currentValue.isEmpty || currentValue == value) {
      return activeKey;
    }
    return SurveySession.newEntryKey(ebirdCode);
  }

  int _currentSpeciesTotal(String ebirdCode) {
    final session = _currentSession;
    if (session == null) return 0;
    var total = 0;
    for (final e in session.observations.entries) {
      if (SurveySession.speciesCodeForKey(e.key) == ebirdCode && e.value > 0) {
        total += e.value;
      }
    }
    return total;
  }

  void _removeSpeciesEntries(String ebirdCode) {
    final session = _currentSession;
    if (session == null) return;
    final keys =
        session.observations.keys
            .where((k) => SurveySession.speciesCodeForKey(k) == ebirdCode)
            .toList();
    for (final key in keys) {
      session.observations.remove(key);
      session.speciesNames.remove(key);
      session.speciesNotes.remove(key);
      session.speciesFields.remove(key);
    }
    session.speciesFieldCounts.remove(ebirdCode);
    session.nestedSpeciesFieldCounts.remove(ebirdCode);
    session.observationEvents.removeWhere((e) => e.ebirdCode == ebirdCode);
    _activeObservationKeys.remove(ebirdCode);
    _clearSpeciesListCount(ebirdCode);
  }

  void _restoreActiveObservationKeys() {
    _activeObservationKeys.clear();
    final session = _currentSession;
    if (session == null) return;
    for (final e in session.observations.entries) {
      if (e.value <= 0) continue;
      _activeObservationKeys[SurveySession.speciesCodeForKey(e.key)] = e.key;
    }
  }

  void _recordEditSnapshot(String summary) {
    final session = _currentSession;
    if (session == null) return;
    _editSnapshots.add(_EditSnapshot(session.copyWith(), summary));
    if (_editSnapshots.length > 10) {
      _editSnapshots.removeAt(0);
    }
  }

  bool undoLastEdit() {
    if (_editSnapshots.isEmpty) return false;
    final snapshot = _editSnapshots.removeLast();
    _restoreSnapshot(snapshot.session);
    notifyListeners();
    return true;
  }

  bool undoToEditIndex(int index) {
    if (index < 0 || index >= _editSnapshots.length) return false;
    final snapshot = _editSnapshots[index];
    _editSnapshots.removeRange(index, _editSnapshots.length);
    _restoreSnapshot(snapshot.session);
    notifyListeners();
    return true;
  }

  void _restoreSnapshot(SurveySession snapshot) {
    _currentSession = snapshot.copyWith();
    _restoreSpeciesListCounts(snapshot);
    _restoreActiveObservationKeys();
    _saveCurrentSession();
  }

  void _restoreSpeciesListCounts(SurveySession session) {
    final totals =
        session.surveyMode == 'transect'
            ? _transectPointTotals(session)
            : session.speciesTotals();
    for (final s in _allSpecies) {
      s.count = totals[s.ebird] ?? 0;
    }
    for (final s in _nearbySpecies) {
      s.count = totals[s.ebird] ?? 0;
    }
  }

  Map<String, int> _transectPointTotals(SurveySession session) {
    final pointId = session.activeTransectPointId;
    if (pointId.isEmpty) return {};
    final totals = <String, int>{};
    for (final event in session.observationEvents.where(
      (e) =>
          (e.type == 'species_count' ||
              e.type == 'field_count' ||
              e.type == 'nested_field_count') &&
          e.trackPointId == pointId,
    )) {
      final next = (totals[event.ebirdCode] ?? 0) + event.delta;
      if (next > 0) {
        totals[event.ebirdCode] = next;
      } else {
        totals.remove(event.ebirdCode);
      }
    }
    return totals;
  }

  @override
  void dispose() {
    _stopTransectPositionStream();
    super.dispose();
  }
}
