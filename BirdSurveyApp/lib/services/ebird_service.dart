import 'dart:convert';
import 'package:http/http.dart' as http;

class EbirdObservation {
  final String speciesCode;
  final String comName;
  final String sciName;
  final int howMany;

  EbirdObservation({
    required this.speciesCode,
    required this.comName,
    required this.sciName,
    required this.howMany,
  });

  factory EbirdObservation.fromJson(Map<String, dynamic> json) {
    return EbirdObservation(
      speciesCode: json['speciesCode'] as String? ?? '',
      comName: json['comName'] as String? ?? '',
      sciName: json['sciName'] as String? ?? '',
      howMany: (json['howMany'] as num?)?.toInt() ?? 1,
    );
  }
}

class EbirdService {
  final String apiKey;
  static const _base = 'https://api.ebird.org/v2';

  EbirdService(this.apiKey);

  // Returns species code -> total count (aggregated over back days)
  Future<Map<String, int>> getNearbySpeciesFrequency({
    required double lat,
    required double lng,
    int distKm = 30,
    int back = 30,
    int maxResults = 1000,
  }) async {
    if (apiKey.isEmpty) return {};
    final uri = Uri.parse(
      '$_base/data/obs/geo/recent'
      '?lat=$lat&lng=$lng&dist=$distKm&back=$back&maxResults=$maxResults',
    );
    final resp = await http
        .get(uri, headers: {'X-eBirdApiToken': apiKey})
        .timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) return {};

    final List<dynamic> data = json.decode(resp.body) as List<dynamic>;
    final freq = <String, int>{};
    for (final item in data) {
      final obs = EbirdObservation.fromJson(item as Map<String, dynamic>);
      if (obs.speciesCode.isNotEmpty) {
        freq[obs.speciesCode] = (freq[obs.speciesCode] ?? 0) + obs.howMany;
      }
    }
    return freq;
  }

  Future<Map<String, int>> getRegionSpeciesFrequency({
    required String regionCode,
    int back = 30,
    int maxResults = 2000,
  }) async {
    if (apiKey.isEmpty) return {};
    final uri = Uri.parse(
      '$_base/data/obs/$regionCode/recent'
      '?back=$back&maxResults=$maxResults',
    );
    final resp = await http
        .get(uri, headers: {'X-eBirdApiToken': apiKey})
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) return {};
    final List<dynamic> data = json.decode(resp.body) as List<dynamic>;
    final freq = <String, int>{};
    for (final item in data) {
      final obs = EbirdObservation.fromJson(item as Map<String, dynamic>);
      if (obs.speciesCode.isNotEmpty) {
        freq[obs.speciesCode] = (freq[obs.speciesCode] ?? 0) + obs.howMany;
      }
    }
    return freq;
  }

  static String getRegionCode(double lat, double lon) {
    if (lat >= 30.7 && lat <= 31.9 && lon >= 120.9 && lon <= 122.2) return 'CN-31';
    if (lat >= 39.4 && lat <= 41.1 && lon >= 115.7 && lon <= 117.5) return 'CN-11';
    if (lat >= 38.6 && lat <= 40.3 && lon >= 116.7 && lon <= 118.0) return 'CN-12';
    if (lat >= 18.1 && lat <= 20.2 && lon >= 108.4 && lon <= 111.1) return 'CN-46';
    if (lat >= 35.2 && lat <= 39.4 && lon >= 104.3 && lon <= 107.7) return 'CN-64';
    if (lat >= 38.7 && lat <= 43.5 && lon >= 118.8 && lon <= 125.8) return 'CN-21';
    if (lat >= 41.0 && lat <= 46.3 && lon >= 121.7 && lon <= 131.3) return 'CN-22';
    if (lat >= 43.4 && lat <= 53.6 && lon >= 121.2 && lon <= 135.1) return 'CN-23';
    if (lat >= 30.8 && lat <= 35.1 && lon >= 116.4 && lon <= 121.9) return 'CN-32';
    if (lat >= 27.1 && lat <= 31.2 && lon >= 118.0 && lon <= 122.9) return 'CN-33';
    if (lat >= 29.4 && lat <= 34.6 && lon >= 114.9 && lon <= 119.6) return 'CN-34';
    if (lat >= 23.5 && lat <= 28.3 && lon >= 115.8 && lon <= 120.8) return 'CN-35';
    if (lat >= 24.5 && lat <= 30.1 && lon >= 113.6 && lon <= 118.5) return 'CN-36';
    if (lat >= 34.4 && lat <= 38.4 && lon >= 114.8 && lon <= 122.7) return 'CN-37';
    if (lat >= 31.4 && lat <= 36.4 && lon >= 110.4 && lon <= 116.7) return 'CN-41';
    if (lat >= 29.0 && lat <= 33.3 && lon >= 108.4 && lon <= 116.1) return 'CN-42';
    if (lat >= 24.6 && lat <= 30.1 && lon >= 108.8 && lon <= 114.3) return 'CN-43';
    if (lat >= 20.2 && lat <= 25.5 && lon >= 109.7 && lon <= 117.3) return 'CN-44';
    if (lat >= 20.5 && lat <= 26.4 && lon >= 104.5 && lon <= 112.1) return 'CN-45';
    if (lat >= 28.2 && lat <= 32.2 && lon >= 105.3 && lon <= 110.2) return 'CN-50';
    if (lat >= 26.0 && lat <= 34.3 && lon >= 97.4 && lon <= 108.6) return 'CN-51';
    if (lat >= 24.6 && lat <= 29.2 && lon >= 103.6 && lon <= 109.5) return 'CN-52';
    if (lat >= 21.1 && lat <= 29.2 && lon >= 97.5 && lon <= 106.2) return 'CN-53';
    if (lat >= 26.8 && lat <= 36.5 && lon >= 78.4 && lon <= 99.1) return 'CN-54';
    if (lat >= 31.7 && lat <= 39.6 && lon >= 105.5 && lon <= 111.2) return 'CN-61';
    if (lat >= 32.6 && lat <= 42.8 && lon >= 92.3 && lon <= 108.7) return 'CN-62';
    if (lat >= 31.6 && lat <= 39.2 && lon >= 89.4 && lon <= 103.1) return 'CN-63';
    if (lat >= 34.2 && lat <= 49.2 && lon >= 73.4 && lon <= 96.4) return 'CN-65';
    if (lat >= 36.0 && lat <= 42.6 && lon >= 113.5 && lon <= 119.8) return 'CN-13';
    if (lat >= 34.6 && lat <= 40.7 && lon >= 110.2 && lon <= 114.6) return 'CN-14';
    if (lat >= 37.4 && lat <= 53.3 && lon >= 97.2 && lon <= 126.1) return 'CN-15';
    return 'CN';
  }

  static const regionNames = <String, String>{
    'CN-11': '北京', 'CN-12': '天津', 'CN-13': '河北', 'CN-14': '山西',
    'CN-15': '内蒙古', 'CN-21': '辽宁', 'CN-22': '吉林', 'CN-23': '黑龙江',
    'CN-31': '上海', 'CN-32': '江苏', 'CN-33': '浙江', 'CN-34': '安徽',
    'CN-35': '福建', 'CN-36': '江西', 'CN-37': '山东', 'CN-41': '河南',
    'CN-42': '湖北', 'CN-43': '湖南', 'CN-44': '广东', 'CN-45': '广西',
    'CN-46': '海南', 'CN-50': '重庆', 'CN-51': '四川', 'CN-52': '贵州',
    'CN-53': '云南', 'CN-54': '西藏', 'CN-61': '陕西', 'CN-62': '甘肃',
    'CN-63': '青海', 'CN-64': '宁夏', 'CN-65': '新疆', 'CN': '全国',
  };
}
