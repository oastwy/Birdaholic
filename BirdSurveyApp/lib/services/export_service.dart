import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/custom_field.dart';
import '../models/survey_session.dart';
import 'species_meta_service.dart';
import 'webdav_service.dart';

enum ExportTemplate { full, simple }

class ExportService {
  static final _df = DateFormat('yyyy-MM-dd HH:mm');
  static final _dfTime = DateFormat('HH:mm');
  static final _dfDate = DateFormat('yyyy-MM-dd');

  // Fixed column order matching the screenshot
  static const _fixedHeaders = [
    '县市',
    '地点名称',
    '风电场',
    '经度',
    '纬度',
    '类',
    '生境',
    '海拔',
    '潮高',
    '潮涨/',
    '时间',
    '结束时',
    '年',
    '月',
    '日',
    '天气',
    '观察',
    '记录',
    '物种',
    '数量',
  ];

  // Species meta columns appended after 数量
  static const _metaHeaders = [
    '拉丁名',
    '目',
    '目英文',
    '科',
    '科英文',
    '居留型',
    '省重点',
    '三有',
    '国重',
    '红色名录',
    'IUCN',
    'CITES',
  ];

  /// Lookup helper for custom values with fallback key variants
  static String _cv(Map<String, String> cv, List<String> keys) {
    for (final k in keys) {
      final v = cv[k];
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }

  /// Export and optionally upload to WebDAV.
  /// Returns a non-null error string if WebDAV upload failed.
  /// [projectName] overrides the filename prefix when exporting a whole project.
  static Future<String?> exportToExcel(
    List<SurveySession> sessions, {
    String? projectName,
    List<CustomField>? speciesFieldDefs,
    ExportTemplate? template,
  }) async {
    // Load species field defs from prefs if not supplied by caller
    final fieldDefs = speciesFieldDefs ?? await _loadSpeciesFieldDefs();

    final prefs = await SharedPreferences.getInstance();
    final selectedTemplate =
        template ??
        (prefs.getString('export_template') == 'simple'
            ? ExportTemplate.simple
            : ExportTemplate.full);
    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    // ── Sheet 1: 调查汇总 ─────────────────────────────────────────────────────
    final summary = excel['调查汇总'];
    excel.setDefaultSheet('调查汇总');

    final summaryHeaders = [
      '调查编号',
      '日期',
      '开始时间',
      '结束时间',
      '时长(分钟)',
      '县市',
      '地点名称',
      '风电场',
      '经度',
      '纬度',
      '天气',
      '潮高',
      '潮涨/',
      '鸟种数',
      '记录总数',
    ];
    _writeRow(summary, 0, summaryHeaders, header: true);

    for (int i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      final dur = s.endTime?.difference(s.startTime).inMinutes;
      final cv = s.customValues;
      _writeRow(summary, i + 1, [
        'S${(i + 1).toString().padLeft(3, '0')}',
        _dfDate.format(s.startTime),
        _df.format(s.startTime),
        s.endTime != null ? _df.format(s.endTime!) : '',
        dur?.toString() ?? '',
        _cv(cv, ['县市']),
        _cv(cv, ['位点名称', '地点名称']),
        _cv(cv, ['风电场']),
        s.longitude.toStringAsFixed(6),
        s.latitude.toStringAsFixed(6),
        s.weather ?? '',
        s.tideHeight?.toStringAsFixed(3) ?? '',
        s.tideDirection ?? '',
        s.speciesCount.toString(),
        s.totalCount.toString(),
      ]);
    }

    // ── Sheet 2: 物种记录（flat, one row per species per session） ────────────
    final details = excel['物种记录'];
    final metaHeaders =
        selectedTemplate == ExportTemplate.full ? _metaHeaders : <String>[];
    final nestedParentFieldId = prefs.getString('nested_parent_field_id') ?? '';
    final nestedChildFieldId = prefs.getString('nested_child_field_id') ?? '';
    final nestedFieldDefs = <CustomField>[
      ...fieldDefs.where((f) => f.type == FieldType.nestedSelect),
    ];
    final relationParent = _fieldById(fieldDefs, nestedParentFieldId);
    final relationChild = _fieldById(fieldDefs, nestedChildFieldId);
    final relationId = '${nestedParentFieldId}__nested__$nestedChildFieldId';
    if (relationParent != null &&
        relationChild != null &&
        relationParent.id != relationChild.id &&
        relationParent.options.isNotEmpty &&
        relationChild.options.isNotEmpty) {
      nestedFieldDefs.insert(
        0,
        CustomField(
          id: relationId,
          name: '${relationParent.name}-${relationChild.name}',
          type: FieldType.nestedSelect,
          nestedOptions: {
            for (final option in relationParent.options)
              option: relationChild.options,
          },
        ),
      );
    }
    final flatFieldDefs =
        fieldDefs
            .where(
              (f) =>
                  f.type != FieldType.nestedSelect &&
                  f.id != nestedParentFieldId &&
                  f.id != nestedChildFieldId,
            )
            .toList();
    final flatFieldHeaders = flatFieldDefs.map((f) => f.name).toList();
    final nestedHeaders = nestedFieldDefs.expand(
      (f) => ['${f.name}一级', '${f.name}二级'],
    );
    _writeRow(details, 0, [
      ..._fixedHeaders,
      ...metaHeaders,
      ...flatFieldHeaders,
      ...nestedHeaders,
    ], header: true);

    int row = 1;
    for (int i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      final cv = s.customValues;
      final t = s.startTime;

      final entries =
          s.observations.entries.where((e) => e.value > 0).toList()
            ..sort((a, b) => b.value.compareTo(a.value));

      final transectEvents =
          s.surveyMode == 'transect'
              ? s.observationEvents
                  .where((e) => e.type == 'species_count' && e.delta > 0)
                  .toList()
              : <SpeciesObservationEvent>[];
      if (transectEvents.isNotEmpty) {
        for (final ev in transectEvents) {
          final zhName =
              ev.speciesName.isNotEmpty ? ev.speciesName : ev.ebirdCode;
          final meta = SpeciesMetaService.lookup(zhName);
          final metaValues =
              meta != null
                  ? metaHeaders.map((h) => meta.toExportMap()[h] ?? '').toList()
                  : List.filled(metaHeaders.length, '');
          _writeRow(details, row, [
            _cv(cv, ['县市']),
            _cv(cv, ['位点名称', '地点名称']),
            _cv(cv, ['风电场']),
            ev.longitude.toStringAsFixed(6),
            ev.latitude.toStringAsFixed(6),
            _cv(cv, ['类', '调查类型', '类型']),
            _cv(cv, ['生境', '生境类型']),
            _cv(cv, ['海拔']),
            s.tideHeight?.toStringAsFixed(3) ?? '',
            s.tideDirection ?? '',
            _dfTime.format(ev.time),
            s.endTime != null ? _df.format(s.endTime!) : '',
            ev.time.year.toString(),
            ev.time.month.toString(),
            ev.time.day.toString(),
            s.weather ?? '',
            _cv(cv, ['观察', '观察者', '调查者']),
            _cv(cv, ['记录', '记录者']),
            zhName,
            ev.delta.toString(),
            ...metaValues,
            ...List.filled(flatFieldHeaders.length, ''),
            ...List.filled(nestedFieldDefs.length * 2, ''),
          ]);
          row++;
        }
        continue;
      }

      for (final e in entries) {
        final code = SurveySession.speciesCodeForKey(e.key);
        final zhName = s.speciesNames[e.key] ?? s.speciesNames[code] ?? code;
        final meta = SpeciesMetaService.lookup(zhName);
        final metaValues =
            meta != null
                ? metaHeaders.map((h) => meta.toExportMap()[h] ?? '').toList()
                : List.filled(metaHeaders.length, '');

        final fieldValues =
            flatFieldDefs.map((f) {
              // For select fields: use option counts if available (e.g. 飞行×5 停歇×3)
              final counts = s.speciesFieldCounts[code]?[f.id];
              if (counts != null && counts.isNotEmpty) {
                final parts = counts.entries
                    .where((c) => c.value > 0)
                    .map((c) => '${c.key}×${c.value}')
                    .join(' ');
                if (parts.isNotEmpty) return parts;
              }
              // Fall back to single stored value
              return s.speciesFields[e.key]?[f.id] ?? '';
            }).toList();

        final nestedRows = _nestedRowsFor(s, code, nestedFieldDefs);
        final rowsToWrite =
            nestedRows.isEmpty
                ? [List<String>.filled(nestedFieldDefs.length * 2, '')]
                : nestedRows;
        for (final nestedValues in rowsToWrite) {
          final rowCount =
              nestedRows.isEmpty
                  ? e.value.toString()
                  : _nestedRowCount(
                    s,
                    code,
                    nestedFieldDefs,
                    nestedValues,
                  ).toString();
          _writeRow(details, row, [
            // 固定列
            _cv(cv, ['县市']),
            _cv(cv, ['位点名称', '地点名称']),
            _cv(cv, ['风电场']),
            s.longitude.toStringAsFixed(6),
            s.latitude.toStringAsFixed(6),
            _cv(cv, ['类', '调查类型', '类型']),
            _cv(cv, ['生境', '生境类型']),
            _cv(cv, ['海拔']),
            s.tideHeight?.toStringAsFixed(3) ?? '',
            s.tideDirection ?? '',
            _dfTime.format(t),
            s.endTime != null ? _df.format(s.endTime!) : '',
            t.year.toString(),
            t.month.toString(),
            t.day.toString(),
            s.weather ?? '',
            _cv(cv, ['观察', '观察者', '调查者']),
            _cv(cv, ['记录', '记录者']),
            zhName,
            rowCount,
            // 物种分类与保护信息
            ...metaValues,
            // 自定义行为字段
            ...fieldValues,
            ...nestedValues,
          ]);
          row++;
        }
      }
    }

    final transectSessions = sessions.where((s) => s.transectTrack.isNotEmpty);
    if (transectSessions.isNotEmpty) {
      final trackSheet = excel['样线轨迹'];
      _writeRow(trackSheet, 0, [
        '调查编号',
        '县市',
        '地点名称',
        '风电场',
        '轨迹点ID',
        '时间',
        '经度',
        '纬度',
        '备注',
      ], header: true);
      var trackRow = 1;
      for (int i = 0; i < sessions.length; i++) {
        final s = sessions[i];
        final cv = s.customValues;
        for (final p in s.transectTrack) {
          _writeRow(trackSheet, trackRow, [
            'S${(i + 1).toString().padLeft(3, '0')}',
            _cv(cv, ['县市']),
            _cv(cv, ['位点名称', '地点名称']),
            _cv(cv, ['风电场']),
            p.id,
            _df.format(p.time),
            p.longitude.toStringAsFixed(6),
            p.latitude.toStringAsFixed(6),
            p.note,
          ]);
          trackRow++;
        }
      }
    }

    // ── Save & share ──────────────────────────────────────────────────────────
    final bytes = excel.encode();
    if (bytes == null) return null;

    final dir = await getApplicationDocumentsDirectory();
    final sessionDate =
        sessions.isNotEmpty
            ? DateFormat('yyyyMMdd').format(sessions.first.startTime)
            : DateFormat('yyyyMMdd').format(DateTime.now());
    final String prefix;
    if (projectName != null && projectName.isNotEmpty) {
      prefix = projectName.replaceAll(RegExp(r'[^\w一-鿿]'), '_');
    } else {
      final pointName = sessions
          .map((s) => _cv(s.customValues, ['位点名称', '地点名称']))
          .firstWhere((n) => n.isNotEmpty, orElse: () => '')
          .replaceAll(RegExp(r'[^\w一-鿿]'), '_');
      prefix = pointName;
    }
    final filename =
        prefix.isEmpty ? '$sessionDate.xlsx' : '${prefix}_$sessionDate.xlsx';
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: filename,
      text: '鸟类调查数据导出',
    );

    final config = await WebDavConfig.load();
    if (config.isConfigured) {
      return WebDavService.uploadFile(config, file, filename);
    }
    return null;
  }

  static List<List<String>> _nestedRowsFor(
    SurveySession session,
    String code,
    List<CustomField> fields,
  ) {
    if (fields.isEmpty) return [];
    final result = <List<String>>[];
    for (final field in fields) {
      final parents = session.nestedSpeciesFieldCounts[code]?[field.id] ?? {};
      for (final parent in parents.entries) {
        for (final child in parent.value.entries.where((e) => e.value > 0)) {
          final row = <String>[];
          for (final f in fields) {
            if (f.id == field.id) {
              row.addAll([parent.key, child.key]);
            } else {
              row.addAll(['', '']);
            }
          }
          result.add(row);
        }
      }
    }
    return result;
  }

  static int _nestedRowCount(
    SurveySession session,
    String code,
    List<CustomField> fields,
    List<String> nestedValues,
  ) {
    for (int i = 0; i < fields.length; i++) {
      final parent = nestedValues[i * 2];
      final child = nestedValues[i * 2 + 1];
      if (parent.isEmpty || child.isEmpty) continue;
      final count =
          session.nestedSpeciesFieldCounts[code]?[fields[i]
              .id]?[parent]?[child];
      if (count != null) return count;
    }
    return session.speciesTotals()[code] ?? 0;
  }

  static Future<List<CustomField>> _loadSpeciesFieldDefs() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('species_field_defs') ?? '';
    return CustomField.decodeList(json);
  }

  static CustomField? _fieldById(List<CustomField> fields, String id) {
    for (final field in fields) {
      if (field.id == id) return field;
    }
    return null;
  }

  static void _writeRow(
    Sheet sheet,
    int rowIdx,
    List<String> values, {
    bool header = false,
  }) {
    for (int col = 0; col < values.length; col++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIdx),
      );
      cell.value = TextCellValue(values[col]);
      if (header) {
        cell.cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.fromHexString('#2E7D32'),
          fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        );
      }
    }
  }
}
