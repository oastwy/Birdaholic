import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地存储服务
/// 管理收藏、学习进度和不熟悉列表
class StorageService {
  static const _favoritesKey = 'favorites';
  static const _statsKey = 'learning_stats';
  static const _speciesMasteryKey = 'species_mastery';
  static const _xenoCantoApiKey = 'xeno_canto_api_key';

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

  // ============ 物种掌握度追踪 ============

  /// 获取所有物种的掌握度记录
  /// key: 中文名, value: SpeciesMastery
  Map<String, SpeciesMastery> getAllMastery() {
    final str = _prefs.getString(_speciesMasteryKey);
    if (str == null || str.isEmpty) return {};
    final map = jsonDecode(str) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, SpeciesMastery.fromJson(v as Map<String, dynamic>)));
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
    await _prefs.setString(_speciesMasteryKey, jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))));
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
    await _prefs.setString(_speciesMasteryKey, jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))));
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
      await _prefs.setString(_speciesMasteryKey, jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))));
    }
  }

  /// 清空所有不熟悉记录
  Future<void> clearUnfamiliar() async {
    final all = getAllMastery();
    for (final m in all.values) {
      m.unfamiliar = false;
    }
    await _prefs.setString(_speciesMasteryKey, jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))));
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
  int knownCount;      // 认识次数
  int unknownCount;    // 不认识次数
  int knownStreak;     // 连续认识次数
  bool unfamiliar;     // 是否在不熟悉列表中
  String lastResult;   // 上次结果: "known" | "unknown" | ""
  String lastTime;     // 上次学习时间

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
