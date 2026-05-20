import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/survey_point.dart';

class SurveyPointService {
  static const _prefsKey = 'survey_points'; // legacy key, for one-time migration

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/survey_points.json');
  }

  static Future<List<SurveyPoint>> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final raw = await file.readAsString();
        return raw.isEmpty ? [] : SurveyPoint.decodeList(raw);
      }
      // One-time migration from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey) ?? '';
      final points = raw.isEmpty ? <SurveyPoint>[] : SurveyPoint.decodeList(raw);
      await save(points); // write to file so next load skips prefs
      return points;
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<SurveyPoint> points) async {
    final file = await _file();
    await file.writeAsString(SurveyPoint.encodeList(points));
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

  static Future<void> deleteMany(Set<String> ids) async {
    final points = await load();
    points.removeWhere((p) => ids.contains(p.id));
    await save(points);
  }

  static Future<void> deleteAll() async {
    await save([]);
  }

  static Future<void> setVisibility(Set<String> ids, bool visible) async {
    final points = await load();
    final updated = points
        .map((p) => ids.contains(p.id) ? p.copyWith(isVisible: visible) : p)
        .toList();
    await save(updated);
  }

  static Future<void> setAllVisibility(bool visible) async {
    final points = await load();
    await save(points.map((p) => p.copyWith(isVisible: visible)).toList());
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

    final rng = Random.secure();
    String uid() => List.generate(
        16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
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
      final cleaned = _cleanKmlText(rawName);
      final name = cleaned.isNotEmpty ? cleaned : '位点${seq++}';

      points.add(SurveyPoint(
        id: uid(),
        name: name,
        latitude: lat,
        longitude: lon,
      ));
    }
    return points;
  }

  static String _cleanKmlText(String raw) {
    final cdata = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true);
    final m = cdata.firstMatch(raw);
    return (m != null ? m.group(1)! : raw).trim();
  }
}
