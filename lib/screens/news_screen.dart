import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_version.dart';
import '../services/app_update_service.dart';
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

Future<void> _saveWechatQrToDevice(BuildContext context) async {
  try {
    final path = await _writeWechatQrAsset();
    if (!context.mounted) return;
    final fileName = path.split(Platform.pathSeparator).last;
    final inDownloads = path.contains('${Platform.pathSeparator}Download'
        '${Platform.pathSeparator}');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          inDownloads ? '已保存到下载目录：$fileName' : '已保存二维码：$path',
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('保存失败：$e')),
    );
  }
}

Future<String> _writeWechatQrAsset() async {
  final data = await rootBundle.load(_wechatGroupQrAsset);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  const fileName = 'Birdaholic_wechat_group_qr_20260614.jpg';
  final dirs = <Directory>[];

  if (Platform.isAndroid) {
    final downloads = Directory('/storage/emulated/0/Download');
    if (await downloads.exists()) {
      dirs.add(downloads);
    }
  }
  dirs.add(await getApplicationDocumentsDirectory());

  Object? lastError;
  for (final dir in dirs) {
    try {
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      lastError = e;
    }
  }
  throw Exception(lastError ?? '无法写入图片');
}

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  PodcastEpisode? _podcastEpisode;
  AppUpdateInfo? _updateInfo;
  bool _podcastLoading = true;
  bool _updateLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPodcast();
    _loadUpdateInfo();
  }

  Future<void> _loadPodcast() async {
    final ep = await PodcastService.fetchLatestEpisode();
    if (!mounted) return;
    setState(() {
      _podcastEpisode = ep;
      _podcastLoading = false;
    });
  }

  Future<void> _loadUpdateInfo() async {
    final info = await AppUpdateService.fetchLatest();
    if (!mounted) return;
    setState(() {
      _updateInfo = info;
      _updateLoading = false;
    });
  }

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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionHeader(Icons.system_update_alt_outlined, '更新通知'),
        const SizedBox(height: 8),
        _updateNoticeCard(context),
        const SizedBox(height: 18),
        _sectionHeader(Icons.mic_none_outlined, '鸟瘾综合征 · 最新一期'),
        const SizedBox(height: 8),
        _podcastCard(context),
        const SizedBox(height: 18),
        _sectionHeader(Icons.groups_outlined, '入群交流'),
        const SizedBox(height: 8),
        _wechatGroupCard(context),
        const SizedBox(height: 18),
        _sectionHeader(Icons.newspaper_outlined, '鸟讯'),
        const SizedBox(height: 8),
        _buildComingSoonCard('鸟讯功能开发中'),
        const SizedBox(height: 18),
        _sectionHeader(Icons.volunteer_activism_outlined, '志愿者招募'),
        const SizedBox(height: 8),
        ..._volunteers.map((item) => _buildVolunteerCard(context, item)),
        const SizedBox(height: 8),
        Card(
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
                  const Expanded(
                    child: Text(
                      '如有需要发布研究招募信息，请联系 birderrrr@gmail.com',
                      style: TextStyle(fontSize: 13, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF2d5016)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _updateNoticeCard(BuildContext context) {
    final currentVersion = _updateInfo?.version == appVersionName;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(
          context,
          _updateInfo?.downloadUrl ?? AppUpdateService.downloadUrl,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFF2d5016).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.system_update_alt_outlined,
                  color: Color(0xFF2d5016),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _updateLoading
                          ? '正在检查最新版本...'
                          : (_updateInfo == null
                              ? '打开下载页查看最新版'
                              : currentVersion
                                  ? '当前版本 Birdaholic v$appVersionName'
                                  : '${_updateInfo!.title}'
                                      '${_updateInfo!.releaseDate.isEmpty ? '' : ' · ${_updateInfo!.releaseDate}'}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _updateInfo == null
                          ? '前往下载页'
                          : currentVersion
                              ? '版本 $appVersionName · 已是当前安装包版本'
                              : '版本 ${_updateInfo!.version} · 点击查看下载页',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
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

  Widget _wechatGroupCard(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _openWechatQr(context),
                  child: Container(
                    width: 92,
                    height: 122,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        _wechatGroupQrAsset,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '鸟瘾综合征用户群',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '点击二维码可放大查看，也可以先保存图片，再去微信扫码入群。',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '二维码过期后会在这里更新。',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openWechatQr(context),
                    icon: const Icon(Icons.open_in_full_rounded, size: 18),
                    label: const Text('放大'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _saveWechatQrToDevice(context),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('保存图片'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openWechatQr(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _WechatQrViewer()),
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
                children: [
                  _InfoPill('招募中'),
                  _InfoPill('春迁'),
                  _InfoPill('滨海水鸟'),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.place_outlined, size: 13, color: Colors.grey[500]),
                  const SizedBox(width: 3),
                  Text(item.location,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(width: 12),
                  Icon(Icons.calendar_today_outlined,
                      size: 13, color: Colors.grey[500]),
                  const SizedBox(width: 3),
                  Text(item.date,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
              const SizedBox(height: 5),
              Text('发起：${item.org}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
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

class _WechatQrViewer extends StatelessWidget {
  const _WechatQrViewer();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFCF6),
      appBar: AppBar(
        title: const Text('入群二维码'),
        actions: [
          IconButton(
            tooltip: '保存图片',
            onPressed: () => _saveWechatQrToDevice(context),
            icon: const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: InteractiveViewer(
                  minScale: 0.75,
                  maxScale: 5,
                  boundaryMargin: const EdgeInsets.all(40),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset(
                          _wechatGroupQrAsset,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: () => _saveWechatQrToDevice(context),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('保存图片'),
                ),
              ),
            ),
          ],
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
