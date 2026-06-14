import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/discover_service.dart';
import '../services/podcast_service.dart';

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

const _volunteers = <_VolunteerItem>[
  _VolunteerItem(
    title: '26南堡春迁滨海水鸟研究项目志愿者补招募',
    org: '南堡水鸟调查组',
    location: '河北曹妃甸南堡',
    date: '2026春迁',
    url: 'https://xhslink.com/o/AVPp9tsUw8V',
    note: '复制链接，在小红书中打开',
  ),
];

const _wechatGroupQrAsset = 'assets/brand/wechat_group_qr_20260614.jpg';

/// 入群二维码图片：有服务器 URL 用网络图（失败回退内置），否则内置。
Widget _qrImage(String networkUrl, {BoxFit fit = BoxFit.contain}) {
  if (networkUrl.isEmpty) {
    return Image.asset(_wechatGroupQrAsset, fit: fit);
  }
  return Image.network(
    networkUrl,
    fit: fit,
    errorBuilder: (_, __, ___) => Image.asset(_wechatGroupQrAsset, fit: fit),
  );
}

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  PodcastEpisode? _podcastEpisode;
  bool _podcastLoading = true;
  DiscoverContent? _discover;

  int _tab = 0;
  static const _tabs = ['播客栏目', '志愿招募', '观鸟资讯'];

  @override
  void initState() {
    super.initState();
    _loadPodcast();
    _loadDiscover();
  }

  Future<void> _loadPodcast() async {
    final ep = await PodcastService.fetchLatestEpisode();
    if (!mounted) return;
    setState(() {
      _podcastEpisode = ep;
      _podcastLoading = false;
    });
  }

  Future<void> _loadDiscover() async {
    final content = await DiscoverService.fetchDiscover();
    if (!mounted || content == null) return;
    setState(() => _discover = content);
  }

  /// 志愿招募项：服务器可达时用服务器内容（即便为空），不可达时回退内置。
  List<_VolunteerItem> get _volunteerItems {
    if (_discover == null) return _volunteers;
    return _discover!.volunteers
        .map((v) => _VolunteerItem(
              title: v.title,
              org: v.org,
              location: '',
              date: v.date,
              url: v.url,
            ))
        .toList();
  }

  String get _groupQrUrl => _discover?.groupQrUrl ?? '';

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法打开：$url')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        _tabBar(),
        const SizedBox(height: 4),
        Expanded(child: _tabContent(context)),
        _wechatBottomBar(context),
      ],
    );
  }

  Widget _tabBar() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final selected = i == _tab;
          return Center(
            child: ChoiceChip(
              label: Text(_tabs[i]),
              selected: selected,
              showCheckmark: false,
              labelStyle: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : Colors.grey[800],
              ),
              selectedColor: const Color(0xFF2d5016),
              backgroundColor: Colors.grey.withValues(alpha: 0.12),
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              onSelected: (_) => setState(() => _tab = i),
            ),
          );
        },
      ),
    );
  }

  Widget _tabContent(BuildContext context) {
    switch (_tab) {
      case 0: // 播客
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _podcastCard(context),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => _open(context, PodcastService.podcastWebUrl),
              icon: const Icon(Icons.podcasts_outlined, size: 18),
              label: const Text('在小宇宙收听全部往期'),
            ),
          ],
        );
      case 1: // 志愿招募
        final items = _volunteerItems;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (items.isEmpty)
              _buildComingSoonCard('暂无招募信息，欢迎联系补充')
            else
              ...items.map((item) => _buildVolunteerCard(context, item)),
            const SizedBox(height: 4),
            _contactCard(context, '如有需要发布研究招募信息，请联系 birderrrr@gmail.com'),
          ],
        );
      default: // 观鸟资讯
        final news = _discover?.news ?? const <DiscoverNews>[];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (news.isEmpty)
              _discoverPlaceholder(context)
            else ...[
              ...news.map((n) => _buildNewsCard(context, n)),
              const SizedBox(height: 4),
              _contactCard(context, '想分享鸟导 / 鸟团 / 出行 / 鸟种攻略？联系 birderrrr@gmail.com'),
            ],
          ],
        );
    }
  }

  Widget _contactCard(BuildContext context, String text) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context, 'mailto:birderrrr@gmail.com'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.campaign_outlined, color: Colors.green[700]),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 13, height: 1.45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _discoverPlaceholder(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.construction_outlined, color: Colors.grey[400]),
                const SizedBox(width: 12),
                const Text(
                  '观鸟资讯 · 开发中',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '计划收录：鸟讯、观鸟向导 / 带队老师、观鸟团、热门观鸟地与出行线路、鸟种攻略。',
              style: TextStyle(
                  fontSize: 13, height: 1.5, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _open(context, 'mailto:birderrrr@gmail.com'),
              icon: const Icon(Icons.mail_outline, size: 18),
              label: const Text('欢迎联系补充'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewsCard(BuildContext context, DiscoverNews n) {
    final hasUrl = n.url.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: hasUrl ? () => _open(context, n.url) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (n.category.isNotEmpty) ...[
                _InfoPill(n.category),
                const SizedBox(height: 8),
              ],
              Text(
                n.title,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              if (n.summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  n.summary,
                  style: TextStyle(
                      fontSize: 13, height: 1.45, color: Colors.grey[700]),
                ),
              ],
              if (n.date.isNotEmpty || hasUrl) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (n.date.isNotEmpty) ...[
                      Icon(Icons.calendar_today_outlined,
                          size: 13, color: Colors.grey[500]),
                      const SizedBox(width: 3),
                      Text(n.date,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                    const Spacer(),
                    if (hasUrl)
                      Icon(Icons.chevron_right,
                          size: 18, color: Colors.grey[400]),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _wechatBottomBar(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
        child: Center(
          child: TextButton.icon(
            onPressed: () => _showWechatSheet(context),
            icon: const Icon(Icons.groups_outlined, size: 18),
            label: const Text('入群交流'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF2d5016),
            ),
          ),
        ),
      ),
    );
  }

  /// 点入群直接弹出微信群二维码截图，无多余文字/按钮。
  void _showWechatSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final maxH = MediaQuery.of(ctx).size.height * 0.7;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _qrImage(_groupQrUrl, fit: BoxFit.contain),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _podcastCard(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context, PodcastService.podcastWebUrl),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: _podcastLoading
              ? Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              height: 14,
                              width: double.infinity,
                              color: Colors.grey[200]),
                          const SizedBox(height: 8),
                          Container(
                              height: 12, width: 80, color: Colors.grey[200]),
                        ],
                      ),
                    ),
                  ],
                )
              : _podcastEpisode == null
                  ? Row(
                      children: [
                        const Icon(Icons.podcasts_outlined,
                            color: Color(0xFF2d5016)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '暂时无法加载最新一期，点击前往小宇宙',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[600]),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_podcastEpisode!.imageUrl.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              _podcastEpisode!.imageUrl,
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 60,
                                height: 60,
                                color: Colors.grey[200],
                                child: const Icon(Icons.podcasts,
                                    color: Colors.grey),
                              ),
                            ),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '鸟瘾综合征 · 最新一期',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF2d5016),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _podcastEpisode!.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _podcastEpisode!.pubDate,
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.grey),
                      ],
                    ),
        ),
      ),
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

  Widget _buildVolunteerCard(BuildContext context, _VolunteerItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context, item.url),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [_InfoPill('招募中')],
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              if (item.location.isNotEmpty || item.date.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (item.location.isNotEmpty) ...[
                      Icon(Icons.place_outlined,
                          size: 13, color: Colors.grey[500]),
                      const SizedBox(width: 3),
                      Text(item.location,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                      const SizedBox(width: 12),
                    ],
                    if (item.date.isNotEmpty) ...[
                      Icon(Icons.calendar_today_outlined,
                          size: 13, color: Colors.grey[500]),
                      const SizedBox(width: 3),
                      Text(item.date,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ],
                ),
              ],
              if (item.org.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text('发起：${item.org}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
              if (item.note != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    item.note!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  const _InfoPill(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF2d5016).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF2d5016),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
