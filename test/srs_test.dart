import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bird_flashcard/services/storage.dart';

/// 把一条掌握度记录预置进 prefs（可指定"上次调度时间"为 N 天前，用于跨天场景）。
Future<StorageService> _svcWith(
  String cn,
  SpeciesMastery m, {
  int lastTimeDaysAgo = 0,
}) async {
  if (m.lastTime.isEmpty && (m.knownCount > 0 || m.unknownCount > 0)) {
    m.lastTime = DateTime.now()
        .subtract(Duration(days: lastTimeDaysAgo))
        .toIso8601String();
  }
  SharedPreferences.setMockInitialValues({
    'species_mastery': jsonEncode({cn: m.toJson()}),
  });
  final prefs = await SharedPreferences.getInstance();
  return StorageService(prefs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SRS SM-2-lite 调度', () {
    test('首次答对：streak=1、间隔=1天（不再是旧表的 2 天死区）', () async {
      SharedPreferences.setMockInitialValues({});
      final svc = StorageService(await SharedPreferences.getInstance());
      await svc.markSpeciesKnown('测试鸟');
      final m = svc.getMastery('测试鸟');
      expect(m.knownStreak, 1);
      expect(m.intervalDays, 1);
      expect(m.lastResult, 'known');
    });

    test('同一天重复答对不虚增 streak / 不拉长间隔（finding ②）', () async {
      SharedPreferences.setMockInitialValues({});
      final svc = StorageService(await SharedPreferences.getInstance());
      await svc.markSpeciesKnown('测试鸟');
      await svc.markSpeciesKnown('测试鸟');
      await svc.markSpeciesKnown('测试鸟');
      final m = svc.getMastery('测试鸟');
      expect(m.knownStreak, 1, reason: '同天 3 次答对只算一次调度');
      expect(m.intervalDays, 1);
      expect(m.knownCount, 3, reason: '统计计数仍累加');
    });

    test('跨天答对：间隔按 ×ease 增长、连续 3 天判掌握', () async {
      final svc = await _svcWith(
        '测试鸟',
        SpeciesMastery(
          knownCount: 2,
          knownStreak: 2,
          intervalDays: 3,
          ease: 2.5,
          unfamiliar: true,
          lastResult: 'known',
        ),
        lastTimeDaysAgo: 3,
      );
      await svc.markSpeciesKnown('测试鸟');
      final m = svc.getMastery('测试鸟');
      expect(m.knownStreak, 3);
      expect(m.intervalDays, 8, reason: 'round(3 * 2.5) = 8');
      expect(m.unfamiliar, false, reason: '连续 3 天认识 → 移出不熟悉');
    });

    test('答错：streak 清零、进不熟悉、间隔归 1、ease 下调 0.2', () async {
      final svc = await _svcWith(
        '测试鸟',
        SpeciesMastery(
          knownCount: 5,
          knownStreak: 5,
          intervalDays: 30,
          ease: 2.5,
          lastResult: 'known',
        ),
        lastTimeDaysAgo: 1,
      );
      await svc.markSpeciesUnknown('测试鸟');
      final m = svc.getMastery('测试鸟');
      expect(m.knownStreak, 0);
      expect(m.unfamiliar, true);
      expect(m.intervalDays, 1);
      expect(m.ease, closeTo(2.3, 1e-9));
    });

    test('同天多张卡连错：ease 只扣一次', () async {
      SharedPreferences.setMockInitialValues({});
      final svc = StorageService(await SharedPreferences.getInstance());
      await svc.markSpeciesKnown('测试鸟'); // 先有记录
      await svc.markSpeciesUnknown('测试鸟');
      await svc.markSpeciesUnknown('测试鸟');
      final m = svc.getMastery('测试鸟');
      expect(m.ease, closeTo(2.3, 1e-9), reason: '2.5-0.2，第二次不再扣');
    });

    test('ease 下限 1.3', () async {
      final svc = await _svcWith(
        '测试鸟',
        SpeciesMastery(
          knownCount: 1,
          knownStreak: 0,
          intervalDays: 1,
          ease: 1.4,
          lastResult: 'known',
        ),
        lastTimeDaysAgo: 1,
      );
      await svc.markSpeciesUnknown('测试鸟');
      expect(svc.getMastery('测试鸟').ease, closeTo(1.3, 1e-9));
    });
  });

  group('isDue（纯函数）', () {
    test('没学过 → 不到期', () {
      expect(StorageService.isDue(SpeciesMastery()), false);
    });

    test('间隔 4 天、2 天前学 → 未到期', () {
      final m = SpeciesMastery(
        knownCount: 1,
        intervalDays: 4,
        lastResult: 'known',
        lastTime: DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
      );
      expect(StorageService.isDue(m), false);
    });

    test('间隔 4 天、5 天前学 → 到期', () {
      final m = SpeciesMastery(
        knownCount: 1,
        intervalDays: 4,
        lastResult: 'known',
        lastTime: DateTime.now().subtract(const Duration(days: 5)).toIso8601String(),
      );
      expect(StorageService.isDue(m), true);
    });

    test('学过但未排程(interval=0, legacy) → 到期', () {
      final m = SpeciesMastery(
        knownCount: 1,
        intervalDays: 0,
        lastTime: DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      );
      expect(StorageService.isDue(m), true);
    });
  });

  group('legacy 迁移', () {
    test('老记录（无 ease/intervalDays）按 streak 播种间隔、ease 默认 2.5', () {
      final m = SpeciesMastery.fromJson({
        'knownCount': 5,
        'knownStreak': 3,
        'unfamiliar': false,
        'lastResult': 'known',
        'lastTime': '2026-06-01T10:00:00.000',
      });
      expect(m.ease, 2.5);
      expect(m.intervalDays, StorageService.srsIntervalsDays[3]); // = 7
    });
  });
}
