import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_version.dart';

class AppUpdateInfo {
  final String version;
  final String releaseDate;
  final String downloadUrl;
  final String title;

  const AppUpdateInfo({
    required this.version,
    required this.releaseDate,
    required this.downloadUrl,
    required this.title,
  });
}

class AppUpdateService {
  static const downloadUrl = 'https://birding.today/download.html';
  static const _githubLatestUrl =
      'https://api.github.com/repos/oastwy/Birdaholic/releases/latest';

  static AppUpdateInfo? _cached;
  static DateTime? _cachedAt;
  static const _cacheTtl = Duration(hours: 1);

  static Future<AppUpdateInfo> fetchLatest() async {
    if (_cached != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheTtl) {
      return _cached!;
    }

    var version = appVersionName;
    var date = '';
    var title = 'Birdaholic v$appVersionName';

    try {
      final response = await http.get(Uri.parse(_githubLatestUrl), headers: {
        'User-Agent': 'Birdaholic/$appVersionName',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final tag = (data['tag_name'] as String? ?? '').trim();
        if (tag.isNotEmpty) {
          version = tag.replaceFirst(RegExp(r'^[vV]'), '');
          title = 'Birdaholic v$version';
        }
        date = _formatIsoDate((data['published_at'] as String? ?? '').trim());
      }
    } catch (_) {}

    if (date.isEmpty) {
      try {
        final response = await http.get(Uri.parse(downloadUrl), headers: {
          'User-Agent': 'Birdaholic/$appVersionName',
        }).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final html = utf8.decode(response.bodyBytes);
          version = _parseVersion(html) ?? version;
          date = _parseDate(html) ?? date;
          title = 'Birdaholic v$version';
        }
      } catch (_) {}
    }

    final info = AppUpdateInfo(
      version: version,
      releaseDate: date,
      downloadUrl: downloadUrl,
      title: title,
    );
    _cached = info;
    _cachedAt = DateTime.now();
    return info;
  }

  static String? _parseVersion(String html) {
    final patterns = [
      RegExp(r'当前版本\s*[vV]?([0-9]+(?:\.[0-9]+){1,3})'),
      RegExp(r'最新版本\s*[vV]?([0-9]+(?:\.[0-9]+){1,3})'),
      RegExp(r'[vV]([0-9]+(?:\.[0-9]+){1,3})'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) return match.group(1);
    }
    return null;
  }

  static String? _parseDate(String html) {
    final patterns = [
      RegExp(r'(?:发布日期|发布时间|更新日期)\s*[:：]?\s*([0-9]{4}-[0-9]{1,2}-[0-9]{1,2})'),
      RegExp(r'<time[^>]+datetime="([^"]+)"'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      final value = match?.group(1);
      if (value == null || value.isEmpty) continue;
      return _formatIsoDate(value);
    }
    return null;
  }

  static String _formatIsoDate(String value) {
    if (value.isEmpty) return '';
    try {
      final dt = DateTime.parse(value).toLocal();
      return '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return value;
    }
  }
}
