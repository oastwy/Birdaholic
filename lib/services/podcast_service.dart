import 'dart:convert';

import 'package:http/http.dart' as http;

class PodcastEpisode {
  final String title;
  final String pubDate;
  final String episodeUrl;
  final String imageUrl;

  const PodcastEpisode({
    required this.title,
    required this.pubDate,
    required this.episodeUrl,
    required this.imageUrl,
  });
}

/// 小宇宙不公开 RSS，所以抓 podcast 主页 HTML，从内嵌的
/// JSON-LD schema (`schema:podcast-show`) 和 `<meta og:image>` 取数据。
class PodcastService {
  static const _podcastWebUrl =
      'https://www.xiaoyuzhoufm.com/podcast/6688a873ae8e21859ade308b';

  static String get podcastWebUrl => _podcastWebUrl;

  // Cache: 1 hour TTL (avoid re-fetch every time user returns to home tab)
  static PodcastEpisode? _cached;
  static DateTime? _cachedAt;
  static const _cacheTtl = Duration(hours: 1);

  static Future<PodcastEpisode?> fetchLatestEpisode() async {
    if (_cached != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheTtl) {
      return _cached;
    }

    try {
      final response = await http
          .get(Uri.parse(_podcastWebUrl), headers: {
            'User-Agent':
                'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) '
                    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 '
                    'Mobile/15E148 Safari/604.1',
          })
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final episode = _parseFromHtml(utf8.decode(response.bodyBytes));
      if (episode != null) {
        _cached = episode;
        _cachedAt = DateTime.now();
      }
      return episode;
    } catch (_) {
      return null;
    }
  }

  static PodcastEpisode? _parseFromHtml(String html) {
    // JSON-LD: <script ... name="schema:podcast-show" type="application/ld+json">{...}</script>
    final ldMatch = _jsonLdRe.firstMatch(html);
    if (ldMatch == null) return null;

    Map<String, dynamic> ld;
    try {
      ld = jsonDecode(ldMatch.group(1)!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final works = ld['workExample'] as List<dynamic>?;
    if (works == null || works.isEmpty) return null;
    final ep = works.first as Map<String, dynamic>;

    final title = (ep['name'] as String? ?? '').trim();
    if (title.isEmpty) return null;

    final pubDateRaw = (ep['datePublished'] as String? ?? '').trim();
    final pubDate = _formatIsoDate(pubDateRaw);

    // og:image is the podcast cover (episode-level image not in JSON-LD)
    final ogImgMatch = _ogImageRe.firstMatch(html);
    final imageUrl = ogImgMatch?.group(1)?.trim() ?? '';

    return PodcastEpisode(
      title: title,
      pubDate: pubDate,
      episodeUrl: _podcastWebUrl, // single-episode URL is unavailable
      imageUrl: imageUrl,
    );
  }

  static final _jsonLdRe = RegExp(
    r'<script[^>]+schema:podcast-show[^>]+>([\s\S]*?)</script>',
  );
  static final _ogImageRe = RegExp(
    r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"',
  );

  static String _formatIsoDate(String iso) {
    // "2026-05-15T12:30:00.000Z" → "2026-05-15"
    try {
      final dt = DateTime.parse(iso).toLocal();
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    } catch (_) {
      return iso;
    }
  }
}
