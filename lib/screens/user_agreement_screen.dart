import 'package:flutter/material.dart';

const String kUserAgreementVersion = '1.0';
const String kUserAgreementEffectiveDate = '2026-05-22';

class UserAgreementScreen extends StatelessWidget {
  const UserAgreementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('用户协议')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: UserAgreementBody(),
      ),
    );
  }
}

class UserAgreementBody extends StatelessWidget {
  const UserAgreementBody({super.key});

  static const _body = '''
《鸟瘾综合征 Birdaholic 用户协议》

生效日期：$kUserAgreementEffectiveDate
版本：v$kUserAgreementVersion

欢迎使用鸟瘾综合征 Birdaholic（以下简称"本 App"）。本协议是您与本 App 运营者及备案主体——自然人 伍洋（品牌名：奇趣自然团队，以下简称"我们"）之间的法律协议。请您仔细阅读并理解，使用本 App 即视为您同意本协议全部条款。

一、服务内容

本 App 是一款面向观鸟爱好者的鸟种学习工具，主要功能包括：
1. 鸟种闪卡（中文名 / 学名 / 音频 / 图片）；
2. 鸟种浏览、收藏与统计；
3. 数据包导入（本地 ZIP / 服务器下载 / 按地区下载）；
4. 媒体上传（普通用户可保存本地，内测用户和管理员可同步至服务器）。

二、账户与角色

2.1 普通用户：无需注册即可使用大部分功能。上传的媒体仅保存到本机数据包。

2.2 内测用户：由管理员分配上传 Token。上传内容进入审核队列，管理员审核通过后向其他用户公开。

2.3 管理员：拥有审核、用户管理等额外权限。

三、用户行为规范

您承诺在使用本 App 时：

3.1 **不上传含有以下内容的媒体**：
- 鸟类以外的人物面部、隐私信息；
- 侵犯他人版权的素材（请仅上传自己拍摄/录制的内容，或明确具有使用许可的开放素材）；
- 违法、暴力、色情、恐怖、政治敏感内容；
- 虚假或刻意误导的物种鉴定信息。

3.2 **上传素材的权利声明**：您确认拥有所上传素材的著作权或已获得权利人合法授权，并同意以 **CC BY 4.0 协议**（署名 4.0 国际，详见 https://creativecommons.org/licenses/by/4.0/deed.zh-hans ）将其授权给本 App 及其他用户使用。我们将保留您的署名并标注来源。

3.3 您不得通过本 App 实施任何危害他人、网络安全或公共利益的行为。

3.4 不得对本 App 进行反向工程、破解、二次分发牟利等行为。

四、知识产权

4.1 本 App 软件本身（源代码、设计、品牌等）的所有权归我们所有。

4.2 鸟种基础数据（名录、分类）基于 eBird、AviList、郑光美《中国鸟类分类与分布名录》等公开学术资源整理。

4.3 物种图片 / 录音 / 识别特征：
- 来源标注为 eBird、xeno-canto、iNaturalist、Wikimedia Commons 等的，遵守其原平台的开放许可（通常为 CC BY、CC BY-SA、CC BY-NC 等）；
- 来源标注为 birdaholic-upload（即用户贡献）的，遵守 CC BY 4.0；
- 详细许可信息见各物种页面"致谢"区。

五、免责声明

5.1 本 App 完全免费，按"现状"提供，我们不对功能完善性、绝对准确性作出保证。

5.2 物种鉴定结果仅供参考，请勿在科研、商业等场景中作为唯一依据。

5.3 因网络不稳定、服务器维护、API 配额耗尽等导致的功能短期不可用，我们不承担赔偿责任。

5.4 因用户违反本协议（如上传侵权素材）引发的法律责任，由该用户自行承担。

六、商业用途说明

本 App **完全免费、无广告、非商业用途**。我们不向用户收取任何费用，不出售用户数据。

七、协议变更与终止

7.1 我们可能根据国家法律法规及业务发展需要修订本协议，修订后在 App 内公告并请您再次确认。

7.2 如您不同意修订后的协议，可停止使用并卸载本 App。

7.3 如您严重违反本协议，我们有权停止对您的服务（如禁用上传 Token、删除上传内容）。

八、争议解决

本协议的解释、效力及争议解决均适用中华人民共和国法律。因本协议产生的争议，双方应友好协商解决；协商不成的，提交开发者所在地有管辖权的人民法院诉讼解决。

九、联系我们

- 邮箱：birderrrr@gmail.com
- 微信：hotpeaker
- 社交平台：全网搜索"鸟瘾综合征"

ICP 备案：粤ICP备2026057758号-2A
运营者 / 备案主体：伍洋（品牌：奇趣自然团队）
''';

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      _body.trimLeft(),
      style: const TextStyle(
        fontSize: 13.5,
        height: 1.6,
        color: Color(0xFF222222),
      ),
    );
  }
}
