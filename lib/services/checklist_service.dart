import 'dart:convert';

import 'package:http/http.dart' as http;

/// 世界名录（按国家 → 省/州）客户端。
/// 数据由服务器 `gen_checklists.py` 生成，nginx 静态服务于 `/checklists/`。
class ChecklistRegion {
  final String code;
  final String name; // eBird 英文名
  final String nameZh; // 中文名（查不到时等于英文名）
  final int count;

  /// 无国家级合集文件的地区（如台湾），下载时把这些子区代码合并去重。
  final List<String> memberCodes;

  const ChecklistRegion({
    required this.code,
    required this.name,
    required this.nameZh,
    required this.count,
    this.memberCodes = const [],
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
    return _foldGreaterChinaIntoCN(countries);
  }

  /// 港澳台并入中国：从国家列表移除独立的 HK / MO / TW，作为省加到中国下面。
  /// 香港 / 澳门有国家级名录文件（HK.json / MO.json）直接用；
  /// 台湾无国家级合集文件，记录其各县市代码，下载时客户端合并去重。
  List<ChecklistCountry> _foldGreaterChinaIntoCN(
      List<ChecklistCountry> countries) {
    const zhNames = {'HK': '香港', 'MO': '澳门', 'TW': '台湾'};
    final extras = <ChecklistRegion>[];
    for (final c in countries) {
      if (!zhNames.containsKey(c.code)) continue;
      if (c.code == 'TW') {
        final members = c.provinces
            .map((p) => p.code)
            .where((e) => e.isNotEmpty)
            .toList();
        final maxCount = c.provinces.isEmpty
            ? 0
            : c.provinces.map((p) => p.count).reduce((a, b) => a > b ? a : b);
        extras.add(ChecklistRegion(
          code: 'TW',
          name: 'Taiwan',
          nameZh: '台湾',
          count: maxCount,
          memberCodes: members,
        ));
      } else {
        extras.add(ChecklistRegion(
          code: c.code,
          name: c.name,
          nameZh: zhNames[c.code]!,
          count: c.provinces.isNotEmpty ? c.provinces.first.count : 0,
        ));
      }
    }
    if (extras.isEmpty) return countries;

    final result = <ChecklistCountry>[];
    for (final c in countries) {
      if (zhNames.containsKey(c.code)) continue; // 去掉独立的港澳台
      if (c.code == 'CN') {
        final existing = c.provinces.map((p) => p.code).toSet();
        final merged = [
          ...c.provinces,
          ...extras.where((r) => !existing.contains(r.code)),
        ]..sort((a, b) => a.display.compareTo(b.display));
        result.add(ChecklistCountry(
          code: c.code,
          name: c.name,
          nameZh: c.nameZh,
          provinceCount: merged.length,
          provinces: merged,
        ));
      } else {
        result.add(c);
      }
    }
    return result;
  }

  /// 合并多个地区名录（去重），用于无国家级文件的地区（如台湾各县市）。
  Future<List<String>> fetchRegionCodesUnion(List<String> regionCodes) async {
    final seen = <String>{};
    final out = <String>[];
    for (final rc in regionCodes) {
      try {
        for (final code in await fetchRegionCodes(rc)) {
          if (seen.add(code)) out.add(code);
        }
      } catch (_) {
        // 单个县市拉取失败不影响整体
      }
    }
    return out;
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
