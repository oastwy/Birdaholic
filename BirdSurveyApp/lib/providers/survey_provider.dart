import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bird_species.dart';
import '../models/custom_field.dart';
import '../models/survey_point.dart';
import '../models/survey_session.dart';
import '../services/database_service.dart';
import '../services/ebird_service.dart';
import '../services/location_service.dart';
import '../services/survey_point_service.dart';
import '../services/tide_service.dart';

enum SurveyStatus { idle, active, saving }

class SurveyProvider extends ChangeNotifier {
  List<BirdSpecies> _allSpecies = [];
  List<BirdSpecies> _nearbySpecies = [];
  List<SurveySession> _history = [];
  SurveySession? _currentSession;
  SurveyStatus _status = SurveyStatus.idle;
  Position? _position;
  TideResult? _tideResult;
  String _searchQuery = '';
  bool _loadingNearby = false;
  int _nearbyDays = 30;
  String? _error;

  // Settings
  String _ebirdApiKey = '';
  String _chaoxi365Key = '';
  String _chaoxi365Endpoint = TideService.defaultChaoxi365Endpoint;
  String _stormglassKey = '';
  String _worldtidesKey = '';
  TideSource _tideSource = TideSource.local;
  List<CustomField> _customFields = [];
  List<SurveyPoint> _surveyPoints = [];
  String _tiandituKey = '';

  // Per-species custom field definitions
  List<CustomField> _speciesFieldDefs = [];

  // Recent species (from last completed survey)
  Set<String> _recentEbirdCodes = {};
  final Map<String, String> _activeObservationKeys = {};

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
  int get nearbyDays => _nearbyDays;
  String? get error => _error;
  String get ebirdApiKey => _ebirdApiKey;
  String get chaoxi365Key => _chaoxi365Key;
  String get chaoxi365Endpoint => _chaoxi365Endpoint;
  String get stormglassKey => _stormglassKey;
  String get worldtidesKey => _worldtidesKey;
  TideSource get tideSource => _tideSource;
  List<CustomField> get customFields => _customFields;
  List<SurveyPoint> get surveyPoints => _surveyPoints;
  String get tiandituKey => _tiandituKey;

  List<CustomField> get speciesFieldDefs => _speciesFieldDefs;
  bool get setupDone => _setupDone;
  String get searchQuery => _searchQuery;
  List<BirdSpecies> get provinceSpecies => _provinceSpecies;
  List<BirdSpecies> get nationalSpecies => _nationalSpecies;
  bool get loadingProvince => _loadingProvince;
  bool get loadingNational => _loadingNational;
  String get provinceRegionName => _provinceRegionName;

  List<BirdSpecies> get filteredNearbySpecies {
    if (_searchQuery.isEmpty) return _nearbySpecies;
    return _applyFilter(_nearbySpecies, _searchQuery);
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

  List<BirdSpecies> get recordedSpecies =>
      _allSpecies.where((s) => s.count > 0).toList()
        ..sort((a, b) => b.count.compareTo(a.count));

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
  }

  Future<void> saveSettings({
    required String ebird,
    required String chaoxi365,
    required String chaoxi365Endpoint,
    required String stormglass,
    required String worldtides,
    required String tianditu,
    required TideSource tideSource,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ebird_api_key', ebird);
    await prefs.setString('chaoxi365_key', chaoxi365);
    await prefs.setString('chaoxi365_endpoint', chaoxi365Endpoint);
    await prefs.setString('stormglass_key', stormglass);
    await prefs.setString('worldtides_key', worldtides);
    await prefs.setString('tianditu_key', tianditu);
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
    _tideSource = tideSource;
    notifyListeners();
  }

  // ── Survey Points ──────────────────────────────────────────────────────────

  Future<void> retryGps() async {
    final pos = await LocationService.getCurrentPosition();
    _position = pos;
    notifyListeners();
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

  /// Returns points sorted by distance from [lat],[lon], attaches distanceM.
  List<SurveyPoint> nearbyPoints(double lat, double lon, {int maxCount = 5}) {
    for (final p in _surveyPoints) {
      p.distanceM = p.distanceTo(lat, lon);
    }
    final sorted = List<SurveyPoint>.from(_surveyPoints)
      ..sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));
    return sorted.take(maxCount).toList();
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
    notifyListeners();
  }

  String getSpeciesFieldValue(String ebirdCode, String fieldId) =>
      _currentSession?.speciesFields[_activeKeyFor(ebirdCode)]?[fieldId] ?? '';

  void setSpeciesFieldValue(String ebirdCode, String fieldId, String value) {
    if (_currentSession == null) return;
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

  Future<void> startSurvey(
    Map<String, String> customValues, {
    double? manualLat,
    double? manualLon,
  }) async {
    _error = null;
    _resetCounts();
    _nearbySpecies = [];
    _tideResult = null;

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
    );
    final id = await DatabaseService.insertSurvey(session);
    _currentSession = SurveySession(
      id: id,
      startTime: session.startTime,
      latitude: lat,
      longitude: lon,
      customValues: Map.from(customValues),
    );
    _status = SurveyStatus.active;
    notifyListeners();

    if (lat != 0 || lon != 0) {
      _fetchNearbySpecies(lat, lon);
      _fetchTide(lat, lon);
    }
  }

  void setNearbyDays(int days) {
    if (_nearbyDays == days) return;
    _nearbyDays = days;
    final pos = _position;
    if (pos != null) _fetchNearbySpecies(pos.latitude, pos.longitude);
  }

  Future<void> _fetchNearbySpecies(double lat, double lng) async {
    _loadingNearby = true;
    notifyListeners();
    try {
      final service = EbirdService(_ebirdApiKey);
      final freq = await service.getNearbySpeciesFrequency(
        lat: lat,
        lng: lng,
        back: _nearbyDays,
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
      _currentSession = SurveySession(
        id: _currentSession!.id,
        startTime: _currentSession!.startTime,
        latitude: _currentSession!.latitude,
        longitude: _currentSession!.longitude,
        tideHeight: result.height,
        tideUnit: result.unit,
        observations: Map.from(_currentSession!.observations),
        speciesNames: Map.from(_currentSession!.speciesNames),
        customValues: Map.from(_currentSession!.customValues),
        speciesNotes: Map.from(_currentSession!.speciesNotes),
        speciesFields: {
          for (final e in _currentSession!.speciesFields.entries)
            e.key: Map.from(e.value),
        },
        speciesFieldCounts: _copyFieldCounts(
          _currentSession!.speciesFieldCounts,
        ),
        notes: _currentSession!.notes,
      );
      DatabaseService.updateSurvey(_currentSession!);
    }
    notifyListeners();
  }

  void incrementCount(BirdSpecies species) {
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
    final safeCount = count < 0 ? 0 : count;
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

  void setCount(BirdSpecies species, int value) {
    if (value <= 0) {
      _removeSpeciesEntries(species.ebird);
    } else {
      _setSpeciesTotal(species, value);
    }
    _saveCurrentSession();
    notifyListeners();
  }

  void decrementCount(BirdSpecies species) {
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
    final observationKey = _activeKeyFor(ebirdCode);
    if (note.isEmpty) {
      _currentSession!.speciesNotes.remove(observationKey);
    } else {
      _currentSession!.speciesNotes[observationKey] = note;
    }
    _saveCurrentSession();
    notifyListeners();
  }

  String getSpeciesNote(String ebirdCode) =>
      _currentSession?.speciesNotes[_activeKeyFor(ebirdCode)] ?? '';

  void _saveCurrentSession() {
    if (_currentSession != null) DatabaseService.updateSurvey(_currentSession!);
  }

  Future<void> endSurvey({String notes = ''}) async {
    if (_currentSession == null) return;
    _status = SurveyStatus.saving;
    notifyListeners();
    final ended = SurveySession(
      id: _currentSession!.id,
      startTime: _currentSession!.startTime,
      endTime: DateTime.now(),
      latitude: _currentSession!.latitude,
      longitude: _currentSession!.longitude,
      tideHeight: _currentSession!.tideHeight,
      tideUnit: _currentSession!.tideUnit,
      observations: Map.from(_currentSession!.observations),
      speciesNames: Map.from(_currentSession!.speciesNames),
      customValues: Map.from(_currentSession!.customValues),
      speciesNotes: Map.from(_currentSession!.speciesNotes),
      speciesFields: {
        for (final e in _currentSession!.speciesFields.entries)
          e.key: Map.from(e.value),
      },
      speciesFieldCounts: _copyFieldCounts(_currentSession!.speciesFieldCounts),
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
    _status = SurveyStatus.idle;
    _resetCounts();
    _nearbySpecies = [];
    _tideResult = null;
    await _loadHistory();
    notifyListeners();
  }

  /// Reopen a completed survey so the user can add more observations.
  /// The session's endTime is cleared and counts are restored from its observations.
  Future<void> resumeSurvey(SurveySession session) async {
    _currentSession = SurveySession(
      id: session.id,
      startTime: session.startTime,
      endTime: null, // mark as active again
      latitude: session.latitude,
      longitude: session.longitude,
      tideHeight: session.tideHeight,
      tideUnit: session.tideUnit,
      observations: Map.from(session.observations),
      speciesNames: Map.from(session.speciesNames),
      customValues: Map.from(session.customValues),
      speciesNotes: Map.from(session.speciesNotes),
      speciesFields: {
        for (final e in session.speciesFields.entries) e.key: Map.from(e.value),
      },
      speciesFieldCounts: _copyFieldCounts(session.speciesFieldCounts),
      notes: session.notes,
    );
    // Restore counts into the species list
    for (final s in _allSpecies) {
      final c = session.speciesTotals()[s.ebird] ?? 0;
      s.count = c;
    }
    _restoreActiveObservationKeys();
    _status = SurveyStatus.active;
    notifyListeners();
  }

  Future<void> deleteSurvey(int id) async {
    await DatabaseService.deleteSurvey(id);
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

  Map<String, int> _fieldOptionCountsFor(String ebirdCode, String fieldId) {
    final session = _currentSession!;
    session.speciesFieldCounts.putIfAbsent(ebirdCode, () => {});
    session.speciesFieldCounts[ebirdCode]!.putIfAbsent(fieldId, () => {});
    return session.speciesFieldCounts[ebirdCode]![fieldId]!;
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

  Map<String, Map<String, Map<String, int>>> _copyFieldCounts(
    Map<String, Map<String, Map<String, int>>> source,
  ) {
    return {
      for (final speciesEntry in source.entries)
        speciesEntry.key: {
          for (final fieldEntry in speciesEntry.value.entries)
            fieldEntry.key: Map<String, int>.from(fieldEntry.value),
        },
    };
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
    _activeObservationKeys.remove(ebirdCode);
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
}
