import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/storage.dart';
import '../utils/file_picker_guard.dart';

/// 我的观鸟清单（life list）：导入 eBird 的 MyEBirdData.csv 或「中国观鸟记录中心」
/// (birdreport.cn) 导出的 鸟种数据导出.xlsx，或在鸟种页手动标记「已见」。
/// 配合打卡筛选里的「未见过（潜在新种）」使用。
class LifeListScreen extends StatefulWidget {
  final StorageService storage;
  const LifeListScreen({super.key, required this.storage});

  @override
  State<LifeListScreen> createState() => _LifeListScreenState();
}

class _LifeListScreenState extends State<LifeListScreen> {
  bool _importing = false;

  static const _green = Color(0xFF2d5016);

  /// 完整 CSV 状态机解析，正确处理引号内的逗号与换行。
  static List<List<String>> _parseCsv(String content) {
    final rows = <List<String>>[];
    var row = <String>[];
    final sb = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < content.length; i++) {
      final c = content[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < content.length && content[i + 1] == '"') {
            sb.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          sb.write(c);
        }
      } else {
        if (c == '"') {
          inQuotes = true;
        } else if (c == ',') {
          row.add(sb.toString());
          sb.clear();
        } else if (c == '\n') {
          row.add(sb.toString());
          sb.clear();
          rows.add(row);
          row = <String>[];
        } else if (c == '\r') {
          // 跳过
        } else {
          sb.write(c);
        }
      }
    }
    if (sb.isNotEmpty || row.isNotEmpty) {
      row.add(sb.toString());
      rows.add(row);
    }
    return rows;
  }

  /// 从 eBird CSV 内容里抽出所有学名（按表头里含 "scientific" 的列）。
  static List<String> extractScientificNames(String content) {
    final rows = _parseCsv(content);
    if (rows.isEmpty) return const [];
    final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
    var idx = header.indexWhere((h) => h.contains('scientific'));
    final fromHeader = idx >= 0;
    if (idx < 0 && header.length >= 3) idx = 2; // eBird 典型列位兜底
    if (idx < 0) return const [];
    final out = <String>[];
    for (final r in rows.skip(1)) {
      if (idx < r.length) {
        final s = r[idx].trim();
        if (s.isNotEmpty) out.add(s);
      }
    }
    // 走兜底列（非表头命中）时抽样校验确实像学名二名，否则判定选错列/选错文件、
    // 不把任意 CSV 的第 3 列当学名导入假记录。
    if (!fromHeader && !_columnLooksLikeBinomials(out)) return const [];
    return out;
  }

  /// 抽样判断一列取值是否像学名二名（首词首字母大写 + 空格 + 小写种加词）。
  static bool _columnLooksLikeBinomials(List<String> values) {
    final sample = values.where((s) => s.trim().isNotEmpty).take(8).toList();
    if (sample.isEmpty) return false;
    final re = RegExp(r'^[A-Z][a-z]+ [a-z]');
    final hits = sample.where((s) => re.hasMatch(s.trim())).length;
    return hits >= (sample.length / 2).ceil();
  }

  static int _colToIndex(String letters) {
    var n = 0;
    for (final u in letters.codeUnits) {
      n = n * 26 + (u - 64); // 'A'(65) → 1
    }
    return n - 1; // 0-based
  }

  static String _xmlUnescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&'); // &amp; 最后，避免二次解码

  /// 解析「中国观鸟记录中心」(birdreport.cn) 导出的 .xlsx，抽出「拉丁名」列的学名。
  /// 导出列：鸟种编号 / 中文名 / 拉丁名 / 目 / 科 / 数量（单 sheet）；
  /// 兼容 t="s"(共享串) / t="inlineStr" / t="str"或数字(值直接在 `<v>`)。
  static List<String> extractBirdreportLatinNames(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    // 按 sheet 序号收集全部工作表——不能取「zip 里第一个」：多表、或 sheet10.xml 在
    // sheet2.xml 之前的迭代顺序，会选错表。
    final sheets = <int, String>{};
    String? sharedXml;
    for (final f in archive) {
      final name = f.name;
      if (name.startsWith('xl/worksheets/') && name.endsWith('.xml')) {
        final m = RegExp(r'sheet(\d+)\.xml$').firstMatch(name);
        final idx = m != null ? int.parse(m.group(1)!) : 9000 + sheets.length;
        sheets[idx] = utf8.decode(f.content as List<int>, allowMalformed: true);
      } else if (name == 'xl/sharedStrings.xml') {
        sharedXml = utf8.decode(f.content as List<int>, allowMalformed: true);
      }
    }
    if (sheets.isEmpty) return const [];
    // 共享串表（若有）
    final shared = <String>[];
    if (sharedXml != null) {
      for (final si
          in RegExp(r'<si>(.*?)</si>', dotAll: true).allMatches(sharedXml)) {
        final inner = si.group(1) ?? '';
        final sb = StringBuffer();
        for (final t
            in RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).allMatches(inner)) {
          sb.write(t.group(1) ?? '');
        }
        shared.add(_xmlUnescape(sb.toString()));
      }
    }
    final order = sheets.keys.toList()..sort();
    // ① 优先：任意工作表里按表头找到「拉丁名」列。
    for (final k in order) {
      final names = _latinNamesFromSheetXml(sheets[k]!, shared, sciColHint: -1);
      if (names.isNotEmpty) return names;
    }
    // ② 兜底：记录中心固定列序（拉丁名在第 3 列 C），仅当该列取值确实像学名二名时才用——
    //    避免把别的表/别的列当学名导入假数据。只在首表上兜底。
    final fixed =
        _latinNamesFromSheetXml(sheets[order.first]!, shared, sciColHint: 2);
    if (fixed.isNotEmpty && _columnLooksLikeBinomials(fixed)) return fixed;
    return const [];
  }

  /// 从单张 worksheet 的 XML 抽某列。sciColHint<0=按表头找「拉丁名」列（找不到返回空，
  /// 让上层试下一张表）；sciColHint>=0=直接用该列（兜底用）。
  static List<String> _latinNamesFromSheetXml(
      String sheetXml, List<String> shared,
      {required int sciColHint}) {
    final grid = <int, Map<int, String>>{};
    for (final rowM
        in RegExp(r'<row[^>]*>(.*?)</row>', dotAll: true).allMatches(sheetXml)) {
      final rowXml = rowM.group(1) ?? '';
      for (final cM in RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true)
          .allMatches(rowXml)) {
        final attrs = cM.group(1) ?? '';
        final body = cM.group(2) ?? '';
        final ref = RegExp(r'r="([A-Z]+)(\d+)"').firstMatch(attrs);
        if (ref == null) continue;
        final col = _colToIndex(ref.group(1)!);
        final rowIdx = int.parse(ref.group(2)!);
        String value;
        if (RegExp(r't="s"').hasMatch(attrs)) {
          final raw =
              RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body)?.group(1) ??
                  '';
          final idx = int.tryParse(raw.trim());
          value = (idx != null && idx >= 0 && idx < shared.length)
              ? shared[idx]
              : '';
        } else if (RegExp(r't="inlineStr"').hasMatch(attrs)) {
          // 富文本会拆成多个 <t> run，需全部拼接（与共享串一致），否则学名被截断。
          final sb = StringBuffer();
          for (final t
              in RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).allMatches(body)) {
            sb.write(t.group(1) ?? '');
          }
          value = _xmlUnescape(sb.toString());
        } else {
          value = _xmlUnescape(
              RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body)?.group(1) ??
                  '');
        }
        grid.putIfAbsent(rowIdx, () => <int, String>{})[col] = value;
      }
    }
    if (grid.isEmpty) return const [];
    final rowKeys = grid.keys.toList()..sort();
    var sciCol = sciColHint;
    if (sciCol < 0) {
      final header = grid[rowKeys.first] ?? const <int, String>{};
      header.forEach((c, v) {
        final low = v.trim().toLowerCase();
        if (sciCol < 0 &&
            (v.contains('拉丁') ||
                low.contains('scientific') ||
                low.contains('latin'))) {
          sciCol = c;
        }
      });
      if (sciCol < 0) return const []; // 这张表没有「拉丁名」表头，交给上层试下一张
    }
    final out = <String>[];
    for (final rk in rowKeys.skip(1)) {
      final v = (grid[rk]?[sciCol] ?? '').trim();
      if (v.isNotEmpty) out.add(v);
    }
    return out;
  }

  /// 统一导入：birdreport=true 走记录中心 .xlsx，否则走 eBird .csv。
  Future<void> _pickAndImport({required bool birdreport}) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final result = await FilePickerGuard.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final bytes = picked.bytes;
      if (bytes == null) {
        _snack('读取文件失败，请重试或换一个文件');
        return;
      }
      final lower = picked.name.toLowerCase();
      final List<String> names;
      if (birdreport) {
        if (!lower.endsWith('.xlsx')) {
          _snack('请选择记录中心导出的 .xlsx 文件（鸟种数据导出.xlsx）');
          return;
        }
        names = extractBirdreportLatinNames(bytes);
        if (names.isEmpty) {
          _snack('没在文件里找到「拉丁名」列，确认是记录中心导出的鸟种数据吗？');
          return;
        }
      } else {
        if (!lower.endsWith('.csv')) {
          _snack('请选择 eBird 导出的 .csv 文件（MyEBirdData.csv）');
          return;
        }
        names = extractScientificNames(utf8.decode(bytes, allowMalformed: true));
        if (names.isEmpty) {
          _snack('没在文件里找到学名列，确认是 eBird 的 MyEBirdData.csv？');
          return;
        }
      }
      final added = await widget.storage.mergeLifeList(names);
      if (!mounted) return;
      setState(() {});
      _snack('导入成功：识别 ${names.length} 条，新增 $added 种，'
          '清单共 ${widget.storage.lifeListCount} 种');
    } catch (e) {
      _snack('导入失败：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空观鸟清单？'),
        content: const Text('会清除全部「已见」记录（不影响打卡进度与收藏）。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.storage.clearLifeList();
    if (!mounted) return;
    setState(() {});
    _snack('已清空');
  }

  Future<void> _openExportPage() async {
    final uri = Uri.parse('https://ebird.org/downloadMyData');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _snack('打不开浏览器，请手动访问 ebird.org/downloadMyData');
    } catch (_) {
      _snack('打不开浏览器，请手动访问 ebird.org/downloadMyData');
    }
  }

  Future<void> _openBirdreport() async {
    final uri = Uri.parse('https://www.birdreport.cn');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _snack('打不开浏览器，请手动访问 birdreport.cn');
    } catch (_) {
      _snack('打不开浏览器，请手动访问 birdreport.cn');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.storage.lifeListCount;
    return Scaffold(
      appBar: AppBar(title: const Text('我的观鸟清单')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Card(
            color: const Color(0xFFEFF5E9),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const Icon(Icons.checklist_rtl, color: _green, size: 34),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$count',
                            style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: _green)),
                        const Text('已记录的物种（life list）'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // —— 从 eBird 导入 ——
          const Text('从 eBird 导入',
              style: TextStyle(fontWeight: FontWeight.w800, color: _green)),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _importing ? null : () => _pickAndImport(birdreport: false),
            icon: _importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file),
            label: Text(_importing ? '正在导入…' : '导入 eBird CSV'),
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _openExportPage,
            icon: const Icon(Icons.open_in_new),
            label: const Text('打开 eBird 导出页'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              foregroundColor: _green,
            ),
          ),
          const SizedBox(height: 18),
          // —— 从中国观鸟记录中心导入 ——
          const Text('从中国观鸟记录中心导入',
              style: TextStyle(fontWeight: FontWeight.w800, color: _green)),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _importing ? null : () => _pickAndImport(birdreport: true),
            icon: _importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.table_chart_outlined),
            label: Text(_importing ? '正在导入…' : '导入记录中心 Excel'),
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _openBirdreport,
            icon: const Icon(Icons.open_in_new),
            label: const Text('打开记录中心 (birdreport.cn)'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              foregroundColor: _green,
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: count == 0 ? null : _clear,
            icon: const Icon(Icons.delete_outline),
            label: const Text('清空清单'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          ),
          const SizedBox(height: 20),
          const _Help(),
        ],
      ),
    );
  }
}

class _Help extends StatelessWidget {
  const _Help();

  @override
  Widget build(BuildContext context) {
    final hint = TextStyle(fontSize: 13, height: 1.5, color: Colors.grey[700]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('怎么拿到 eBird 清单文件？',
            style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          'eBird 出于隐私不开放「读取他人 life list」的接口，但你可以导出自己的数据：\n'
          '1. 点上面「打开 eBird 导出页」（即 ebird.org/downloadMyData），登录后申请导出；\n'
          '2. 稍后邮件会收到一个压缩包，解压得到 MyEBirdData.csv；\n'
          '3. 把它存到手机，回来点「导入 eBird CSV」选择它。\n'
          '导入只读取「学名」一列，可重复导入更新（已有的不会重复计）。',
          style: hint,
        ),
        const SizedBox(height: 14),
        const Text('怎么拿到「观鸟记录中心」清单文件？',
            style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          '国内观鸟人常用「中国观鸟记录中心」(birdreport.cn)：\n'
          '1. 点上面「打开记录中心」，登录后在个人记录里导出鸟种数据；\n'
          '2. 会得到一个「鸟种数据导出.xlsx」（含中文名、拉丁名等列）；\n'
          '3. 存到手机，回来点「导入记录中心 Excel」选择它。\n'
          '按「拉丁名」匹配；记录中心与 App 分类偶有差异时，个别种可能匹配不上。',
          style: hint,
        ),
        const SizedBox(height: 14),
        const Text('还能手动标记', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          '在鸟种页（预习详情）点「已见 / 未见」，也会记进这份清单。',
          style: hint,
        ),
        const SizedBox(height: 14),
        const Text('清单有什么用', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          '打卡时在「筛选 → 范围」里选「未见过（潜在新种）」，就只练你还没见过的鸟；'
          '再叠加 eBird 地点筛选，等于「这个地方我还没见过的鸟」，很适合出门前突击。',
          style: hint,
        ),
      ],
    );
  }
}
