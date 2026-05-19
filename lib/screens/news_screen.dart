import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
    url: 'http://xhslink.com/o/AVPp9tsUw8V',
    note: '复制链接，在小红书中打开',
  ),
];

class NewsScreen extends StatelessWidget {
  const NewsScreen({super.key});

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
        _sectionHeader('📰 鸟讯'),
        const SizedBox(height: 8),
        _buildComingSoonCard('鸟讯功能开发中'),
        const SizedBox(height: 20),
        _sectionHeader('🙋 志愿者招募'),
        const SizedBox(height: 8),
        ..._volunteers.map((item) => _buildVolunteerCard(context, item)),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Text(title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700));
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
              Text(item.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 6),
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
