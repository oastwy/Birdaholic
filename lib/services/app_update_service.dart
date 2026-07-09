import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_version.dart';

class AppUpdateInfo {
  final String version;
  final String releaseDate;
  final String downloadUrl;
  final String title;

  /// GitHub Release 里那个 .apk 附件的直链；能一键下载安装用这个。
  /// 拿不到（GitHub API 没走通、退化成抓 download.html）时为 null，
  /// 只能退回打开下载页让用户自己点。
  final String? apkAssetUrl;

  const AppUpdateInfo({
    required this.version,
    required this.releaseDate,
    required this.downloadUrl,
    required this.title,
    this.apkAssetUrl,
  });
}

class AppUpdateService {
  static const downloadUrl = 'https://birding.today/download.html';
  static const _githubLatestUrl =
      'https://api.github.com/repos/oastwy/Birdaholic/releases/latest';
  // 国内自托管版本源：GitHub 在国内又慢又常被拦，且一键装需要国内可达的 apk 直链。
  // 优先查这个；拿到有效响应就以它为准（不再打 GitHub），拿不到才退回 GitHub / download.html。
  static const _domesticVersionUrl =
      'https://birding.today/birdaholic/version.json';

  static AppUpdateInfo? _cached;
  static DateTime? _cachedAt;
  static const _cacheTtl = Duration(hours: 1);

  static Future<AppUpdateInfo> fetchLatest({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cached != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheTtl) {
      return _cached!;
    }

    // 1) 国内源优先。version.json = {versionCode,versionName,url,notes,date}。
    //    按 versionCode 与本机 appBuildNumber 比较（比版本名字符串更可靠）。
    try {
      final response = await http.get(Uri.parse(_domesticVersionUrl), headers: {
        'User-Agent': 'Birdaholic/$appVersionName',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final vCode = (data['versionCode'] as num?)?.toInt() ?? 0;
        final vName = (data['versionName'] ?? '').toString().trim();
        final url = (data['url'] ?? '').toString().trim();
        final newer = vCode > appBuildNumber && vName.isNotEmpty && url.isNotEmpty;
        final info = AppUpdateInfo(
          version: newer ? vName : appVersionName,
          releaseDate: _formatIsoDate((data['date'] ?? '').toString().trim()),
          downloadUrl: downloadUrl,
          title: 'Birdaholic v${newer ? vName : appVersionName}',
          apkAssetUrl: newer ? url : null,
        );
        _cached = info;
        _cachedAt = DateTime.now();
        return info;
      }
    } catch (_) {}

    var version = appVersionName;
    var date = '';
    var title = 'Birdaholic v$appVersionName';
    String? apkAssetUrl;

    try {
      final response = await http.get(Uri.parse(_githubLatestUrl), headers: {
        'User-Agent': 'Birdaholic/$appVersionName',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final tag = (data['tag_name'] as String? ?? '').trim();
        if (tag.isNotEmpty) {
          final parsedVersion = tag.replaceFirst(RegExp(r'^[vV]'), '');
          if (_compareVersions(parsedVersion, appVersionName) >= 0) {
            version = parsedVersion;
            title = 'Birdaholic v$version';
            date =
                _formatIsoDate((data['published_at'] as String? ?? '').trim());
            final assets = data['assets'] as List<dynamic>? ?? [];
            for (final a in assets) {
              final name = (a['name'] as String? ?? '').toLowerCase();
              final url = (a['browser_download_url'] as String? ?? '');
              if (name.endsWith('.apk') && url.isNotEmpty) {
                apkAssetUrl = url;
                break;
              }
            }
          }
        }
      }
    } catch (_) {}

    if (date.isEmpty) {
      try {
        final response = await http.get(Uri.parse(downloadUrl), headers: {
          'User-Agent': 'Birdaholic/$appVersionName',
        }).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final html = utf8.decode(response.bodyBytes);
          final parsedVersion = _parseVersion(html);
          if (parsedVersion != null &&
              _compareVersions(parsedVersion, version) >= 0) {
            version = parsedVersion;
            date = _parseDate(html) ?? date;
            title = 'Birdaholic v$version';
          } else if (parsedVersion == null) {
            date = _parseDate(html) ?? date;
            title = 'Birdaholic v$version';
          }
        }
      } catch (_) {}
    }

    final info = AppUpdateInfo(
      version: version,
      releaseDate: date,
      downloadUrl: downloadUrl,
      title: title,
      apkAssetUrl: apkAssetUrl,
    );
    _cached = info;
    _cachedAt = DateTime.now();
    return info;
  }

  static bool isNewerThanCurrent(String version) {
    return _compareVersions(version, appVersionName) > 0;
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

  static int _compareVersions(String a, String b) {
    final left = a.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    final right = b.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final lv = i < left.length ? left[i] : 0;
      final rv = i < right.length ? right[i] : 0;
      if (lv != rv) return lv.compareTo(rv);
    }
    return 0;
  }
}
