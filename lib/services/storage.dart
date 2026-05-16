import 'dart:convert';
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
  static const _feedbackJournalKey = 'feedback_journal';
  static const _speciesNotesKey = 'species_identification_notes';
  static const _checkInDatesKey = 'study_check_in_dates';
  static const _flashcardGroupSizeKey = 'flashcard_group_size';

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

  String getAdminUploadToken() => _prefs.getString(_adminUploadTokenKey) ?? '';

  bool get isAdminMode => getAdminUploadToken().isNotEmpty;

  Future<void> setAdminUploadToken(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await _prefs.remove(_adminUploadTokenKey);
      return;
    }
    await _prefs.setString(_adminUploadTokenKey, normalized);
  }

  int get flashcardGroupSize {
    final value = _prefs.getInt(_flashcardGroupSizeKey) ?? 10;
    return value.clamp(1, 100);
  }

  Future<void> setFlashcardGroupSize(int value) async {
    await _prefs.setInt(_flashcardGroupSizeKey, value.clamp(1, 100));
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
