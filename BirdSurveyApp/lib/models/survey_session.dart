import 'dart:convert';

class SurveySession {
  static const entryKeySeparator = '#entry_';

  final int? id;
  final DateTime startTime;
  DateTime? endTime;
  final double latitude;
  final double longitude;
  double? tideHeight;
  String? tideUnit;
  final Map<String, int> observations; // ebird code -> count
  final Map<String, String> speciesNames; // ebird code -> Chinese name
  final Map<String, String> customValues; // field name -> value
  final Map<String, String> speciesNotes; // ebird code -> per-species note
  String notes; // overall survey notes
  // ebird code -> (fieldId -> value)  per-species custom field values
  final Map<String, Map<String, String>> speciesFields;
  // ebird code -> fieldId -> option -> count
  final Map<String, Map<String, Map<String, int>>> speciesFieldCounts;

  SurveySession({
    this.id,
    required this.startTime,
    this.endTime,
    required this.latitude,
    required this.longitude,
    this.tideHeight,
    this.tideUnit,
    Map<String, int>? observations,
    Map<String, String>? speciesNames,
    Map<String, String>? customValues,
    Map<String, String>? speciesNotes,
    this.notes = '',
    Map<String, Map<String, String>>? speciesFields,
    Map<String, Map<String, Map<String, int>>>? speciesFieldCounts,
  }) : observations = observations ?? {},
       speciesNames = speciesNames ?? {},
       customValues = customValues ?? {},
       speciesNotes = speciesNotes ?? {},
       speciesFields = speciesFields ?? {},
       speciesFieldCounts = speciesFieldCounts ?? {};

  int get totalCount => observations.values.fold(0, (a, b) => a + b);
  int get speciesCount =>
      observations.entries
          .where((e) => e.value > 0)
          .map((e) => speciesCodeForKey(e.key))
          .toSet()
          .length;

  static String speciesCodeForKey(String observationKey) {
    final idx = observationKey.indexOf(entryKeySeparator);
    return idx < 0 ? observationKey : observationKey.substring(0, idx);
  }

  static bool isSplitEntryKey(String observationKey) =>
      observationKey.contains(entryKeySeparator);

  static String newEntryKey(String ebirdCode) =>
      '$ebirdCode$entryKeySeparator${DateTime.now().microsecondsSinceEpoch}';

  Map<String, int> speciesTotals() {
    final totals = <String, int>{};
    for (final e in observations.entries.where((e) => e.value > 0)) {
      final code = speciesCodeForKey(e.key);
      totals[code] = (totals[code] ?? 0) + e.value;
    }
    return totals;
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'tideHeight': tideHeight,
      'tideUnit': tideUnit,
      'observations': observations.entries
          .where((e) => e.value > 0)
          .map((e) => '${e.key}:${e.value}')
          .join(','),
      'speciesNames': speciesNames.entries
          .map((e) => '${e.key}=${e.value}')
          .join('|'),
      'customValues': jsonEncode(customValues),
      'notes': notes,
      'speciesNotes': jsonEncode(speciesNotes),
      'speciesFields': jsonEncode(speciesFields),
      'speciesFieldCounts': jsonEncode(speciesFieldCounts),
    };
  }

  static Map<String, String> _decodeStringMap(String raw) {
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  factory SurveySession.fromMap(Map<String, dynamic> map) {
    final obsStr = map['observations'] as String? ?? '';
    final obs = <String, int>{};
    if (obsStr.isNotEmpty) {
      for (final part in obsStr.split(',')) {
        final kv = part.split(':');
        if (kv.length == 2) obs[kv[0]] = int.tryParse(kv[1]) ?? 0;
      }
    }
    final namesStr = map['speciesNames'] as String? ?? '';
    final names = <String, String>{};
    if (namesStr.isNotEmpty) {
      for (final part in namesStr.split('|')) {
        final kv = part.split('=');
        if (kv.length == 2) names[kv[0]] = kv[1];
      }
    }
    Map<String, String> customValues = {};
    final cvStr = map['customValues'] as String? ?? '';
    if (cvStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(cvStr) as Map<String, dynamic>;
        customValues = decoded.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {}
    }
    final speciesFields = _decodeNestedMap(
      map['speciesFields'] as String? ?? '',
    );
    final speciesFieldCounts = _decodeFieldCounts(
      map['speciesFieldCounts'] as String? ?? '',
    );
    if (speciesFieldCounts.isEmpty && speciesFields.isNotEmpty) {
      for (final e in obs.entries.where((e) => e.value > 0)) {
        final code = speciesCodeForKey(e.key);
        final fields = speciesFields[e.key] ?? {};
        for (final f in fields.entries) {
          if (f.value.isEmpty) continue;
          speciesFieldCounts.putIfAbsent(code, () => {});
          speciesFieldCounts[code]!.putIfAbsent(f.key, () => {});
          speciesFieldCounts[code]![f.key]![f.value] =
              (speciesFieldCounts[code]![f.key]![f.value] ?? 0) + e.value;
        }
      }
    }
    return SurveySession(
      id: map['id'] as int?,
      startTime: DateTime.parse(map['startTime'] as String),
      endTime:
          map['endTime'] != null
              ? DateTime.parse(map['endTime'] as String)
              : null,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      tideHeight:
          map['tideHeight'] != null
              ? (map['tideHeight'] as num).toDouble()
              : null,
      tideUnit: map['tideUnit'] as String?,
      observations: obs,
      speciesNames: names,
      customValues: customValues,
      notes: map['notes'] as String? ?? '',
      speciesNotes: _decodeStringMap(map['speciesNotes'] as String? ?? ''),
      speciesFields: speciesFields,
      speciesFieldCounts: speciesFieldCounts,
    );
  }

  static Map<String, Map<String, String>> _decodeNestedMap(String raw) {
    if (raw.isEmpty) return {};
    try {
      final outer = jsonDecode(raw) as Map<String, dynamic>;
      return outer.map((k, v) {
        final inner = (v as Map<String, dynamic>).map(
          (ik, iv) => MapEntry(ik, iv.toString()),
        );
        return MapEntry(k, inner);
      });
    } catch (_) {
      return {};
    }
  }

  static Map<String, Map<String, Map<String, int>>> _decodeFieldCounts(
    String raw,
  ) {
    if (raw.isEmpty) return {};
    try {
      final outer = jsonDecode(raw) as Map<String, dynamic>;
      return outer.map((code, fieldsRaw) {
        final fields = (fieldsRaw as Map<String, dynamic>).map((
          fieldId,
          optsRaw,
        ) {
          final opts = (optsRaw as Map<String, dynamic>).map(
            (opt, count) => MapEntry(opt, int.tryParse(count.toString()) ?? 0),
          );
          return MapEntry(fieldId, opts);
        });
        return MapEntry(code, fields);
      });
    } catch (_) {
      return {};
    }
  }
}
