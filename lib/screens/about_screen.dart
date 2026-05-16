import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_version.dart';

class AboutScreen extends StatelessWidget {
  final bool embedded;

  const AboutScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final children = [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFC400), Color(0xFFFFE38A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'assets/brand/birdaholic_logo.png',
                width: 120,
                height: 120,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '鸟瘾综合征 Birdaholic',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '奇趣自然团队的观鸟斑块。',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.45),
            ),
            const SizedBox(height: 8),
            Text(
              'v$appVersionName ($appBuildNumber)',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      _section(
        title: '关于鸟瘾综合征',
        icon: Icons.travel_explore_outlined,
        body:
            '鸟瘾综合征是奇趣自然团队的观鸟斑块。我们聚集了一群热爱自然，热爱动物的科研小伙伴，希望通过我们的平台把对自然的热爱传递给每一个热爱生活的朋友。',
      ),
      _section(
        title: '这个 App 想解决什么',
        icon: Icons.lightbulb_outline,
        body:
            'Birdaholic 面向观鸟前的预习和观鸟后的复习：把鸟种清单、鸟鸣、鸟图和个人识别笔记放在一起，用闪卡、选择题和打卡机制帮助你更快进入状态。',
      ),
      _section(
        title: '数据与致谢',
        icon: Icons.volunteer_activism_outlined,
        body:
            '鸟鸣、鸟图和鸟种名录可能来自 eBird、Xeno-canto、Wikimedia、iNaturalist 或用户自建数据包。数据包会为物种保留图片/音频提供者致谢字段，并在学习页展示。',
      ),
      _section(
        title: '隐私原则',
        icon: Icons.privacy_tip_outlined,
        body:
            'API Key 由用户自行填写并保存在本机；识别笔记、纠错日记和学习记录默认只保存在本机。我们不应在代码中内置个人 API Key。',
      ),
      _section(
        title: '找到我们',
        icon: Icons.link_outlined,
        body: '小红书、B站、小宇宙、抖音和微博等平台，全网同名。',
        children: const [
          _SocialLinkTile(
            icon: Icons.podcasts_outlined,
            label: '小宇宙',
            url:
                'https://www.xiaoyuzhoufm.com/podcast/6688a873ae8e21859ade308b',
          ),
          _SocialLinkTile(
            icon: Icons.bookmark_border,
            label: '小红书',
            url:
                'https://www.xiaohongshu.com/user/profile/6516e3ef00000000240167e9',
          ),
          _SocialLinkTile(
            icon: Icons.ondemand_video_outlined,
            label: 'B站',
            url: 'https://space.bilibili.com/3546850323860358',
          ),
          SizedBox(height: 8),
          SelectableText('有问题请联系：birderrrr@gmail.com\n微信 / v：hotpeaker'),
        ],
      ),
    ];
    if (embedded) {
      return Column(children: children);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: children,
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required String body,
    List<Widget> children = const [],
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF2d5016)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(body, style: const TextStyle(height: 1.45)),
                  if (children.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ...children,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SocialLinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;

  const _SocialLinkTile({
    required this.icon,
    required this.label,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    );
  }
}
