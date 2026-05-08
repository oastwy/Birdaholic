import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/survey_session.dart';
import 'webdav_service.dart';

class ExportService {
  static final _df = DateFormat('yyyy-MM-dd HH:mm:ss');
  static final _dfDate = DateFormat('yyyy-MM-dd');

  /// Export and optionally upload to WebDAV.
  /// Returns a non-null error string if WebDAV upload failed (export itself always succeeds).
  static Future<String?> exportToExcel(List<SurveySession> sessions) async {
    final excel = Excel.createExcel();

    // ── Sheet 1: 调查汇总 ──────────────────────────────────────────────────────
    final summary = excel['调查汇总'];
    excel.setDefaultSheet('调查汇总');

    // Collect all custom field names across sessions
    final allCustomKeys = <String>{};
    final allSpeciesFieldKeys = <String>{};
    for (final s in sessions) {
      allCustomKeys.addAll(s.customValues.keys);
      for (final fields in s.speciesFields.values) {
        allSpeciesFieldKeys.addAll(fields.keys);
      }
    }
    final customKeys = allCustomKeys.toList()..sort();
    final speciesFieldKeys = allSpeciesFieldKeys.toList()..sort();

    final summaryHeaders = [
      '调查编号',
      '日期',
      '开始时间',
      '结束时间',
      '时长(分钟)',
      '纬度',
      '经度',
      '潮汐高度',
      '潮汐单位',
      '鸟种数',
      '记录总数',
      ...customKeys,
    ];
    _writeRow(summary, 0, summaryHeaders, header: true);

    for (int i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      final dur = s.endTime?.difference(s.startTime).inMinutes;
      final row = [
        'S${(i + 1).toString().padLeft(3, '0')}',
        _dfDate.format(s.startTime),
        _df.format(s.startTime),
        s.endTime != null ? _df.format(s.endTime!) : '',
        dur?.toString() ?? '',
        s.latitude.toStringAsFixed(6),
        s.longitude.toStringAsFixed(6),
        s.tideHeight?.toStringAsFixed(3) ?? '',
        s.tideUnit ?? '',
        s.speciesCount.toString(),
        s.totalCount.toString(),
        ...customKeys.map((k) => s.customValues[k] ?? ''),
      ];
      _writeRow(summary, i + 1, row);
    }

    // ── Sheet 2: 物种记录明细 ──────────────────────────────────────────────────
    final details = excel['物种记录'];
    final detailHeaders = [
      '调查编号',
      '日期',
      '时间',
      '纬度',
      '经度',
      '潮汐高度',
      '中文名',
      'eBird代码',
      '数量',
      ...speciesFieldKeys,
      '物种备注',
      ...customKeys,
    ];
    _writeRow(details, 0, detailHeaders, header: true);

    int row = 1;
    for (int i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      final sid = 'S${(i + 1).toString().padLeft(3, '0')}';
      final entries =
          s.observations.entries.where((e) => e.value > 0).toList()
            ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in entries) {
        final code = SurveySession.speciesCodeForKey(e.key);
        final fields = s.speciesFields[e.key] ?? {};
        _writeRow(details, row, [
          sid,
          _dfDate.format(s.startTime),
          _df.format(s.startTime),
          s.latitude.toStringAsFixed(6),
          s.longitude.toStringAsFixed(6),
          s.tideHeight?.toStringAsFixed(3) ?? '',
          s.speciesNames[e.key] ?? s.speciesNames[code] ?? code,
          code,
          e.value.toString(),
          ...speciesFieldKeys.map((k) => fields[k] ?? ''),
          s.speciesNotes[e.key] ?? '',
          ...customKeys.map((k) => s.customValues[k] ?? ''),
        ]);
        row++;
      }
    }

    // ── Save & share ─────────────────────────────────────────────────────────
    final bytes = excel.encode();
    if (bytes == null) return null;

    final dir = await getApplicationDocumentsDirectory();
    final pointName =
        sessions.isNotEmpty
            ? (sessions.first.customValues['位点名称'] ?? '').replaceAll(
              RegExp(r'[^\w一-鿿]'),
              '_',
            )
            : '';
    final datePart = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final filename =
        pointName.isEmpty
            ? 'bird_survey_$datePart.xlsx'
            : 'bird_survey_${pointName}_$datePart.xlsx';
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: filename,
      text: '鸟类调查数据导出',
    );

    // Auto-upload to WebDAV if configured.
    final config = await WebDavConfig.load();
    if (config.isConfigured) {
      return WebDavService.uploadFile(config, file, filename);
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
