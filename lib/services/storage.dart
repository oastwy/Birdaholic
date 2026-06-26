import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
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
  static const _quizNameModesKey = 'quiz_name_modes';
  static const _newUserGuideDismissedKey = 'new_user_guide_dismissed';
  static const _ebirdFilterLabelKey = 'ebird_filter_label';
  static const _ebirdFilterSciKey = 'ebird_filter_sci';
  static const _ebirdFilterRegionKey = 'ebird_filter_region';
  static const _ebirdFilterCoordsKey = 'ebird_filter_coords';
  static const _ebirdLocationHistoryKey = 'ebird_location_history';
  static const _lifeListKey = 'ebird_life_list';
  static const _appModeKey = 'app_mode'; // beginner / free / ''（未选）

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  // ============ 收藏 ============

  /// 获取收藏的鸟种中文名列表
  Set<String> getFavorites() {
    final str = _prefs.getString(_favoritesKey);
    if (str == null || str.isEmpty) return {};
    final list = jsonDecode(str) as List<dynamic>;
    return list.cast<String>().toSet();
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

  String getXenoCantoApiKey() => _prefs.getString(_xenoCantoApiKey) ?? '';

  Future<void> setXenoCantoApiKey(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await _prefs.remove(_xenoCantoApiKey);
      return;
    }
    await _prefs.setString(_xenoCantoApiKey, normalized);
  }

  String getEBirdApiKey() => _prefs.getString(_eBirdApiKey) ?? '';

  Future<void> setEBirdApiKey(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await _prefs.remove(_eBirdApiKey);
      return;
    }
    await _prefs.setString(_eBirdApiKey, normalized);
  }

  // ── 整包下载断点续传：按包名持久化「打算下载的完整物种清单」，下载中断/重启后
  //    可在数据包管理里「继续下载」补齐剩余物种（createPack 幂等，已下的会跳过）。
  static const _pendingDlPrefix = 'pending_dl_';

  /// 保存某包的待下载意图（record 含 region/allowApiFallback/species:[SpeciesEntry.toJson]）。
  Future<void> savePendingDownload(
      String packName, Map<String, dynamic> record) async {
    if (packName.trim().isEmpty) return;
    await _prefs.setString(
        '$_pendingDlPrefix$packName', jsonEncode(record));
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

  String getAdminUploadToken() => _prefs.getString(_adminUploadTokenKey) ?? '';

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
    if (normalized.isEmpty) {
      await _prefs.remove(_adminUploadTokenKey);
      await _prefs.remove(_userRoleKey);
      await _prefs.remove(_userNameKey);
      return;
    }
    await _prefs.setString(_adminUploadTokenKey, normalized);
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
      _synonyms = j.map(
          (k, v) => MapEntry(k, (v as List).map((e) => '$e').toList()));
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
  String getEbirdFilterCoords() => _prefs.getString(_ebirdFilterCoordsKey) ?? '';

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
    final list = jsonDecode(str) as List<dynamic>;
    return list
        .map((item) => FeedbackEntry.fromJson(item as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
    final map = jsonDecode(str) as Map<String, dynamic>;
    return map.map((key, value) => MapEntry(key, value as String? ?? ''));
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
    final map = jsonDecode(str) as Map<String, dynamic>;
    return LearningStats.fromJson(map);
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
    final list = jsonDecode(str) as List<dynamic>;
    return list.cast<String>().toSet();
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
    final cur =
        _prefs.getString(_studyCountDateKey) == today
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
    final map = jsonDecode(str) as Map<String, dynamic>;
    return map.map(
      (k, v) => MapEntry(k, SpeciesMastery.fromJson(v as Map<String, dynamic>)),
    );
  }

  /// 获取单个物种的掌握度
  SpeciesMastery getMastery(String cnName) {
    final all = getAllMastery();
    return all[cnName] ?? SpeciesMastery();
  }

  /// SRS 间隔（天）：按连续认识次数递增；上次答错则 1 天后再复习。
  static const srsIntervalsDays = [1, 2, 4, 7, 15, 30];

  /// 该物种是否到期需要复习（纯函数，传入已取好的 mastery，避免重复解析）。
  static bool isDue(SpeciesMastery m) {
    if (m.knownCount == 0 && m.unknownCount == 0) return false; // 没学过不算
    final last = DateTime.tryParse(m.lastTime);
    if (last == null) return true;
    final streak = m.knownStreak.clamp(0, srsIntervalsDays.length - 1);
    final days = m.lastResult == 'unknown' ? 1 : srsIntervalsDays[streak];
    return DateTime.now().difference(last).inDays >= days;
  }

  /// 标记物种为"认识"
  Future<void> markSpeciesKnown(String cnName) async {
    final all = getAllMastery();
    final m = all[cnName] ?? SpeciesMastery();
    m.knownCount++;
    m.knownStreak++;
    m.lastResult = 'known';
    m.lastTime = DateTime.now().toIso8601String();
    // 连续认识 3 次以上，从"不熟悉"移除
    if (m.knownStreak >= 3) {
      m.unfamiliar = false;
    }
    all[cnName] = m;
    await _prefs.setString(
      _speciesMasteryKey,
      jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))),
    );
    await _recordCheckIn();
  }

  /// 标记物种为"不认识"（加入不熟悉列表）
  Future<void> markSpeciesUnknown(String cnName) async {
    final all = getAllMastery();
    final m = all[cnName] ?? SpeciesMastery();
    m.unknownCount++;
    m.knownStreak = 0; // 重置连续认识计数
    m.lastResult = 'unknown';
    m.lastTime = DateTime.now().toIso8601String();
    m.unfamiliar = true; // 加入不熟悉列表
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

/// 单个物种的掌握度
class SpeciesMastery {
  int knownCount; // 认识次数
  int unknownCount; // 不认识次数
  int knownStreak; // 连续认识次数
  bool unfamiliar; // 是否在不熟悉列表中
  String lastResult; // 上次结果: "known" | "unknown" | ""
  String lastTime; // 上次学习时间

  SpeciesMastery({
    this.knownCount = 0,
    this.unknownCount = 0,
    this.knownStreak = 0,
    this.unfamiliar = false,
    this.lastResult = '',
    this.lastTime = '',
  });

  factory SpeciesMastery.fromJson(Map<String, dynamic> json) {
    return SpeciesMastery(
      knownCount: json['knownCount'] as int? ?? 0,
      unknownCount: json['unknownCount'] as int? ?? 0,
      knownStreak: json['knownStreak'] as int? ?? 0,
      unfamiliar: json['unfamiliar'] as bool? ?? false,
      lastResult: json['lastResult'] as String? ?? '',
      lastTime: json['lastTime'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'knownCount': knownCount,
        'unknownCount': unknownCount,
        'knownStreak': knownStreak,
        'unfamiliar': unfamiliar,
        'lastResult': lastResult,
        'lastTime': lastTime,
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
