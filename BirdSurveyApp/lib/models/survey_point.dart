import 'dart:convert';
import 'dart:math';

class SurveyPoint {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String notes;
  final String county;    // 县市
  final String windFarm;  // 风电场
  final bool isVisible;   // 是否在地图上显示
  final double? distanceM;

  SurveyPoint({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.notes = '',
    this.county = '',
    this.windFarm = '',
    this.isVisible = true,
    this.distanceM,
  });

  SurveyPoint copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    String? notes,
    String? county,
    String? windFarm,
    bool? isVisible,
    double? distanceM,
  }) => SurveyPoint(
        id: id ?? this.id,
        name: name ?? this.name,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        notes: notes ?? this.notes,
        county: county ?? this.county,
        windFarm: windFarm ?? this.windFarm,
        isVisible: isVisible ?? this.isVisible,
        distanceM: distanceM ?? this.distanceM,
      );

  /// Haversine distance in metres from another point.
  double distanceTo(double lat, double lon) {
    const r = 6371000.0;
    final dLat = (lat - latitude) * pi / 180;
    final dLon = (lon - longitude) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(latitude * pi / 180) *
            cos(lat * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  String get distanceLabel {
    final d = distanceM;
    if (d == null) return '';
    if (d < 1000) return '${d.round()}m';
    return '${(d / 1000).toStringAsFixed(1)}km';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'notes': notes,
        'county': county,
        'windFarm': windFarm,
        'isVisible': isVisible,
      };

  factory SurveyPoint.fromJson(Map<String, dynamic> j) => SurveyPoint(
        id: j['id'] as String,
        name: j['name'] as String,
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        notes: j['notes'] as String? ?? '',
        county: j['county'] as String? ?? '',
        windFarm: j['windFarm'] as String? ?? '',
        isVisible: j['isVisible'] as bool? ?? true,
      );

  static List<SurveyPoint> decodeList(String raw) {
    if (raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => SurveyPoint.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String encodeList(List<SurveyPoint> pts) =>
      jsonEncode(pts.map((p) => p.toJson()).toList());

  /// Parse CSV. Reads header to detect column order.
  /// Supports: 位点名称,经度,纬度,县市,风电场  (and old: 名称,纬度,经度)
  static List<SurveyPoint> fromCsv(String csv) {
    final lines = csv
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return [];

    int nameIdx = 0, latIdx = 1, lonIdx = 2;
    int countyIdx = -1, windFarmIdx = -1;
    int start = 0;

    final firstCols = lines[0].split(',').map((c) => c.trim()).toList();
    // If first row is a header (non-numeric first meaningful field)
    if (firstCols.length >= 2 && double.tryParse(firstCols[1]) == null) {
      start = 1;
      for (int i = 0; i < firstCols.length; i++) {
        final col = firstCols[i].toLowerCase();
        if (col.contains('经度') || col == 'longitude' || col == 'lon' || col == 'lng') {
          lonIdx = i;
        } else if (col.contains('纬度') || col == 'latitude' || col == 'lat') {
          latIdx = i;
        } else if (col.contains('名称') || col == 'name') {
          nameIdx = i;
        } else if (col.contains('县') || col.contains('市') || col == 'county' || col == 'city') {
          countyIdx = i;
        } else if (col.contains('风电') || col.contains('wind')) {
          windFarmIdx = i;
        }
      }
    }

    final rng = Random.secure();
    String uid() => List.generate(
        16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

    final result = <SurveyPoint>[];
    for (int i = start; i < lines.length; i++) {
      final cols = lines[i].split(',');
      final maxIdx = [nameIdx, latIdx, lonIdx].reduce(max);
      if (cols.length <= maxIdx) continue;
      final lat = double.tryParse(cols[latIdx].trim());
      final lon = double.tryParse(cols[lonIdx].trim());
      if (lat == null || lon == null) continue;
      result.add(SurveyPoint(
        id: uid(),
        name: cols[nameIdx].trim(),
        latitude: lat,
        longitude: lon,
        county: countyIdx >= 0 && cols.length > countyIdx
            ? cols[countyIdx].trim()
            : '',
        windFarm: windFarmIdx >= 0 && cols.length > windFarmIdx
            ? cols[windFarmIdx].trim()
            : '',
      ));
    }
    return result;
  }
}
