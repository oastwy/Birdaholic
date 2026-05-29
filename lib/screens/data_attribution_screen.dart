import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class DataAttributionScreen extends StatelessWidget {
  const DataAttributionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据声明与致谢')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: const [
          _Section(
            title: '开放数据声明',
            body:
                '本 App 使用的鸟类基础数据（名录、分类、地区分布）来自以下公开学术资源，所有数据均为非商业用途：',
          ),
          _CitationCard(
            name: 'eBird',
            org: 'Cornell Lab of Ornithology',
            description: '全球鸟类观测记录与名录，提供地区物种清单 API',
            url: 'https://ebird.org',
            licenseNote: '名录数据按 eBird API 使用条款，非商业研究/教育用途',
          ),
          _CitationCard(
            name: 'AviList',
            org: 'IOC + Working Group on Avian Checklists',
            description: '全球鸟类权威分类系统（目 / 科 / 属 / 种）',
            url: 'https://avilist.org',
            licenseNote: 'CC BY 4.0 — 署名 4.0 国际',
          ),
          _CitationCard(
            name: '郑光美《中国鸟类分类与分布名录》',
            org: '科学出版社',
            description: '中国鸟类完整名录与分布',
            url: '',
            licenseNote: '学术引用，非商业用途',
          ),
          SizedBox(height: 18),
          _Section(
            title: '媒体素材声明',
            body:
                '本 App 内的物种照片、录音、识别特征来自以下平台或用户贡献，所有素材均保留原作者署名（contributor 字段）。',
          ),
          _CitationCard(
            name: 'Xeno-canto',
            org: 'XC',
            description: '全球鸟类鸣叫共享平台',
            url: 'https://xeno-canto.org',
            licenseNote: 'CC BY-SA / CC BY-NC-SA / CC BY-NC-ND（依录音具体许可）',
          ),
          _CitationCard(
            name: 'iNaturalist',
            org: 'iNaturalist',
            description: '全球自然观察照片共享平台',
            url: 'https://www.inaturalist.org',
            licenseNote: 'CC BY-NC / CC BY-SA 等（依照片具体许可）',
          ),
          _CitationCard(
            name: 'Wikimedia Commons',
            org: 'Wikimedia Foundation',
            description: '维基百科旗下自由媒体素材库',
            url: 'https://commons.wikimedia.org',
            licenseNote: 'CC0 / CC BY / CC BY-SA 等',
          ),
          _CitationCard(
            name: '用户贡献（birdaholic-upload）',
            org: '内测用户 / 管理员',
            description: '由用户主动上传，已签署 CC BY 4.0 授权',
            url: 'https://creativecommons.org/licenses/by/4.0/deed.zh-hans',
            licenseNote: 'CC BY 4.0 — 署名 4.0 国际',
          ),
          SizedBox(height: 18),
          _Section(
            title: 'CC BY 4.0 协议说明',
            body:
                '本 App 中由内测用户和管理员上传的所有媒体均按 CC BY 4.0（署名 4.0 国际）协议公开：'
                '\n• 您可以自由共享、改编这些素材；'
                '\n• 必须**署名**（标注原作者和来源），不得暗示原作者认可您的使用方式；'
                '\n• 用于商业目的也被允许；'
                '\n• 不得附加额外限制条款。',
          ),
          _LinkCard(
            label: '查看 CC BY 4.0 协议全文',
            url: 'https://creativecommons.org/licenses/by/4.0/deed.zh-hans',
          ),
          SizedBox(height: 18),
          _Section(
            title: '商业用途',
            body:
                '本 App 完全免费、无广告，开发由奇趣自然团队志愿维护，不存在任何商业变现行为。'
                '\nApp 内的所有公开数据严格按各来源平台的"非商业用途"条款使用。',
          ),
          _Section(
            title: '感谢',
            body:
                '感谢 eBird、Xeno-canto、iNaturalist、Wikimedia Commons、AviList、郑光美教授团队 以及所有内测用户为本 App 提供的数据和内容。'
                '\n如您发现署名错误或希望撤回您贡献的素材，请通过"关于"页底部的联系方式与我们联系。',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, height: 1.4)),
          const SizedBox(height: 6),
          Text(body,
              style:
                  const TextStyle(fontSize: 13.5, height: 1.55, color: Color(0xFF333333))),
        ],
      ),
    );
  }
}

class _CitationCard extends StatelessWidget {
  final String name;
  final String org;
  final String description;
  final String url;
  final String licenseNote;
  const _CitationCard({
    required this.name,
    required this.org,
    required this.description,
    required this.url,
    required this.licenseNote,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                if (url.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    onPressed: () =>
                        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                  ),
              ],
            ),
            Text('— $org',
                style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            const SizedBox(height: 6),
            Text(description,
                style: const TextStyle(fontSize: 13, height: 1.45)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(licenseNote,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.green[900],
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  final String label;
  final String url;
  const _LinkCard({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.link, color: Color(0xFF2d5016), size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600))),
            const Icon(Icons.open_in_new, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
