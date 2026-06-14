import 'dart:convert';

import 'package:http/http.dart' as http;

import 'server_media_service.dart';

/// 发现页运营内容（来自服务器 /api/discover），含入群二维码、志愿招募、观鸟资讯。
/// 失败时调用方回退到内置默认值。

class DiscoverVolunteer {
  final String id;
  final String title;
  final String org;
  final String date;
  final String url;

  const DiscoverVolunteer({
    required this.title,
    this.id = '',
    this.org = '',
    this.date = '',
    this.url = '',
  });

  static DiscoverVolunteer? fromJson(Map<String, dynamic> j) {
    final title = (j['title'] as String? ?? '').trim();
    if (title.isEmpty) return null;
    return DiscoverVolunteer(
      id: (j['id'] as String? ?? '').trim(),
      title: title,
      org: (j['org'] as String? ?? '').trim(),
      date: (j['date'] as String? ?? '').trim(),
      url: (j['url'] as String? ?? '').trim(),
    );
  }
}

class DiscoverNews {
  final String id;
  final String title;
  final String summary;
  final String url;
  final String category;
  final String date;

  const DiscoverNews({
    required this.title,
    this.id = '',
    this.summary = '',
    this.url = '',
    this.category = '',
    this.date = '',
  });

  static DiscoverNews? fromJson(Map<String, dynamic> j) {
    final title = (j['title'] as String? ?? '').trim();
    if (title.isEmpty) return null;
    return DiscoverNews(
      id: (j['id'] as String? ?? '').trim(),
      title: title,
      summary: (j['summary'] as String? ?? '').trim(),
      url: (j['url'] as String? ?? '').trim(),
      category: (j['category'] as String? ?? '').trim(),
      date: (j['date'] as String? ?? '').trim(),
    );
  }
}

class DiscoverContent {
  final String groupQrUrl;
  final List<DiscoverVolunteer> volunteers;
  final List<DiscoverNews> news;

  const DiscoverContent({
    this.groupQrUrl = '',
    this.volunteers = const [],
    this.news = const [],
  });
}

class DiscoverService {
  static const _baseUrl = ServerMediaService.defaultBaseUrl;

  static DiscoverContent? _cached;
  static DateTime? _cachedAt;
  static const _cacheTtl = Duration(hours: 1);

  /// 拉取运营内容（已过滤 status==active）。失败/无内容返回 null，调用方用内置兜底。
  static Future<DiscoverContent?> fetchDiscover({bool force = false}) async {
    if (!force &&
        _cached != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheTtl) {
      return _cached;
    }
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/discover'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) return null;

      final qr = data['groupQr'];
      final groupQrUrl = (qr is Map && qr['imageUrl'] is String)
          ? (qr['imageUrl'] as String).trim()
          : '';

      final volunteers = <DiscoverVolunteer>[];
      for (final v in (data['volunteers'] as List? ?? const [])) {
        if (v is! Map<String, dynamic>) continue;
        if ((v['status'] as String? ?? 'active') == 'expired') continue;
        final item = DiscoverVolunteer.fromJson(v);
        if (item != null) volunteers.add(item);
      }

      final news = <DiscoverNews>[];
      for (final n in (data['news'] as List? ?? const [])) {
        if (n is! Map<String, dynamic>) continue;
        if ((n['status'] as String? ?? 'active') == 'expired') continue;
        final item = DiscoverNews.fromJson(n);
        if (item != null) news.add(item);
      }

      final content = DiscoverContent(
        groupQrUrl: groupQrUrl,
        volunteers: volunteers,
        news: news,
      );
      _cached = content;
      _cachedAt = DateTime.now();
      return content;
    } catch (_) {
      return null;
    }
  }
}
