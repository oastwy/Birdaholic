import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService {
  final String apiKey;

  WeatherService(this.apiKey);

  /// Returns a human-readable weather string, e.g. "晴 25℃ 东南风3级 湿度68%"
  /// Returns null if key is empty or request fails.
  Future<String?> getCurrentWeather(double lat, double lon) async {
    if (apiKey.isEmpty) return null;
    final uri = Uri.parse(
      'https://devapi.qweather.com/v7/weather/now'
      '?location=${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)}'
      '&key=$apiKey',
    );
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body) as Map<String, dynamic>;
      if (data['code'] != '200') return null;
      final now = data['now'] as Map<String, dynamic>?;
      if (now == null) return null;
      final text = now['text'] as String? ?? '';
      final temp = now['temp'] as String? ?? '';
      final windDir = now['windDir'] as String? ?? '';
      final windScale = now['windScale'] as String? ?? '';
      final humidity = now['humidity'] as String? ?? '';
      final parts = <String>[
        if (text.isNotEmpty) text,
        if (temp.isNotEmpty) '$temp℃',
        if (windDir.isNotEmpty && windScale.isNotEmpty) '$windDir${windScale}级',
        if (humidity.isNotEmpty) '湿度$humidity%',
      ];
      return parts.join(' ');
    } catch (_) {
      return null;
    }
  }
}
