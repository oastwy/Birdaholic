import 'dart:convert';

import 'package:bird_flashcard/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地偏好里 JSON 值损坏（脏数据/老版本字段）时，读取必须安全回退而不是抛异常，
/// 否则答题链路（markCorrect → _recordCheckIn、markSpeciesKnown 等）会整体卡死。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<StorageService> storageWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return StorageService(await SharedPreferences.getInstance());
  }

  test('各存储键损坏时读取返回空默认值，不抛异常', () async {
    final storage = await storageWith(const {
      'favorites': '{broken',
      'study_check_in_dates': '[1, 2]',
      'feedback_journal': 'not json{',
      'species_identification_notes': '"top-level-string"',
      'learning_stats': '{broken',
      'species_mastery': '[1, 2]',
    });

    expect(storage.getFavorites(), isEmpty);
    expect(storage.isFavorite('大山雀'), isFalse);
    expect(storage.getCheckInDates(), isEmpty);
    expect(storage.getFeedbackJournal(), isEmpty);
    expect(storage.getSpeciesNotes(), isEmpty);
    expect(storage.getSpeciesNote('Parus major'), isEmpty);
    expect(storage.getStats().correct, 0);
    expect(storage.getStats().wrong, 0);
    expect(storage.getAllMastery(), isEmpty);
    expect(storage.getMastery('大山雀').knownCount, 0);
  });

  test('掌握度表单条损坏只丢弃该条，其余物种进度保留', () async {
    final good = {
      'knownCount': 2,
      'unknownCount': 1,
      'knownStreak': 1,
      'unfamiliar': false,
      'lastResult': 'known',
      'lastTime': '2026-08-29T10:00:00.000',
      'ease': 2.5,
      'intervalDays': 1,
    };
    final storage = await storageWith({
      'species_mastery':
          '{"大山雀": ${jsonEncode(good)}, "坏种": {"knownCount": "not-a-number"}}',
    });

    final all = storage.getAllMastery();
    expect(all.containsKey('坏种'), isFalse);
    expect(all['大山雀']?.knownCount, 2);
    expect(all['大山雀']?.intervalDays, 1);
  });

  test('损坏的掌握度表上继续答题不抛异常，且能写入新记录', () async {
    final storage = await storageWith(const {
      'species_mastery': '{broken',
      'study_check_in_dates': '{broken',
    });

    await storage.markSpeciesKnown('大山雀');

    final all = storage.getAllMastery();
    expect(all['大山雀']?.knownCount, 1);
    // 打卡日期损坏被清空后应能重新记录今天。
    expect(storage.getTodayStudyCount(), 1);
  });
}
