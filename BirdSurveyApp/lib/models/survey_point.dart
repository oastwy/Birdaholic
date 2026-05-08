import 'dart:convert';
import 'dart:math';

class SurveyPoint {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String notes;
  double? distanceM; // set dynamically based on current GPS

  SurveyPoint({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.notes = '',
    this.distanceM,
  });

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
      };

  factory SurveyPoint.fromJson(Map<String, dynamic> j) => SurveyPoint(
        id: j['id'] as String,
        name: j['name'] as String,
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        notes: j['notes'] as String? ?? '',
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

  /// Parse CSV text. Expected header: 名称,纬度,经度[,备注]
  /// Also accepts: name,lat,lng[,notes]
  static List<SurveyPoint> fromCsv(String csv) {
    final lines = csv
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return [];

    // skip header if first line contains non-numeric second field
    int start = 0;
    final firstCols = lines[0].split(',');
    if (firstCols.length >= 3 &&
        double.tryParse(firstCols[1].trim()) == null) {
      start = 1;
    }

    final result = <SurveyPoint>[];
    for (int i = start; i < lines.length; i++) {
      final cols = lines[i].split(',');
      if (cols.length < 3) continue;
      final lat = double.tryParse(cols[1].trim());
      final lon = double.tryParse(cols[2].trim());
      if (lat == null || lon == null) continue;
      result.add(SurveyPoint(
        id: DateTime.now().microsecondsSinceEpoch.toString() + i.toString(),
        name: cols[0].trim(),
        latitude: lat,
        longitude: lon,
        notes: cols.length > 3 ? cols[3].trim() : '',
      ));
    }
    return result;
  }
}
