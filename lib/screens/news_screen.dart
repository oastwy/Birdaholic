import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class _EBirdNewsItem {
  final String title;
  final String url;
  final String date;
  final String summary;
  const _EBirdNewsItem(
      {required this.title,
      required this.url,
      required this.date,
      required this.summary});
}

class _VolunteerItem {
  final String title;
  final String org;
  final String location;
  final String date;
  final String url;
  final String? note;
  const _VolunteerItem({
    required this.title,
    required this.org,
    required this.location,
    required this.date,
    required this.url,
    this.note,
  });
}

// ─── Hardcoded volunteer data (manually maintained) ───────────────────────────

const _volunteers = <_VolunteerItem>[
  _VolunteerItem(
    title: '26南堡春迁滨海水鸟研究项目志愿者补招募',
    org: '南堡水鸟调查组',
    location: '河北曹妃甸南堡',
    date: '2026春迁',
    url: 'http://xhslink.com/o/AVPp9tsUw8V',
    note: '复制链接，在小红书中打开',
  ),
];

// ─── Screen ───────────────────────────────────────────────────────────────────

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  List<_EBirdNewsItem>? _ebirdNews;
  bool _ebirdLoading = true;
  String? _ebirdError;

  @override
  void initState() {
    super.initState();
    _fetchEBirdNews();
  }

  Future<void> _fetchEBirdNews() async {
    try {
      // Fetch eBird news page and parse JSON-LD or articles
      final response = await http
          .get(Uri.parse('https://ebird.org/news'),
              headers: {'User-Agent': 'BirdaholicApp/1.0'})
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final items = _parseEBirdNews(response.body);
      if (mounted) {
        setState(() {
          _ebirdNews = items;
          _ebirdLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _ebirdError = '$e';
          _ebirdLoading = false;
        });
      }
    }
  }

  List<_EBirdNewsItem> _parseEBirdNews(String html) {
    final items = <_EBirdNewsItem>[];
    // Parse article links from eBird news page
    final articleRe = RegExp(
      r'<article[^>]*>.*?<a[^>]+href="(/news/[^"]+)"[^>]*>.*?<h[23][^>]*>(.*?)</h[23]>.*?(?:<time[^>]*>(.*?)</time>)?.*?(?:<p[^>]*>(.*?)</p>)?.*?</article>',
      dotAll: true,
    );
    for (final m in articleRe.allMatches(html)) {
      final path = m.group(1) ?? '';
      final title = _stripTags(m.group(2) ?? '').trim();
      final date = _stripTags(m.group(3) ?? '').trim();
      final summary = _stripTags(m.group(4) ?? '').trim();
      if (title.isNotEmpty) {
        items.add(_EBirdNewsItem(
          title: title,
          url: 'https://ebird.org$path',
          date: date,
          summary: summary,
        ));
      }
    }
    // Fallback: try simpler link+heading pattern
    if (items.isEmpty) {
      final re2 = RegExp(
        r'href="(https://ebird\.org/news/[^"]+)"[^>]*>\s*<[^>]+>\s*([^<]{10,})',
        dotAll: true,
      );
      for (final m in re2.allMatches(html).take(8)) {
        final url = m.group(1) ?? '';
        final title = m.group(2)?.trim() ?? '';
        if (title.isNotEmpty) {
          items.add(_EBirdNewsItem(title: title, url: url, date: '', summary: ''));
        }
      }
    }
    return items.take(8).toList();
  }

  String _stripTags(String html) =>
      html.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法打开：$url')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionHeader('🌍 eBird 新闻', onRefresh: () {
          setState(() {
            _ebirdLoading = true;
            _ebirdError = null;
            _ebirdNews = null;
          });
          _fetchEBirdNews();
        }),
        const SizedBox(height: 8),
        _buildEBirdSection(),
        const SizedBox(height: 20),
        _sectionHeader('📰 鸟讯'),
        const SizedBox(height: 8),
        _buildComingSoonCard('鸟讯功能开发中'),
        const SizedBox(height: 20),
        _sectionHeader('🙋 志愿者招募'),
        const SizedBox(height: 8),
        ..._volunteers.map(_buildVolunteerCard),
      ],
    );
  }

  Widget _sectionHeader(String title, {VoidCallback? onRefresh}) {
    return Row(
      children: [
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const Spacer(),
        if (onRefresh != null)
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: onRefresh,
            tooltip: '刷新',
          ),
      ],
    );
  }

  Widget _buildEBirdSection() {
    if (_ebirdLoading) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator()));
    }
    if (_ebirdError != null || _ebirdNews == null || _ebirdNews!.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.wifi_off_outlined, color: Colors.grey[400], size: 32),
              const SizedBox(height: 8),
              Text(
                _ebirdNews != null && _ebirdNews!.isEmpty
                    ? '暂无新闻'
                    : '加载失败，请检查网络',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _open('https://ebird.org/news'),
                child: const Text('在浏览器中打开 eBird News'),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: _ebirdNews!
          .map((item) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _open(item.url),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                        if (item.date.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(item.date,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[500])),
                        ],
                        if (item.summary.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(item.summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[700])),
                        ],
                      ],
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildComingSoonCard(String text) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Row(
          children: [
            Icon(Icons.construction_outlined, color: Colors.grey[400]),
            const SizedBox(width: 12),
            Text(text, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _buildVolunteerCard(_VolunteerItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(item.url),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.place_outlined, size: 13, color: Colors.grey[500]),
                  const SizedBox(width: 3),
                  Text(item.location,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(width: 12),
                  Icon(Icons.calendar_today_outlined,
                      size: 13, color: Colors.grey[500]),
                  const SizedBox(width: 3),
                  Text(item.date,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
              const SizedBox(height: 4),
              Text('发起：${item.org}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              if (item.note != null) ...[
                const SizedBox(height: 4),
                Text(item.note!,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange[700],
                        fontStyle: FontStyle.italic)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
