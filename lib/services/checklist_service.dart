import 'dart:convert';

import 'package:http/http.dart' as http;

/// 世界名录（按国家 → 省/州）客户端。
/// 数据由服务器 `gen_checklists.py` 生成，nginx 静态服务于 `/checklists/`。
class ChecklistRegion {
  final String code;
  final String name; // eBird 英文名
  final String nameZh; // 中文名（查不到时等于英文名）
  final int count;

  const ChecklistRegion({
    required this.code,
    required this.name,
    required this.nameZh,
    required this.count,
  });

  /// 展示名：中文优先，英文兜底。
  String get display => nameZh.trim().isNotEmpty ? nameZh : name;

  factory ChecklistRegion.fromJson(Map<String, dynamic> j) => ChecklistRegion(
        code: (j['code'] as String? ?? '').trim(),
        name: (j['name'] as String? ?? '').trim(),
        nameZh: (j['name_zh'] as String? ?? '').trim(),
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

class ChecklistCountry {
  final String code;
  final String name;
  final String nameZh;
  final int provinceCount;
  final List<ChecklistRegion> provinces;

  const ChecklistCountry({
    required this.code,
    required this.name,
    required this.nameZh,
    required this.provinceCount,
    required this.provinces,
  });

  String get display => nameZh.trim().isNotEmpty ? nameZh : name;

  factory ChecklistCountry.fromJson(Map<String, dynamic> j) {
    final provs = (j['provinces'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChecklistRegion.fromJson)
        .toList();
    return ChecklistCountry(
      code: (j['code'] as String? ?? '').trim(),
      name: (j['name'] as String? ?? '').trim(),
      nameZh: (j['name_zh'] as String? ?? '').trim(),
      provinceCount: (j['province_count'] as num?)?.toInt() ?? provs.length,
      provinces: provs,
    );
  }
}

class ChecklistService {
  static const String defaultBaseUrl = 'https://birding.today';

  final String baseUrl;
  final http.Client _client;

  ChecklistService({this.baseUrl = defaultBaseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// 国家 → 省 目录树（一次拉取，按国家中文名排序）。
  Future<List<ChecklistCountry>> fetchIndex() async {
    final resp = await _client
        .get(Uri.parse('$baseUrl/checklists/_index.json'))
        .timeout(const Duration(seconds: 25));
    if (resp.statusCode != 200) {
      throw Exception('获取世界名录目录失败：${resp.statusCode}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final countries = (data['countries'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChecklistCountry.fromJson)
        .where((c) => c.code.isNotEmpty)
        .toList();
    return countries;
  }

  /// 某个地区（国家或省）名录里的 eBird 物种代码列表。
  /// 精简格式直接读 `codes`；兼容旧"胖"格式时从 `species[].code` 取。
  Future<List<String>> fetchRegionCodes(String regionCode) async {
    final resp = await _client
        .get(Uri.parse('$baseUrl/checklists/$regionCode.json'))
        .timeout(const Duration(seconds: 25));
    if (resp.statusCode != 200) {
      throw Exception('获取名录失败（$regionCode）：${resp.statusCode}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final codes = data['codes'];
    if (codes is List) {
      return codes.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList();
    }
    // 兼容旧格式
    return (data['species'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((s) => (s['code'] as String? ?? '').trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
}
