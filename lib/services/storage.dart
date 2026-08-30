import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地存储服务
/// 管理收藏、学习进度和不熟悉列表
class StorageService {
  static const _favoritesKey = 'favorites';
  static const _statsKey = 'learning_stats';
  static const _speciesMasteryKey = 'species_mastery';
  static const _xenoCantoApiKey = 'xeno_canto_api_key';
  static const _eBirdApiKey = 'ebird_api_key';
  static const _adminUploadTokenKey = 'admin_upload_token';
  static const _userRoleKey = 'upload_user_role'; // admin / beta / ''
  static const _userNameKey = 'upload_user_name';
  static const _contributorKey = 'upload_contributor';
  static const _uploadLocationKey = 'upload_location';
  static const _consentAcceptedKey = 'consent_accepted_version';
  static const _feedbackJournalKey = 'feedback_journal';
  static const _feedbackClientIdKey = 'feedback_client_id';
  static const _speciesNotesKey = 'species_identification_notes';
  static const _checkInDatesKey = 'study_check_in_dates';
  static const _flashcardGroupSizeKey = 'flashcard_group_size';
  static const _flashcardStartFullscreenKey = 'flashcard_start_fullscreen';
  static const _lastFlashcardFilterKey = 'flashcard_last_filter';
  static const _lastFlashcardSetupKey = 'flashcard_last_setup_v1';
  static const _quizNameModesKey = 'quiz_name_modes';
  static const _newUserGuideDismissedKey = 'new_user_guide_dismissed';
  static const _dismissedUpdateVersionKey = 'dismissed_update_version';
  static const _ebirdFilterLabelKey = 'ebird_filter_label';
  static const _ebirdFilterSciKey = 'ebird_filter_sci';
  static const _ebirdFilterRegionKey = 'ebird_filter_region';
  static const _ebirdFilterCoordsKey = 'ebird_filter_coords';
  static const _ebirdLocationHistoryKey = 'ebird_location_history';
  static const _lifeListKey = 'ebird_life_list';
  static const _appModeKey = 'app_mode'; // beginner / free / ''（未选）

  final SharedPreferences _prefs;
  // Android API 21+ compatible encrypted storage, backed by Android Keystore.
  // iOS values stay on this device and are available only while it is unlocked.
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );
  late String _xenoCantoApiKeyValue;
  late String _eBirdApiKeyValue;
  late String _adminUploadTokenValue;

  StorageService(this._prefs) {
    // Keep construction synchronous for the existing UI, then migrate these
    // values during app startup before any network request is made.
    _xenoCantoApiKeyValue = _prefs.getString(_xenoCantoApiKey) ?? '';
    _eBirdApiKeyValue = _prefs.getString(_eBirdApiKey) ?? '';
    _adminUploadTokenValue = _prefs.getString(_adminUploadTokenKey) ?? '';
  }

  bool get _usesPlatformSecureStorage => Platform.isAndroid || Platform.isIOS;

  /// Moves legacy plaintext credentials out of SharedPreferences. Desktop and
  /// OpenHarmony keep their existing storage path until a supported secure
  /// storage implementation is available there.
  Future<void> initializeSensitiveCredentials() async {
    if (!_usesPlatformSecureStorage) return;
    _xenoCantoApiKeyValue = await _readOrMigrateCredential(
      _xenoCantoApiKey,
      _xenoCantoApiKeyValue,
    );
    _eBirdApiKeyValue = await _readOrMigrateCredential(
      _eBirdApiKey,
      _eBirdApiKeyValue,
    );
    _adminUploadTokenValue = await _readOrMigrateCredential(
      _adminUploadTokenKey,
      _adminUploadTokenValue,
    );
  }

  Future<String> _readOrMigrateCredential(
    String key,
    String legacyValue,
  ) async {
    try {
      final secureValue = (await _secureStorage.read(key: key) ?? '').trim();
      if (secureValue.isNotEmpty) {
        if (legacyValue.isNotEmpty) await _prefs.remove(key);
        return secureValue;
      }
      if (legacyValue.isEmpty) return '';
      await _secureStorage.write(key: key, value: legacyValue);
      await _prefs.remove(key);
      return legacyValue;
    } catch (_) {
      // Do not strand a user who upgrades from a build that stored credentials
      // in preferences. A later successful startup can retry the migration.
      return legacyValue;
    }
  }

  Future<void> _setCredential(String key, String value) async {
    if (!_usesPlatformSecureStorage) {
      if (value.isEmpty) {
        await _prefs.remove(key);
      } else {
        await _prefs.setString(key, value);
      }
      return;
    }

    if (value.isEmpty) {
      await _secureStorage.delete(key: key);
    } else {
      await _secureStorage.write(key: key, value: value);
    }
    await _prefs.remove(key);
  }

  // ============ 收藏 ============

  /// 获取收藏的鸟种中文名列表
  Set<String> getFavorites() {
    final str = _prefs.getString(_favoritesKey);
    if (str == null || str.isEmpty) return {};
    try {
      final list = jsonDecode(str) as List<dynamic>;
      return list.cast<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  /// 切换收藏状态
  Future<bool> toggleFavorite(String cnName) async {
    final favs = getFavorites();
    if (favs.contains(cnName)) {
      favs.remove(cnName);
    } else {
      favs.add(cnName);
    }
    await _prefs.setString(_favoritesKey, jsonEncode(favs.toList()));
    return favs.contains(cnName);
  }

  /// 是否已收藏
  bool isFavorite(String cnName) => getFavorites().contains(cnName);

  // ============ 在线下载设置 ============

  String getXenoCantoApiKey() => _xenoCantoApiKeyValue;

  Future<void> setXenoCantoApiKey(String value) async {
    final normalized = value.trim();
    await _setCredential(_xenoCantoApiKey, normalized);
    _xenoCantoApiKeyValue = normalized;
  }

  String getEBirdApiKey() => _eBirdApiKeyValue;

  Future<void> setEBirdApiKey(String value) async {
    final normalized = value.trim();
    await _setCredential(_eBirdApiKey, normalized);
    _eBirdApiKeyValue = normalized;
  }

  // ── 整包下载断点续传：按包名持久化「打算下载的完整物种清单」，下载中断/重启后
  //    可在数据包管理里「继续下载」补齐剩余物种（createPack 幂等，已下的会跳过）。
  static const _pendingDlPrefix = 'pending_dl_';

  /// 保存某包的待下载意图（record 含 region/allowApiFallback/species:[SpeciesEntry.toJson]）。
  Future<void> savePendingDownload(
      String packName, Map<String, dynamic> record) async {
    if (packName.trim().isEmpty) return;
    await _prefs.setString('$_pendingDlPrefix$packName', jsonEncode(record));
  }

  /// 读某包的待下载意图（无则 null）。
  Map<String, dynamic>? getPendingDownload(String packName) {
    final s = _prefs.getString('$_pendingDlPrefix$packName');
    if (s == null) return null;
    try {
      final m = jsonDecode(s);
      return m is Map<String, dynamic> ? m : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearPendingDownload(String packName) async {
    await _prefs.remove('$_pendingDlPrefix$packName');
  }

  String getAdminUploadToken() => _adminUploadTokenValue;

  String getUserRole() => _prefs.getString(_userRoleKey) ?? '';
  String getUserName() => _prefs.getString(_userNameKey) ?? '';
  String getContributorName() => _prefs.getString(_contributorKey) ?? '';
  String getUploadLocation() => _prefs.getString(_uploadLocationKey) ?? '';

  bool get isAdminMode => getUserRole() == 'admin';
  bool get isBetaMode => getUserRole() == 'beta';
  bool get hasUploadAccess =>
      getAdminUploadToken().isNotEmpty && getUserRole().isNotEmpty;

  Future<String> ensureFeedbackClientId() async {
    final existing = _prefs.getString(_feedbackClientIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final id = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _prefs.setString(_feedbackClientIdKey, id);
    return id;
  }

  Future<void> setAdminUploadToken(String value) async {
    final normalized = value.trim();
    await _setCredential(_adminUploadTokenKey, normalized);
    _adminUploadTokenValue = normalized;
    if (normalized.isEmpty) {
      await _prefs.remove(_userRoleKey);
      await _prefs.remove(_userNameKey);
    }
  }

  Future<void> setUserIdentity(
      {required String role, required String name}) async {
    if (role.isEmpty) {
      await _prefs.remove(_userRoleKey);
      await _prefs.remove(_userNameKey);
      return;
    }
    await _prefs.setString(_userRoleKey, role);
    await _prefs.setString(_userNameKey, name);
  }

  String getConsentAcceptedVersion() =>
      _prefs.getString(_consentAcceptedKey) ?? '';

  Future<void> setConsentAccepted(String version) async {
    await _prefs.setString(_consentAcceptedKey, version);
  }

  Future<void> setContributorName(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await _prefs.remove(_contributorKey);
      return;
    }
    await _prefs.setString(_contributorKey, normalized);
  }

  Future<void> setUploadLocation(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await _prefs.remove(_uploadLocationKey);
      return;
    }
    await _prefs.setString(_uploadLocationKey, normalized);
  }

  bool get isNewUserGuideDismissed =>
      _prefs.getBool(_newUserGuideDismissedKey) ?? false;

  Future<void> dismissNewUserGuide() async {
    await _prefs.setBool(_newUserGuideDismissedKey, true);
  }

  String? get dismissedUpdateVersion =>
      _prefs.getString(_dismissedUpdateVersionKey);

  Future<void> dismissUpdateVersion(String version) async {
    await _prefs.setString(_dismissedUpdateVersionKey, version);
  }

  int get flashcardGroupSize {
    final value = _prefs.getInt(_flashcardGroupSizeKey) ?? 10;
    return value.clamp(1, 100);
  }

  Future<void> setFlashcardGroupSize(int value) async {
    await _prefs.setInt(_flashcardGroupSizeKey, value.clamp(1, 100));
  }

  /// 开始打卡时是否直接进入全屏（专注）模式。默认 false：先停在带筛选条的窗口视图。
  bool get flashcardStartFullscreen =>
      _prefs.getBool(_flashcardStartFullscreenKey) ?? false;

  Future<void> setFlashcardStartFullscreen(bool value) async {
    await _prefs.setBool(_flashcardStartFullscreenKey, value);
  }

  /// 上次打卡使用的筛选（如 all / unlearned / favorite / ...），下次打卡沿用。
  String get lastFlashcardFilter =>
      _prefs.getString(_lastFlashcardFilterKey) ?? '';

  Future<void> setLastFlashcardFilter(String value) async {
    await _prefs.setString(_lastFlashcardFilterKey, value);
  }

  /// 上次确认的整套闪卡配置。用 JSON 保存，后续增加字段时旧版本仍可兼容。
  Map<String, dynamic> getLastFlashcardSetup() {
    final raw = _prefs.getString(_lastFlashcardSetupKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }

  Future<void> setLastFlashcardSetup(Map<String, dynamic> setup) async {
    await _prefs.setString(_lastFlashcardSetupKey, jsonEncode(setup));
    final filter = setup['filter'];
    if (filter is String && filter.isNotEmpty) {
      await _prefs.setString(_lastFlashcardFilterKey, filter);
    }
  }

  // ====== App 模式：新手(beginner) / 自由(free) ======
  /// 'beginner'=新手（内容与进阶入口锁定在「中国常见鸟100」）；'free'=自由（全功能）；
  /// ''=尚未选择（首次启动时弹二选一）。
  String get appMode => _prefs.getString(_appModeKey) ?? '';
  bool get isBeginnerMode => appMode == 'beginner';
  bool get hasChosenMode => appMode == 'beginner' || appMode == 'free';
  Future<void> setAppMode(String mode) async {
    if (mode != 'beginner' && mode != 'free') return;
    await _prefs.setString(_appModeKey, mode);
  }

  // ====== 观鸟清单 / life list（标准化为小写「属 种」双名，用于判断是否见过）======
  static String normalizeSci(String sci) {
    final parts = sci.trim().toLowerCase().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0]} ${parts[1]}';
    return parts.isEmpty ? '' : parts.first;
  }

  Set<String> getLifeList() {
    final str = _prefs.getString(_lifeListKey);
    if (str == null || str.isEmpty) return {};
    try {
      final list = jsonDecode(str) as List<dynamic>;
      return list.map((e) => '$e').toSet();
    } catch (_) {
      return {};
    }
  }

  int get lifeListCount => getLifeList().length;

  // ====== 跨分类同义词（郑四 ↔ eBird/AviList）======
  // 不同分类系统对同一种鸟用不同学名（如 小田鸡 Porzana pusilla / Zapornia pusilla）。
  // 观鸟清单按学名匹配，若清单（eBird/AviList）与数据包（郑四）分类不同会漏配。
  // 这里把每个学名展开成它的「等价学名组」，匹配时任一写法命中即算已见。
  static Map<String, List<String>> _synonyms = const {};

  /// 启动时调一次：加载 assets/data/taxonomy_synonyms.json（缺失则退化为精确匹配）。
  static Future<void> loadTaxonomySynonyms() async {
    if (_synonyms.isNotEmpty) return;
    try {
      final raw =
          await rootBundle.loadString('assets/data/taxonomy_synonyms.json');
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _synonyms =
          j.map((k, v) => MapEntry(k, (v as List).map((e) => '$e').toList()));
    } catch (_) {
      _synonyms = const {};
    }
  }

  /// 某学名的全部等价二名（含自身，均归一化小写）。无同义词时只含自身。
  Set<String> lifeGroup(String sci) {
    final n = normalizeSci(sci);
    if (n.isEmpty) return const {};
    final g = _synonyms[n];
    return g == null ? {n} : {n, ...g};
  }

  /// 是否已在清单里（已见过）。跨分类：该种的任一等价学名在清单里即算已见。
  bool hasSeen(String sci) {
    final list = getLifeList();
    return lifeGroup(sci).any(list.contains);
  }

  Future<void> _saveLifeList(Set<String> set) async {
    await _prefs.setString(_lifeListKey, jsonEncode(set.toList()));
  }

  Future<void> setSeen(String sci, bool seen) async {
    final n = normalizeSci(sci);
    if (n.isEmpty) return;
    final set = getLifeList();
    if (seen) {
      set.add(n);
    } else {
      set.remove(n);
    }
    await _saveLifeList(set);
  }

  /// 合并一批学名（如导入 eBird CSV），返回本次新增的数量。
  Future<int> mergeLifeList(Iterable<String> scientificNames) async {
    final set = getLifeList();
    final before = set.length;
    for (final s in scientificNames) {
      final n = normalizeSci(s);
      if (n.isNotEmpty) set.add(n);
    }
    await _saveLifeList(set);
    return set.length - before;
  }

  Future<void> clearLifeList() async {
    await _prefs.remove(_lifeListKey);
  }

  // ============ 选择题鸟名显示（cn / en / sci 任意组合，至少一项）============

  /// 选择题选项里显示哪些名字：'cn'(中文) / 'en'(英文) / 'sci'(拉丁名)。
  List<String> get quizNameModes {
    final v = _prefs.getStringList(_quizNameModesKey);
    if (v == null || v.isEmpty) return const ['cn', 'en'];
    final cleaned =
        v.where((m) => m == 'cn' || m == 'en' || m == 'sci').toList();
    return cleaned.isEmpty ? const ['cn'] : cleaned;
  }

  Future<void> setQuizNameModes(List<String> modes) async {
    final cleaned =
        modes.where((m) => m == 'cn' || m == 'en' || m == 'sci').toList();
    await _prefs.setStringList(
        _quizNameModesKey, cleaned.isEmpty ? const ['cn'] : cleaned);
  }

  // ============ eBird 地点筛选持久化 ============

  /// 上次应用的 eBird 筛选标签（地点代码或经纬度），空表示未筛选。
  String getEbirdFilterLabel() => _prefs.getString(_ebirdFilterLabelKey) ?? '';

  /// 上次筛选命中的学名集合（小写）。
  Set<String> getEbirdFilterSci() =>
      (_prefs.getStringList(_ebirdFilterSciKey) ?? const []).toSet();

  /// 上次筛选的 eBird 地区代码（如 CN-42 / NO-03），「可能性」排序按它查近期观测。
  /// 经纬度/当前定位筛选时为空。
  String getEbirdFilterRegion() =>
      _prefs.getString(_ebirdFilterRegionKey) ?? '';

  Future<void> setEbirdFilterRegion(String region) async {
    final r = region.trim();
    if (r.isEmpty) {
      await _prefs.remove(_ebirdFilterRegionKey);
    } else {
      await _prefs.setString(_ebirdFilterRegionKey, r);
    }
  }

  /// 上次坐标筛选的「纬度,经度,半径km」（经纬度筛选时用，「可能性」按它查附近近期观测）。
  String getEbirdFilterCoords() =>
      _prefs.getString(_ebirdFilterCoordsKey) ?? '';

  Future<void> setEbirdFilterCoords(String coords) async {
    final c = coords.trim();
    if (c.isEmpty) {
      await _prefs.remove(_ebirdFilterCoordsKey);
    } else {
      await _prefs.setString(_ebirdFilterCoordsKey, c);
    }
  }

  Future<void> saveEbirdFilter(String label, Set<String> sci) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty || sci.isEmpty) {
      await clearEbirdFilter();
      return;
    }
    await _prefs.setString(_ebirdFilterLabelKey, trimmed);
    await _prefs.setStringList(_ebirdFilterSciKey, sci.toList());
  }

  Future<void> clearEbirdFilter() async {
    await _prefs.remove(_ebirdFilterLabelKey);
    await _prefs.remove(_ebirdFilterSciKey);
    await _prefs.remove(_ebirdFilterRegionKey);
    await _prefs.remove(_ebirdFilterCoordsKey);
  }

  /// 最近用过的 eBird 地点（最多 10 条，最新在前）。
  List<String> getEbirdLocationHistory() =>
      _prefs.getStringList(_ebirdLocationHistoryKey) ?? const [];

  Future<void> addEbirdLocationHistory(String location) async {
    final normalized = location.trim();
    if (normalized.isEmpty) return;
    final list = getEbirdLocationHistory().toList()
      ..removeWhere((e) => e.toLowerCase() == normalized.toLowerCase());
    list.insert(0, normalized);
    await _prefs.setStringList(
        _ebirdLocationHistoryKey, list.take(10).toList());
  }

  Future<void> removeEbirdLocationHistory(String location) async {
    final list = getEbirdLocationHistory().toList()
      ..removeWhere((e) => e.toLowerCase() == location.trim().toLowerCase());
    await _prefs.setStringList(_ebirdLocationHistoryKey, list);
  }

  // ============ 纠错日记 ============

  List<FeedbackEntry> getFeedbackJournal() {
    final str = _prefs.getString(_feedbackJournalKey);
    if (str == null || str.isEmpty) return [];
    try {
      final decoded = jsonDecode(str);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) =>
              FeedbackEntry.fromJson(Map<String, dynamic>.from(item)))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      return [];
    }
  }

  Future<void> addFeedbackEntry({
    required String message,
    String page = '',
    String speciesCn = '',
    String speciesSci = '',
  }) async {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final list = getFeedbackJournal();
    list.insert(
      0,
      FeedbackEntry(
        message: normalized,
        page: page,
        speciesCn: speciesCn,
        speciesSci: speciesSci,
        createdAt: DateTime.now().toIso8601String(),
      ),
    );
    await _saveFeedbackJournal(list);
  }

  Future<void> deleteFeedbackEntry(String createdAt) async {
    final list = getFeedbackJournal()
      ..removeWhere((item) => item.createdAt == createdAt);
    await _saveFeedbackJournal(list);
  }

  Future<void> clearFeedbackJournal() async {
    await _prefs.remove(_feedbackJournalKey);
  }

  Future<void> _saveFeedbackJournal(List<FeedbackEntry> list) async {
    await _prefs.setString(
      _feedbackJournalKey,
      jsonEncode(list.map((item) => item.toJson()).toList()),
    );
  }

  // ============ 识别笔记 ============

  Map<String, String> getSpeciesNotes() {
    final str = _prefs.getString(_speciesNotesKey);
    if (str == null || str.isEmpty) return {};
    try {
      final decoded = jsonDecode(str);
      if (decoded is! Map) return {};
      final result = <String, String>{};
      decoded.forEach((key, value) {
        if (value is String) result['$key'] = value;
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  String getSpeciesNote(String sciName) {
    return getSpeciesNotes()[sciName] ?? '';
  }

  Future<void> setSpeciesNote(String sciName, String note) async {
    final notes = getSpeciesNotes();
    final normalized = note.trim();
    if (normalized.isEmpty) {
      notes.remove(sciName);
    } else {
      notes[sciName] = normalized;
    }
    await _prefs.setString(_speciesNotesKey, jsonEncode(notes));
  }

  // ============ 学习统计 ============

  /// 获取学习统计
  LearningStats getStats() {
    final str = _prefs.getString(_statsKey);
    if (str == null || str.isEmpty) return LearningStats();
    try {
      final map = jsonDecode(str) as Map<String, dynamic>;
      return LearningStats.fromJson(map);
    } catch (_) {
      return LearningStats();
    }
  }

  /// 重置统计
  Future<void> resetStats() async {
    await _prefs.setString(_statsKey, jsonEncode(LearningStats().toJson()));
  }

  /// 记录正确
  Future<void> markCorrect() async {
    final stats = getStats();
    stats.correct++;
    await _saveStats(stats);
  }

  /// 记录错误
  Future<void> markWrong() async {
    final stats = getStats();
    stats.wrong++;
    await _saveStats(stats);
  }

  Future<void> _saveStats(LearningStats stats) async {
    await _prefs.setString(_statsKey, jsonEncode(stats.toJson()));
  }

  Set<String> getCheckInDates() {
    final str = _prefs.getString(_checkInDatesKey);
    if (str == null || str.isEmpty) return {};
    try {
      final list = jsonDecode(str) as List<dynamic>;
      return list.cast<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _recordCheckIn() async {
    final dates = getCheckInDates();
    dates.add(DateTime.now().toIso8601String().substring(0, 10));
    await _prefs.setString(
        _checkInDatesKey, jsonEncode(dates.toList()..sort()));
    await _incrementTodayStudyCount();
  }

  // ====== 每日目标 / 今日打卡张数 ======
  static const _dailyGoalKey = 'daily_goal';
  static const _studyCountDateKey = 'study_count_date';
  static const _studyCountValueKey = 'study_count_value';

  /// 每日目标张数，默认 10，范围 1–200。
  int get dailyGoal {
    final v = _prefs.getInt(_dailyGoalKey) ?? 10;
    return v.clamp(1, 200);
  }

  Future<void> setDailyGoal(int value) async {
    await _prefs.setInt(_dailyGoalKey, value.clamp(1, 200));
  }

  /// 今日已打卡张数（跨天自动归零）。
  int getTodayStudyCount() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (_prefs.getString(_studyCountDateKey) != today) return 0;
    return _prefs.getInt(_studyCountValueKey) ?? 0;
  }

  Future<void> _incrementTodayStudyCount() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final cur = _prefs.getString(_studyCountDateKey) == today
        ? (_prefs.getInt(_studyCountValueKey) ?? 0)
        : 0;
    await _prefs.setString(_studyCountDateKey, today);
    await _prefs.setInt(_studyCountValueKey, cur + 1);
  }

  bool get isDailyGoalMet => getTodayStudyCount() >= dailyGoal;

  // ====== 每日打卡提醒（仅 Android 生效）======
  static const _reminderEnabledKey = 'daily_reminder_enabled';
  static const _reminderHourKey = 'daily_reminder_hour';
  static const _reminderMinuteKey = 'daily_reminder_minute';

  bool get reminderEnabled => _prefs.getBool(_reminderEnabledKey) ?? false;
  Future<void> setReminderEnabled(bool v) async =>
      _prefs.setBool(_reminderEnabledKey, v);

  int get reminderHour => _prefs.getInt(_reminderHourKey) ?? 19;
  int get reminderMinute => _prefs.getInt(_reminderMinuteKey) ?? 30;
  Future<void> setReminderTime(int hour, int minute) async {
    await _prefs.setInt(_reminderHourKey, hour);
    await _prefs.setInt(_reminderMinuteKey, minute);
  }

  // ====== 听声每日挑战 ======
  static const _soundChallengeDateKey = 'sound_challenge_date';
  static const _soundChallengeScoreKey = 'sound_challenge_score';
  static const _soundChallengeTotalKey = 'sound_challenge_total';

  bool get soundChallengeDoneToday {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return _prefs.getString(_soundChallengeDateKey) == today;
  }

  int get soundChallengeScore => _prefs.getInt(_soundChallengeScoreKey) ?? 0;
  int get soundChallengeTotal => _prefs.getInt(_soundChallengeTotalKey) ?? 0;

  Future<void> recordSoundChallenge(int score, int total) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await _prefs.setString(_soundChallengeDateKey, today);
    await _prefs.setInt(_soundChallengeScoreKey, score);
    await _prefs.setInt(_soundChallengeTotalKey, total);
  }

  // ============ 物种掌握度追踪 ============

  /// 获取所有物种的掌握度记录
  /// key: 中文名, value: SpeciesMastery
  Map<String, SpeciesMastery> getAllMastery() {
    final str = _prefs.getString(_speciesMasteryKey);
    if (str == null || str.isEmpty) return {};
    try {
      final decoded = jsonDecode(str);
      if (decoded is! Map) return {};
      final result = <String, SpeciesMastery>{};
      decoded.forEach((key, value) {
        try {
          if (value is Map) {
            result['$key'] =
                SpeciesMastery.fromJson(Map<String, dynamic>.from(value));
          }
        } catch (_) {
          // 单条记录损坏只丢弃该条；整表照常返回，
          // 否则下次 markSpeciesKnown 重写会把其余物种的进度一并抹掉。
        }
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  /// 获取单个物种的掌握度
  SpeciesMastery getMastery(String cnName) {
    final all = getAllMastery();
    return all[cnName] ?? SpeciesMastery();
  }

  /// legacy 固定间隔表：仅用于把老记录（无 intervalDays）迁移播种，见 SpeciesMastery.fromJson。
  /// 现役调度已改成 SM-2-lite（ease × interval，见 _nextIntervalDays）。
  static const srsIntervalsDays = [1, 2, 4, 7, 15, 30];

  static const _easeMin = 1.3;
  static const _easeMax = 2.7;
  static const _intervalMaxDays = 365;

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// SM-2-lite 下一间隔：前两次固定爬坡(1→3 天)，之后 interval×ease。
  static int _nextIntervalDays(int reps, int prevInterval, double ease) {
    if (reps <= 1) return 1;
    if (reps == 2) return 3;
    var next = (prevInterval * ease).round();
    if (next <= prevInterval) next = prevInterval + 1; // 保证严格增长
    return next > _intervalMaxDays ? _intervalMaxDays : next;
  }

  /// 该物种是否到期需要复习（纯函数，传入已取好的 mastery，避免重复解析）。
  static bool isDue(SpeciesMastery m) {
    if (m.knownCount == 0 && m.unknownCount == 0) return false; // 没学过不算
    final last = DateTime.tryParse(m.lastTime);
    if (last == null) return true;
    if (m.intervalDays <= 0) return true; // 学过但未排程（含 legacy）→ 到期
    return DateTime.now().difference(last).inDays >= m.intervalDays;
  }

  /// 标记物种为"认识"。
  /// 调度每天每种最多推进一次：同一天内（同一 session 里多张同种卡、或多条录音卡）
  /// 重复答对只累计统计，不再重复 ++streak / 拉长间隔，杜绝"一次坐下刷成已掌握"。
  Future<void> markSpeciesKnown(String cnName) async {
    final all = getAllMastery();
    final m = all[cnName] ?? SpeciesMastery();
    final now = DateTime.now();
    final last = DateTime.tryParse(m.lastTime);
    final advancedToday = last != null && _isSameDay(last, now);

    m.knownCount++;
    m.lastResult = 'known';
    if (!advancedToday) {
      m.knownStreak++;
      // 纯答对按 SM-2 的 q=4 处理：ease 不变（间隔仍靠 ×ease 增长）。
      m.intervalDays = _nextIntervalDays(m.knownStreak, m.intervalDays, m.ease);
      m.lastTime = now.toIso8601String();
      if (m.knownStreak >= 3) m.unfamiliar = false; // 连续 3 天认识才算掌握
    }
    all[cnName] = m;
    await _prefs.setString(
      _speciesMasteryKey,
      jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))),
    );
    await _recordCheckIn();
  }

  /// 标记物种为"不认识"（加入不熟悉列表）。
  /// 答错一律生效（清 streak、置 unfamiliar、间隔归 1 天重学），失败信号不被同天的答对掩盖；
  /// 但 ease 惩罚每天至多一次，避免同种多张卡把 ease 连扣。
  Future<void> markSpeciesUnknown(String cnName) async {
    final all = getAllMastery();
    final m = all[cnName] ?? SpeciesMastery();
    final now = DateTime.now();
    final last = DateTime.tryParse(m.lastTime);
    final lapsedToday =
        m.lastResult == 'unknown' && last != null && _isSameDay(last, now);

    m.unknownCount++;
    m.knownStreak = 0;
    m.lastResult = 'unknown';
    m.unfamiliar = true;
    if (!lapsedToday) {
      m.ease = (m.ease - 0.2).clamp(_easeMin, _easeMax);
    }
    m.intervalDays = 1; // 明天重学
    m.lastTime = now.toIso8601String();
    all[cnName] = m;
    await _prefs.setString(
      _speciesMasteryKey,
      jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))),
    );
    await _recordCheckIn();
  }

  /// 获取不熟悉的物种中文名列表
  Set<String> getUnfamiliarSpecies() {
    final all = getAllMastery();
    return all.entries
        .where((e) => e.value.unfamiliar)
        .map((e) => e.key)
        .toSet();
  }

  /// 获取不熟悉的物种数量
  int get unfamiliarCount => getUnfamiliarSpecies().length;

  /// 手动将物种标记为"已掌握"（从不熟悉列表移除）
  Future<void> markSpeciesMastered(String cnName) async {
    final all = getAllMastery();
    final m = all[cnName];
    if (m != null) {
      m.unfamiliar = false;
      all[cnName] = m;
      await _prefs.setString(
        _speciesMasteryKey,
        jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))),
      );
    }
  }

  /// 清空所有不熟悉记录
  Future<void> clearUnfamiliar() async {
    final all = getAllMastery();
    for (final m in all.values) {
      m.unfamiliar = false;
    }
    await _prefs.setString(
      _speciesMasteryKey,
      jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }
}

/// 学习统计
class LearningStats {
  int correct;
  int wrong;

  LearningStats({this.correct = 0, this.wrong = 0});

  int get total => correct + wrong;
  double get accuracy => total == 0 ? 0 : correct / total;

  factory LearningStats.fromJson(Map<String, dynamic> json) {
    return LearningStats(
      correct: json['correct'] as int? ?? 0,
      wrong: json['wrong'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'correct': correct, 'wrong': wrong};
}

/// 单个物种的掌握度（SM-2-lite 间隔重复：ease 难度因子 + 独立 interval）。
class SpeciesMastery {
  int knownCount; // 认识次数（累计，纯统计）
  int unknownCount; // 不认识次数（累计，纯统计）
  int knownStreak; // 连续认识次数（= SM-2 的 reps，跨天计，答错清零）
  bool unfamiliar; // 是否在不熟悉列表中
  String lastResult; // 上次结果: "known" | "unknown" | ""
  String lastTime; // 上次「推进调度」的时间（不是每次答题都刷新，见 markSpeciesKnown）
  double ease; // 难度因子（SM-2 EF），越大复习间隔涨得越快；答错下调，下限 1.3
  int intervalDays; // 当前复习间隔（天）；0 = 尚未排程（新学/legacy 迁移）

  SpeciesMastery({
    this.knownCount = 0,
    this.unknownCount = 0,
    this.knownStreak = 0,
    this.unfamiliar = false,
    this.lastResult = '',
    this.lastTime = '',
    this.ease = 2.5,
    this.intervalDays = 0,
  });

  factory SpeciesMastery.fromJson(Map<String, dynamic> json) {
    final streak = json['knownStreak'] as int? ?? 0;
    // legacy 迁移：老记录没有 intervalDays/ease，用旧的固定间隔表按 streak 播种一次，
    // 避免升级后把所有已学鸟种的复习间隔一夜清零。
    final seededInterval = streak > 0
        ? StorageService.srsIntervalsDays[
            streak.clamp(0, StorageService.srsIntervalsDays.length - 1)]
        : 0;
    return SpeciesMastery(
      knownCount: json['knownCount'] as int? ?? 0,
      unknownCount: json['unknownCount'] as int? ?? 0,
      knownStreak: streak,
      unfamiliar: json['unfamiliar'] as bool? ?? false,
      lastResult: json['lastResult'] as String? ?? '',
      lastTime: json['lastTime'] as String? ?? '',
      ease: (json['ease'] as num?)?.toDouble() ?? 2.5,
      intervalDays: json['intervalDays'] as int? ?? seededInterval,
    );
  }

  Map<String, dynamic> toJson() => {
        'knownCount': knownCount,
        'unknownCount': unknownCount,
        'knownStreak': knownStreak,
        'unfamiliar': unfamiliar,
        'lastResult': lastResult,
        'lastTime': lastTime,
        'ease': ease,
        'intervalDays': intervalDays,
      };
}

class FeedbackEntry {
  final String message;
  final String page;
  final String speciesCn;
  final String speciesSci;
  final String createdAt;

  const FeedbackEntry({
    required this.message,
    this.page = '',
    this.speciesCn = '',
    this.speciesSci = '',
    required this.createdAt,
  });

  factory FeedbackEntry.fromJson(Map<String, dynamic> json) {
    return FeedbackEntry(
      message: json['message'] as String? ?? '',
      page: json['page'] as String? ?? '',
      speciesCn: json['speciesCn'] as String? ?? '',
      speciesSci: json['speciesSci'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'message': message,
        'page': page,
        'speciesCn': speciesCn,
        'speciesSci': speciesSci,
        'createdAt': createdAt,
      };
}
