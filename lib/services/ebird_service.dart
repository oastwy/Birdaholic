import 'dart:convert';

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
  }) async {
    final uri = Uri.https('api.ebird.org', '/v2/data/obs/geo/recent', {
      'lat': latitude.toStringAsFixed(6),
      'lng': longitude.toStringAsFixed(6),
      'dist': distanceKm.clamp(1, 50).toString(),
      'back': '30',
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
