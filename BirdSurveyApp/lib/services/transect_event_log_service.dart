import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class TransectEventLogService {
  static const _fileName = 'transect_events.jsonl';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<void> append(Map<String, dynamic> event) async {
    final file = await _file();
    await file.writeAsString(
      '${jsonEncode(event)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  static Future<List<Map<String, dynamic>>> readAll() async {
    final file = await _file();
    if (!await file.exists()) return [];
    final lines = await file.readAsLines();
    final events = <Map<String, dynamic>>[];
    for (final line in lines) {
      final text = line.trim();
      if (text.isEmpty) continue;
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) events.add(decoded);
      } catch (_) {
        // Keep recovery tolerant: one bad line must not block later events.
      }
    }
    return events;
  }

  static Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) {
      await file.writeAsString('', flush: true);
    }
  }
}
