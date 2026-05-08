import 'package:shared_preferences/shared_preferences.dart';
import '../models/survey_point.dart';

class SurveyPointService {
  static const _key = 'survey_points';

  static Future<List<SurveyPoint>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? '';
    return SurveyPoint.decodeList(raw);
  }

  static Future<void> save(List<SurveyPoint> points) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, SurveyPoint.encodeList(points));
  }

  static Future<void> add(SurveyPoint point) async {
    final points = await load();
    points.add(point);
    await save(points);
  }

  static Future<void> delete(String id) async {
    final points = await load();
    points.removeWhere((p) => p.id == id);
    await save(points);
  }

  static Future<int> importFromCsv(String csvText) async {
    final imported = SurveyPoint.fromCsv(csvText);
    if (imported.isEmpty) return 0;
    final existing = await load();
    existing.addAll(imported);
    await save(existing);
    return imported.length;
  }

  static Future<int> importFromKml(String kmlText) async {
    final imported = _parseKml(kmlText);
    if (imported.isEmpty) return 0;
    final existing = await load();
    existing.addAll(imported);
    await save(existing);
    return imported.length;
  }

  static List<SurveyPoint> _parseKml(String kmlText) {
    final points = <SurveyPoint>[];
    final placemarkRe =
        RegExp(r'<Placemark[^>]*>(.*?)</Placemark>', dotAll: true);
    final nameRe = RegExp(r'<name[^>]*>(.*?)</name>', dotAll: true);
    final coordRe = RegExp(
        r'<coordinates[^>]*>\s*([-\d.]+)\s*,\s*([-\d.]+)', dotAll: true);

    int seq = 0;
    for (final pm in placemarkRe.allMatches(kmlText)) {
      final block = pm.group(1)!;
      final nameMatch = nameRe.firstMatch(block);
      final coordMatch = coordRe.firstMatch(block);
      if (coordMatch == null) continue;

      final lon = double.tryParse(coordMatch.group(1)!);
      final lat = double.tryParse(coordMatch.group(2)!);
      if (lat == null || lon == null) continue;

      final rawName = nameMatch?.group(1) ?? '';
      final name = _cleanKmlText(rawName).isNotEmpty
          ? _cleanKmlText(rawName)
          : '位点${++seq}';

      points.add(SurveyPoint(
        id: '${DateTime.now().millisecondsSinceEpoch}_$seq',
        name: name,
        latitude: lat,
        longitude: lon,
      ));
      seq++;
    }
    return points;
  }

  // Strip CDATA wrappers and trim whitespace
  static String _cleanKmlText(String raw) {
    final cdata = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true);
    final m = cdata.firstMatch(raw);
    return (m != null ? m.group(1)! : raw).trim();
  }
}
