import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

class EbirdLocationPreset {
  final String label;
  final String code;
  final String note;

  const EbirdLocationPreset({
    required this.label,
    required this.code,
    this.note = '',
  });
}

class EbirdSpeciesMatch {
  final String code;
  final String scientificName;
  final String commonName;

  const EbirdSpeciesMatch({
    required this.code,
    this.scientificName = '',
    this.commonName = '',
  });
}

class EBirdService {
  static const List<EbirdLocationPreset> presets = [
    EbirdLocationPreset(label: '中国', code: 'CN', note: '全国名录'),
    EbirdLocationPreset(label: '北京', code: 'CN-11', note: '省级地区'),
    EbirdLocationPreset(label: '上海', code: 'CN-31', note: '省级地区'),
    EbirdLocationPreset(label: '浙江', code: 'CN-33', note: '省级地区'),
    EbirdLocationPreset(label: '福建', code: 'CN-35', note: '省级地区'),
    EbirdLocationPreset(label: '广东', code: 'CN-44', note: '省级地区'),
    EbirdLocationPreset(label: '广西', code: 'CN-45', note: '省级地区'),
    EbirdLocationPreset(label: '海南', code: 'CN-46', note: '省级地区'),
    EbirdLocationPreset(label: '四川', code: 'CN-51', note: '省级地区'),
    EbirdLocationPreset(label: '云南', code: 'CN-53', note: '省级地区'),
    EbirdLocationPreset(label: '西藏', code: 'CN-54', note: '省级地区'),
    EbirdLocationPreset(label: '青海', code: 'CN-63', note: '省级地区'),
    EbirdLocationPreset(label: '新疆', code: 'CN-65', note: '省级地区'),
    EbirdLocationPreset(
      label: '那邦',
      code: 'L3124991',
      note: 'Nabang [General Area]',
    ),
    EbirdLocationPreset(
      label: '盈江湿地公园',
      code: 'L13803456',
      note: 'Yingjiang Wetland Park',
    ),
    EbirdLocationPreset(label: '石梯村', code: 'L8245010', note: 'Shiti Village'),
  ];

  final String apiKey;
  final http.Client _client;

  EBirdService({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  static List<EbirdLocationPreset> searchPresets(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return presets;
    return presets.where((item) {
      return item.label.toLowerCase().contains(normalized) ||
          item.note.toLowerCase().contains(normalized) ||
          item.code.toLowerCase().contains(normalized);
    }).toList();
  }

  // ── 地区代码 ↔ 中文名（内置 region_names_zh.json，供按名搜索）──────────
  static Map<String, String>? _regionNames;

  /// 加载「eBird 地区代码 → 中文名」表（含 250+ 国家 + 中国省级）。
  static Future<Map<String, String>> loadRegionNames() async {
    if (_regionNames != null) return _regionNames!;
    try {
      final raw =
          await rootBundle.loadString('assets/data/region_names_zh.json');
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _regionNames = m.map((k, v) => MapEntry(k, '$v'.trim()));
    } catch (_) {
      _regionNames = {};
    }
    return _regionNames!;
  }

  /// 按中文名 / 代码模糊搜索地区，返回 (代码, 中文名)，最多 12 条。
  static List<MapEntry<String, String>> searchRegions(
      String query, Map<String, String> names) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <MapEntry<String, String>>[];
    names.forEach((code, name) {
      if (name.toLowerCase().contains(q) || code.toLowerCase().contains(q)) {
        out.add(MapEntry(code, name));
      }
    });
    // 名字越短越靠前（更可能是精确匹配的省/国家），其次按名字排序。
    out.sort((a, b) {
      final byLen = a.value.length.compareTo(b.value.length);
      return byLen != 0 ? byLen : a.value.compareTo(b.value);
    });
    return out.take(12).toList();
  }

  /// 把输入解析成 eBird 地区代码：若整串等于某个中文地名则换成其代码，否则原样返回。
  static String resolveToRegionCode(String input, Map<String, String> names) {
    final t = input.trim();
    if (t.isEmpty) return t;
    for (final e in names.entries) {
      if (e.value == t) return e.key;
    }
    return t;
  }

  /// 代码 → 中文名（查不到返回原代码）。
  static String regionDisplayName(String code, Map<String, String> names) {
    return names[code.trim()] ?? code.trim();
  }

  static String normalizeLocationCode(String input) {
    final trimmed = input.trim();
    for (final item in presets) {
      if (item.label == trimmed ||
          item.note.toLowerCase() == trimmed.toLowerCase() ||
          item.code.toLowerCase() == trimmed.toLowerCase()) {
        return item.code;
      }
    }
    return trimmed.toUpperCase();
  }

  /// 用 eBird API 查地区代码的真实地名（如 NO-03 → "Oslo, Norway"）。
  /// 本地「代码→中文名」表只覆盖国家+中国省级，外国子地区查不到时用它兜底。失败返回 null。
  Future<String?> fetchRegionName(String code) async {
    final c = code.trim();
    if (c.isEmpty || c.contains(',')) return null; // 经纬度不查
    try {
      // 用 Uri.https 让 path 段自动百分号编码——别字符串插值进 Uri.parse，
      // code 里若有空格/#/? 等会破坏 URL、静默查不到。
      final uri = Uri.https('api.ebird.org', '/v2/ref/region/info/$c');
      final resp = await _client
          .get(uri, headers: {'X-eBirdApiToken': apiKey})
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final name = (data['result'] as String?)?.trim();
      return (name == null || name.isEmpty) ? null : name;
    } catch (_) {
      return null;
    }
  }

  Future<Set<String>> fetchSpeciesCodes(String locationCode) async {
    final matches = await fetchSpeciesMatches(locationCode);
    return matches
        .map((item) => item.code)
        .where((code) => code.isNotEmpty)
        .toSet();
  }

  Future<Set<EbirdSpeciesMatch>> fetchSpeciesMatches(
      String locationCode) async {
    final normalizedCode = normalizeLocationCode(locationCode);
    final uri = Uri.parse(
      'https://api.ebird.org/v2/product/spplist/$normalizedCode',
    );
    final response = await _client.get(
      uri,
      headers: {'X-eBirdApiToken': apiKey},
    );

    if (response.statusCode == 401) {
      throw Exception('eBird API key 无效或已失效');
    }
    if (response.statusCode != 200) {
      throw Exception('eBird 请求失败: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    final codes =
        data.map((item) => item.toString().trim().toLowerCase()).toSet();
    return _fetchTaxonomyMatches(codes);
  }

  Future<Set<EbirdSpeciesMatch>> fetchRecentSpeciesMatches(
    String locationCode, {
    int backDays = 30,
  }) async {
    final normalizedCode = normalizeLocationCode(locationCode);
    final uri = Uri.https(
      'api.ebird.org',
      '/v2/data/obs/$normalizedCode/recent',
      {
        'back': backDays.clamp(1, 30).toString(),
        'sppLocale': 'en',
      },
    );
    final response = await _client.get(
      uri,
      headers: {'X-eBirdApiToken': apiKey},
    );

    if (response.statusCode == 401) {
      throw Exception('eBird API key 无效或已失效');
    }
    if (response.statusCode != 200) {
      final detail = response.body.trim();
      throw Exception(
        'eBird 最近鸟种请求失败: ${response.statusCode}'
        '${detail.isEmpty ? '' : ' · $detail'}',
      );
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    final codes = data
        .whereType<Map<String, dynamic>>()
        .map((item) =>
            (item['speciesCode'] as String? ?? '').trim().toLowerCase())
        .where((code) => code.isNotEmpty)
        .toSet();
    return _fetchTaxonomyMatches(codes);
  }

  /// 「可能性」排序近似：近期(默认30天)被观测到的鸟种，按最近观测日期倒序返回学名(小写)。
  /// 越靠前 = 最近越常被记录 = 越可能现在遇到。注：eBird 公开 API 无真·出现频率，
  /// 这里用「最近观测」作近似。经纬度/无地区时不可用。
  Future<List<String>> fetchRecentObsBySci(
    String regionCode, {
    int backDays = 30,
  }) async {
    final normalizedCode = normalizeLocationCode(regionCode);
    final uri = Uri.https(
      'api.ebird.org',
      '/v2/data/obs/$normalizedCode/recent',
      {'back': backDays.clamp(1, 30).toString()},
    );
    final resp =
        await _client.get(uri, headers: {'X-eBirdApiToken': apiKey});
    if (resp.statusCode == 401) throw Exception('eBird API key 无效或已失效');
    if (resp.statusCode != 200) {
      throw Exception('eBird 近期观测请求失败: ${resp.statusCode}');
    }
    return _rankObsBySci(resp.body);
  }

  /// 「可能性」坐标版：某点(lat,lng,半径km)附近近期观测，按最近观测日期排名学名。
  /// 用 eBird geo 端点，弥补地区码筛选之外的经纬度筛选。
  Future<List<String>> fetchRecentObsByCoords(
    double lat,
    double lng, {
    int distanceKm = 25,
    int backDays = 30,
  }) async {
    final uri = Uri.https('api.ebird.org', '/v2/data/obs/geo/recent', {
      'lat': lat.toStringAsFixed(4),
      'lng': lng.toStringAsFixed(4),
      'dist': distanceKm.clamp(1, 50).toString(),
      'back': backDays.clamp(1, 30).toString(),
    });
    final resp = await _client.get(uri, headers: {'X-eBirdApiToken': apiKey});
    if (resp.statusCode == 401) throw Exception('eBird API key 无效或已失效');
    if (resp.statusCode != 200) {
      throw Exception('eBird 附近观测请求失败: ${resp.statusCode}');
    }
    return _rankObsBySci(resp.body);
  }

  /// 把 obs 响应解析成「按最近观测日期倒序、去重」的学名(小写)列表。
  List<String> _rankObsBySci(String body) {
    final data = jsonDecode(body) as List<dynamic>;
    final rows = data
        .whereType<Map<String, dynamic>>()
        .map((m) => (
              (m['sciName'] as String? ?? '').trim().toLowerCase(),
              (m['obsDt'] as String? ?? ''),
            ))
        .where((r) => r.$1.isNotEmpty)
        .toList();
    // 只按日期(前 10 位 yyyy-MM-dd)倒序：obsDt 混了「日期」与「日期+时间」两种格式，
    // 直接字符串比较会让同一天的「纯日期」与「带时间」次序错乱。时间精度对「可能性」无意义。
    String obsDate(String dt) => dt.length >= 10 ? dt.substring(0, 10) : dt;
    rows.sort((a, b) => obsDate(b.$2).compareTo(obsDate(a.$2)));
    final seen = <String>{};
    final ordered = <String>[];
    for (final r in rows) {
      if (seen.add(r.$1)) ordered.add(r.$1);
    }
    return ordered;
  }

  /// 指定历史某一天该地点记录到的鸟种（eBird historic 端点）。
  Future<Set<EbirdSpeciesMatch>> fetchHistoricSpeciesMatches(
    String locationCode, {
    required int year,
    required int month,
    required int day,
  }) async {
    final normalizedCode = normalizeLocationCode(locationCode);
    final uri = Uri.https(
      'api.ebird.org',
      '/v2/data/obs/$normalizedCode/historic/$year/$month/$day',
      {
        'sppLocale': 'en',
        'rank': 'mrec',
      },
    );
    final response = await _client.get(
      uri,
      headers: {'X-eBirdApiToken': apiKey},
    );

    if (response.statusCode == 401) {
      throw Exception('eBird API key 无效或已失效');
    }
    if (response.statusCode != 200) {
      final detail = response.body.trim();
      throw Exception(
        'eBird 历史鸟种请求失败: ${response.statusCode}'
        '${detail.isEmpty ? '' : ' · $detail'}',
      );
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    final codes = data
        .whereType<Map<String, dynamic>>()
        .map((item) =>
            (item['speciesCode'] as String? ?? '').trim().toLowerCase())
        .where((code) => code.isNotEmpty)
        .toSet();
    return _fetchTaxonomyMatches(codes);
  }

  Future<Set<String>> fetchNearbySpeciesCodes({
    required double latitude,
    required double longitude,
    int distanceKm = 25,
  }) async {
    final matches = await fetchNearbySpeciesMatches(
      latitude: latitude,
      longitude: longitude,
      distanceKm: distanceKm,
    );
    return matches
        .map((item) => item.code)
        .where((code) => code.isNotEmpty)
        .toSet();
  }

  Future<Set<EbirdSpeciesMatch>> fetchNearbySpeciesMatches({
    required double latitude,
    required double longitude,
    int distanceKm = 25,
    int backDays = 30,
  }) async {
    final uri = Uri.https('api.ebird.org', '/v2/data/obs/geo/recent', {
      'lat': latitude.toStringAsFixed(6),
      'lng': longitude.toStringAsFixed(6),
      'dist': distanceKm.clamp(1, 50).toString(),
      'back': backDays.clamp(1, 30).toString(),
      'sppLocale': 'en',
    });
    final response = await _client.get(
      uri,
      headers: {'X-eBirdApiToken': apiKey},
    );

    if (response.statusCode == 401) {
      throw Exception('eBird API key 无效或已失效');
    }
    if (response.statusCode != 200) {
      final detail = response.body.trim();
      throw Exception(
        'eBird 附近鸟种请求失败: ${response.statusCode}'
        '${detail.isEmpty ? '' : ' · $detail'}',
      );
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final code =
              (item['speciesCode'] as String? ?? '').trim().toLowerCase();
          return EbirdSpeciesMatch(
            code: code,
            scientificName: (item['sciName'] as String? ?? '').trim(),
            commonName: (item['comName'] as String? ?? '').trim(),
          );
        })
        .where((item) => item.code.isNotEmpty)
        .toSet();
  }

  Future<Set<EbirdSpeciesMatch>> _fetchTaxonomyMatches(
      Set<String> codes) async {
    if (codes.isEmpty) return {};
    final result = <EbirdSpeciesMatch>{};
    final list = codes.toList()..sort();
    const chunkSize = 80;
    for (var start = 0; start < list.length; start += chunkSize) {
      final chunk = list.skip(start).take(chunkSize).toList();
      final uri = Uri.https('api.ebird.org', '/v2/ref/taxonomy/ebird', {
        'species': chunk.join(','),
        'fmt': 'json',
        'locale': 'en',
      });
      final response = await _client.get(
        uri,
        headers: {'X-eBirdApiToken': apiKey},
      );
      if (response.statusCode != 200) {
        result.addAll(chunk.map((code) => EbirdSpeciesMatch(code: code)));
        continue;
      }
      final data = jsonDecode(response.body) as List<dynamic>;
      result.addAll(data.whereType<Map<String, dynamic>>().map((item) {
        return EbirdSpeciesMatch(
          code: (item['speciesCode'] as String? ?? '').trim().toLowerCase(),
          scientificName: (item['sciName'] as String? ?? '').trim(),
          commonName: (item['comName'] as String? ?? '').trim(),
        );
      }).where((item) => item.code.isNotEmpty));
    }
    return result;
  }
}
