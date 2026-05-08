import 'dart:convert';
import 'package:http/http.dart' as http;
import 'local_tide_calculator.dart';

enum TideSource { chaoxi365, stormglass, worldtides, local }

extension TideSourceLabel on TideSource {
  String get label {
    switch (this) {
      case TideSource.chaoxi365:
        return '潮汐网API（100次/天）';
      case TideSource.stormglass:
        return 'Stormglass（10次/天）';
      case TideSource.worldtides:
        return 'WorldTides（100次/天）';
      case TideSource.local:
        return '本地天文计算（离线·无限制）';
    }
  }

  String get name {
    switch (this) {
      case TideSource.chaoxi365:
        return 'chaoxi365';
      case TideSource.stormglass:
        return 'stormglass';
      case TideSource.worldtides:
        return 'worldtides';
      case TideSource.local:
        return 'local';
    }
  }

  static TideSource fromName(String s) {
    switch (s) {
      case 'chaoxi365':
        return TideSource.chaoxi365;
      case 'worldtides':
        return TideSource.worldtides;
      case 'local':
        return TideSource.local;
      default:
        return TideSource.stormglass;
    }
  }
}

class TideResult {
  final double height;
  final String unit;
  final String? label; // qualitative description
  final DateTime time;

  TideResult({
    required this.height,
    required this.unit,
    this.label,
    required this.time,
  });
}

class _TideSample {
  final double height;
  final DateTime time;
  final String? label;

  const _TideSample(this.height, this.time, this.label);
}

class TideService {
  static const defaultChaoxi365Endpoint =
      'https://www.chaoxi365.com/api/tide?lat={lat}&lng={lng}&key={key}';

  final String chaoxi365Key;
  final String chaoxi365Endpoint;
  final String stormglassKey;
  final String worldtidesKey;
  final TideSource source;

  TideService({
    required this.source,
    this.chaoxi365Key = '',
    this.chaoxi365Endpoint = defaultChaoxi365Endpoint,
    this.stormglassKey = '',
    this.worldtidesKey = '',
  });

  Future<TideResult?> getCurrentTide(double lat, double lng) async {
    switch (source) {
      case TideSource.chaoxi365:
        return _chaoxi365(lat, lng);
      case TideSource.stormglass:
        return _stormglass(lat, lng);
      case TideSource.worldtides:
        return _worldtides(lat, lng);
      case TideSource.local:
        return _local(lat, lng);
    }
  }

  // ── Chaoxi365 ──────────────────────────────────────────────────────────────
  Future<TideResult?> _chaoxi365(double lat, double lng) async {
    if (chaoxi365Key.isEmpty || chaoxi365Endpoint.isEmpty) return null;
    final now = DateTime.now();
    final uri = Uri.tryParse(
      chaoxi365Endpoint
          .replaceAll('{lat}', lat.toStringAsFixed(6))
          .replaceAll('{lng}', lng.toStringAsFixed(6))
          .replaceAll('{lon}', lng.toStringAsFixed(6))
          .replaceAll('{key}', Uri.encodeComponent(chaoxi365Key))
          .replaceAll('{date}', _dateKey(now))
          .replaceAll(
            '{timestamp}',
            (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
          ),
    );
    if (uri == null) return null;
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body);
      return _parseFlexibleTideJson(data, now);
    } catch (_) {
      return null;
    }
  }

  TideResult? _parseFlexibleTideJson(dynamic data, DateTime target) {
    final samples = <_TideSample>[];
    void visit(dynamic value) {
      if (value is List) {
        for (final item in value) {
          visit(item);
        }
        return;
      }
      if (value is Map<String, dynamic>) {
        final height = _firstDouble(value, const [
          'height',
          'h',
          'tideHeight',
          'tide_height',
          'level',
          'waterLevel',
          'water_level',
          '潮高',
          '潮位',
        ]);
        final time = _firstDate(value, const [
          'time',
          't',
          'dateTime',
          'datetime',
          'obsTime',
          'fxTime',
          'timestamp',
          'dt',
          '时间',
        ]);
        if (height != null && time != null) {
          samples.add(
            _TideSample(
              height,
              time,
              _firstString(value, const [
                'type',
                'label',
                'state',
                'trend',
                '潮汐',
                '状态',
              ]),
            ),
          );
        }
        for (final child in value.values) {
          if (child is List || child is Map<String, dynamic>) visit(child);
        }
      }
    }

    visit(data);
    if (samples.isEmpty) return null;
    samples.sort(
      (a, b) => a.time
          .difference(target)
          .abs()
          .compareTo(b.time.difference(target).abs()),
    );
    final best = samples.first;
    return TideResult(
      height: double.parse(best.height.toStringAsFixed(3)),
      unit: 'm',
      label: best.label,
      time: best.time,
    );
  }

  static String _dateKey(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  static double? _firstDouble(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(
          value.replaceAll(RegExp(r'[^0-9.\-]'), ''),
        );
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static String? _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value != null && value.toString().isNotEmpty) return value.toString();
    }
    return null;
  }

  static DateTime? _firstDate(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is num) {
        final seconds = value > 100000000000 ? value ~/ 1000 : value.toInt();
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
      if (value is String && value.isNotEmpty) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  // ── Stormglass ──────────────────────────────────────────────────────────────
  Future<TideResult?> _stormglass(double lat, double lng) async {
    if (stormglassKey.isEmpty) return null;
    final now = DateTime.now().toUtc();
    final start = now.subtract(const Duration(hours: 1));
    final end = now.add(const Duration(hours: 1));
    final uri = Uri.parse(
      'https://api.stormglass.io/v2/tide/sea-level/point'
      '?lat=$lat&lng=$lng'
      '&start=${start.millisecondsSinceEpoch ~/ 1000}'
      '&end=${end.millisecondsSinceEpoch ~/ 1000}',
    );
    try {
      final resp = await http
          .get(uri, headers: {'Authorization': stormglassKey})
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final hours = data['hours'] as List<dynamic>? ?? [];
      TideResult? closest;
      Duration? minDiff;
      for (final h in hours) {
        final map = h as Map<String, dynamic>;
        final t = DateTime.tryParse(map['time'] as String? ?? '');
        final sg = (map['sg'] as num?)?.toDouble();
        if (t == null || sg == null) continue;
        final diff = t.difference(now).abs();
        if (minDiff == null || diff < minDiff) {
          minDiff = diff;
          closest = TideResult(height: sg, unit: 'm', time: t);
        }
      }
      return closest;
    } catch (_) {
      return null;
    }
  }

  // ── WorldTides ───────────────────────────────────────────────────────────────
  Future<TideResult?> _worldtides(double lat, double lng) async {
    if (worldtidesKey.isEmpty) return null;
    final now = DateTime.now().toUtc();
    final start = now.subtract(const Duration(hours: 2));
    final uri = Uri.parse(
      'https://www.worldtides.info/api/v3'
      '?heights&lat=$lat&lng=$lng'
      '&start=${start.millisecondsSinceEpoch ~/ 1000}'
      '&length=7200'
      '&key=$worldtidesKey',
    );
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final heights = data['heights'] as List<dynamic>? ?? [];
      TideResult? closest;
      Duration? minDiff;
      for (final h in heights) {
        final map = h as Map<String, dynamic>;
        final ts = (map['dt'] as num?)?.toInt();
        final ht = (map['height'] as num?)?.toDouble();
        if (ts == null || ht == null) continue;
        final t = DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true);
        final diff = t.difference(now).abs();
        if (minDiff == null || diff < minDiff) {
          minDiff = diff;
          closest = TideResult(height: ht, unit: 'm', time: t);
        }
      }
      return closest;
    } catch (_) {
      return null;
    }
  }

  // ── Local astronomical ───────────────────────────────────────────────────────
  Future<TideResult?> _local(double lat, double lng) async {
    final now = DateTime.now();
    final h = LocalTideCalculator.calculate(lat, lng, now);
    final label = LocalTideCalculator.stateLabel(lat, lng, now);
    return TideResult(
      height: double.parse(h.toStringAsFixed(3)),
      unit: 'm(天文)',
      label: label,
      time: now,
    );
  }
}
