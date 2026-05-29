import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_version.dart';
import 'data_attribution_screen.dart';
import 'privacy_policy_screen.dart';
import 'user_agreement_screen.dart';

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
      Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          children: [
            _navTile(
              icon: Icons.shield_outlined,
              title: '隐私政策',
              builder: (_) => const PrivacyPolicyScreen(),
            ),
            const Divider(height: 0),
            _navTile(
              icon: Icons.gavel_outlined,
              title: '用户协议',
              builder: (_) => const UserAgreementScreen(),
            ),
            const Divider(height: 0),
            _navTile(
              icon: Icons.fact_check_outlined,
              title: '数据声明与致谢（CC BY 4.0）',
              builder: (_) => const DataAttributionScreen(),
            ),
          ],
        ),
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
      const SizedBox(height: 8),
      Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Column(
            children: [
              Text(
                '开发者：伍洋（品牌：奇趣自然团队）',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: () => launchUrl(
                  Uri.parse('https://beian.miit.gov.cn/'),
                  mode: LaunchMode.externalApplication,
                ),
                child: Text(
                  '粤ICP备2026057758号-2A',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '本 App 免费、无广告、非商业用途',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
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

  Widget _navTile({
    required IconData icon,
    required String title,
    required WidgetBuilder builder,
  }) {
    return Builder(
      builder: (ctx) => ListTile(
        leading: Icon(icon, color: const Color(0xFF2d5016)),
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14)),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () => Navigator.push(
          ctx,
          MaterialPageRoute(builder: builder),
        ),
      ),
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
