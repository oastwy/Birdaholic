import 'dart:convert';

class TransectTrackPoint {
  final String id;
  final DateTime time;
  final double latitude;
  final double longitude;
  final String note;

  const TransectTrackPoint({
    required this.id,
    required this.time,
    required this.latitude,
    required this.longitude,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'time': time.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'note': note,
  };

  factory TransectTrackPoint.fromJson(Map<String, dynamic> json) =>
      TransectTrackPoint(
        id: json['id']?.toString() ?? '',
        time:
            DateTime.tryParse(json['time']?.toString() ?? '') ?? DateTime.now(),
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        note: json['note']?.toString() ?? '',
      );
}

class SpeciesObservationEvent {
  final String eventId;
  final DateTime time;
  final double latitude;
  final double longitude;
  final String ebirdCode;
  final String speciesName;
  final int delta;
  final int countAfter;
  final String type;
  final String trackPointId;
  final String fieldId;
  final String option;
  final String parentOption;
  final String childOption;

  const SpeciesObservationEvent({
    required this.eventId,
    required this.time,
    required this.latitude,
    required this.longitude,
    required this.ebirdCode,
    required this.speciesName,
    required this.delta,
    required this.countAfter,
    this.type = 'species_count',
    this.trackPointId = '',
    this.fieldId = '',
    this.option = '',
    this.parentOption = '',
    this.childOption = '',
  });

  Map<String, dynamic> toJson() => {
    'eventId': eventId,
    'time': time.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'ebirdCode': ebirdCode,
    'speciesName': speciesName,
    'delta': delta,
    'countAfter': countAfter,
    'type': type,
    'trackPointId': trackPointId,
    'fieldId': fieldId,
    'option': option,
    'parentOption': parentOption,
    'childOption': childOption,
  };

  factory SpeciesObservationEvent.fromJson(Map<String, dynamic> json) =>
      SpeciesObservationEvent(
        eventId: json['eventId']?.toString() ?? '',
        time:
            DateTime.tryParse(json['time']?.toString() ?? '') ?? DateTime.now(),
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        ebirdCode: json['ebirdCode']?.toString() ?? '',
        speciesName: json['speciesName']?.toString() ?? '',
        delta: int.tryParse(json['delta']?.toString() ?? '') ?? 0,
        countAfter: int.tryParse(json['countAfter']?.toString() ?? '') ?? 0,
        type: json['type']?.toString() ?? 'species_count',
        trackPointId: json['trackPointId']?.toString() ?? '',
        fieldId: json['fieldId']?.toString() ?? '',
        option: json['option']?.toString() ?? '',
        parentOption: json['parentOption']?.toString() ?? '',
        childOption: json['childOption']?.toString() ?? '',
      );
}

class SurveySession {
  static const entryKeySeparator = '#entry_';

  final int? id;
  final String title;
  final String folderId;
  final DateTime startTime;
  DateTime? endTime;
  final double latitude;
  final double longitude;
  double? tideHeight;
  String? tideUnit;
  String? tideDirection; // '涨' / '落' / ''
  String? weather; // auto-filled from QWeather, e.g. '晴 25℃'
  final Map<String, int> observations; // ebird code -> count
  final Map<String, String> speciesNames; // ebird code -> Chinese name
  final Map<String, String> customValues; // field name -> value
  final Map<String, String> speciesNotes; // ebird code -> per-species note
  String notes; // overall survey notes
  // ebird code -> (fieldId -> value)  per-species custom field values
  final Map<String, Map<String, String>> speciesFields;
  // ebird code -> fieldId -> option -> count
  final Map<String, Map<String, Map<String, int>>> speciesFieldCounts;
  // ebird code -> fieldId -> parent option -> child option -> count
  final Map<String, Map<String, Map<String, Map<String, int>>>>
  nestedSpeciesFieldCounts;
  final String surveyMode; // point / transect
  final String activeTransectPointId;
  final List<TransectTrackPoint> transectTrack;
  final List<SpeciesObservationEvent> observationEvents;

  SurveySession({
    this.id,
    this.title = '',
    this.folderId = '',
    required this.startTime,
    this.endTime,
    required this.latitude,
    required this.longitude,
    this.tideHeight,
    this.tideUnit,
    this.tideDirection,
    this.weather,
    Map<String, int>? observations,
    Map<String, String>? speciesNames,
    Map<String, String>? customValues,
    Map<String, String>? speciesNotes,
    this.notes = '',
    Map<String, Map<String, String>>? speciesFields,
    Map<String, Map<String, Map<String, int>>>? speciesFieldCounts,
    Map<String, Map<String, Map<String, Map<String, int>>>>?
    nestedSpeciesFieldCounts,
    this.surveyMode = 'point',
    this.activeTransectPointId = '',
    List<TransectTrackPoint>? transectTrack,
    List<SpeciesObservationEvent>? observationEvents,
  }) : observations = observations ?? {},
       speciesNames = speciesNames ?? {},
       customValues = customValues ?? {},
       speciesNotes = speciesNotes ?? {},
       speciesFields = speciesFields ?? {},
       speciesFieldCounts = speciesFieldCounts ?? {},
       nestedSpeciesFieldCounts = nestedSpeciesFieldCounts ?? {},
       transectTrack = transectTrack ?? [],
       observationEvents = observationEvents ?? [];

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

  SurveySession copyWith({
    DateTime? Function()? endTime,
    String? title,
    String? folderId,
    double? Function()? tideHeight,
    String? Function()? tideUnit,
    String? Function()? tideDirection,
    String? Function()? weather,
    String? notes,
    String? surveyMode,
    String? activeTransectPointId,
    List<TransectTrackPoint>? transectTrack,
    List<SpeciesObservationEvent>? observationEvents,
  }) => SurveySession(
    id: id,
    title: title ?? this.title,
    folderId: folderId ?? this.folderId,
    startTime: startTime,
    endTime: endTime != null ? endTime() : this.endTime,
    latitude: latitude,
    longitude: longitude,
    tideHeight: tideHeight != null ? tideHeight() : this.tideHeight,
    tideUnit: tideUnit != null ? tideUnit() : this.tideUnit,
    tideDirection: tideDirection != null ? tideDirection() : this.tideDirection,
    weather: weather != null ? weather() : this.weather,
    notes: notes ?? this.notes,
    surveyMode: surveyMode ?? this.surveyMode,
    activeTransectPointId: activeTransectPointId ?? this.activeTransectPointId,
    transectTrack:
        transectTrack ??
        this.transectTrack
            .map(
              (p) => TransectTrackPoint(
                id: p.id,
                time: p.time,
                latitude: p.latitude,
                longitude: p.longitude,
                note: p.note,
              ),
            )
            .toList(),
    observationEvents:
        observationEvents ??
        this.observationEvents
            .map(
              (e) => SpeciesObservationEvent(
                eventId: e.eventId,
                time: e.time,
                latitude: e.latitude,
                longitude: e.longitude,
                ebirdCode: e.ebirdCode,
                speciesName: e.speciesName,
                delta: e.delta,
                countAfter: e.countAfter,
                type: e.type,
                trackPointId: e.trackPointId,
                fieldId: e.fieldId,
                option: e.option,
                parentOption: e.parentOption,
                childOption: e.childOption,
              ),
            )
            .toList(),
    observations: Map.from(observations),
    speciesNames: Map.from(speciesNames),
    customValues: Map.from(customValues),
    speciesNotes: Map.from(speciesNotes),
    speciesFields: {
      for (final e in speciesFields.entries) e.key: Map.from(e.value),
    },
    speciesFieldCounts: {
      for (final outer in speciesFieldCounts.entries)
        outer.key: {
          for (final inner in outer.value.entries)
            inner.key: Map.from(inner.value),
        },
    },
    nestedSpeciesFieldCounts: {
      for (final species in nestedSpeciesFieldCounts.entries)
        species.key: {
          for (final field in species.value.entries)
            field.key: {
              for (final parent in field.value.entries)
                parent.key: Map.from(parent.value),
            },
        },
    },
  );

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
      'title': title,
      'folderId': folderId,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'tideHeight': tideHeight,
      'tideUnit': tideUnit,
      'tideDirection': tideDirection,
      'weather': weather,
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
      'nestedSpeciesFieldCounts': jsonEncode(nestedSpeciesFieldCounts),
      'surveyMode': surveyMode,
      'activeTransectPointId': activeTransectPointId,
      'transectTrack': jsonEncode(
        transectTrack.map((p) => p.toJson()).toList(),
      ),
      'observationEvents': jsonEncode(
        observationEvents.map((e) => e.toJson()).toList(),
      ),
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
      title: map['title'] as String? ?? '',
      folderId: map['folderId'] as String? ?? '',
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
      tideDirection: map['tideDirection'] as String?,
      weather: map['weather'] as String?,
      observations: obs,
      speciesNames: names,
      customValues: customValues,
      notes: map['notes'] as String? ?? '',
      speciesNotes: _decodeStringMap(map['speciesNotes'] as String? ?? ''),
      speciesFields: speciesFields,
      speciesFieldCounts: speciesFieldCounts,
      nestedSpeciesFieldCounts: _decodeNestedFieldCounts(
        map['nestedSpeciesFieldCounts'] as String? ?? '',
      ),
      surveyMode: map['surveyMode'] as String? ?? 'point',
      activeTransectPointId: map['activeTransectPointId'] as String? ?? '',
      transectTrack: _decodeTrackPoints(map['transectTrack'] as String? ?? ''),
      observationEvents: _decodeObservationEvents(
        map['observationEvents'] as String? ?? '',
      ),
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

  static Map<String, Map<String, Map<String, Map<String, int>>>>
  _decodeNestedFieldCounts(String raw) {
    if (raw.isEmpty) return {};
    try {
      final outer = jsonDecode(raw) as Map<String, dynamic>;
      return outer.map((code, fieldsRaw) {
        final fields = (fieldsRaw as Map<String, dynamic>).map((
          fieldId,
          parentsRaw,
        ) {
          final parents = (parentsRaw as Map<String, dynamic>).map((
            parent,
            childrenRaw,
          ) {
            final children = (childrenRaw as Map<String, dynamic>).map(
              (child, count) =>
                  MapEntry(child, int.tryParse(count.toString()) ?? 0),
            );
            return MapEntry(parent, children);
          });
          return MapEntry(fieldId, parents);
        });
        return MapEntry(code, fields);
      });
    } catch (_) {
      return {};
    }
  }

  static List<TransectTrackPoint> _decodeTrackPoints(String raw) {
    if (raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(TransectTrackPoint.fromJson)
          .where((p) => p.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static List<SpeciesObservationEvent> _decodeObservationEvents(String raw) {
    if (raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(SpeciesObservationEvent.fromJson)
          .where((e) => e.eventId.isNotEmpty && e.ebirdCode.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
