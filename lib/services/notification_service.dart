import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 本地打卡提醒（**仅 Android**）。其他平台（iOS/鸿蒙/Web）全部惰性 no-op，
/// 不依赖、不调用插件，避免影响鸿蒙构建。
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;
  static const int _dailyId = 1001;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static Future<void> init() async {
    if (!_supported || _inited) return;
    try {
      tzdata.initializeTimeZones();
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // 时区拿不到就用默认（UTC）；提醒时间可能偏，但不崩。
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    _inited = true;
  }

  /// 请求通知权限（Android 13+）。返回是否授予。
  static Future<bool> requestPermission() async {
    if (!_supported) return false;
    await init();
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await impl?.requestNotificationsPermission();
    return granted ?? true;
  }

  /// 安排每天 hour:minute 的打卡提醒（重复）。会先取消旧的。
  static Future<void> scheduleDaily(int hour, int minute) async {
    if (!_supported) return;
    await init();
    await _plugin.cancel(_dailyId);
    final now = tz.TZDateTime.now(tz.local);
    var when =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_reminder',
        '每日打卡提醒',
        channelDescription: '提醒你每天来认鸟打卡，保持连续天数',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
    await _plugin.zonedSchedule(
      _dailyId,
      '今天还没打卡 🐦',
      '来认几只鸟，别断了连续打卡～',
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> cancel() async {
    if (!_supported) return;
    await init();
    await _plugin.cancel(_dailyId);
  }
}
