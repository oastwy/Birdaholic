import 'package:flutter/material.dart';

const String kPrivacyPolicyVersion = '1.0';
const String kPrivacyPolicyEffectiveDate = '2026-05-22';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('隐私政策')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: PrivacyPolicyBody(),
      ),
    );
  }
}

class PrivacyPolicyBody extends StatelessWidget {
  const PrivacyPolicyBody({super.key});

  static const _body = '''
《鸟瘾综合征 Birdaholic 隐私政策》

生效日期：$kPrivacyPolicyEffectiveDate
版本：v$kPrivacyPolicyVersion

本 App 的运营者及备案主体为自然人 伍洋（品牌名：奇趣自然团队，以下简称"我们"），非常重视您的个人信息保护。本政策说明我们在您使用本 App 过程中如何收集、使用、存储和保护您的信息，请您仔细阅读并理解。

一、我们处理哪些信息

1.1 本机保存的数据（不上传服务器）
- 学习记录：闪卡答题情况、收藏的鸟种、打卡日历；
- 设置：API Key、上传 Token、署名、闪卡每组数量等偏好；
- 笔记：识别笔记、纠错日记的本机备份。
以上数据存于本设备的 SharedPreferences 中，**不会**主动上传服务器，卸载 App 即删除。

1.2 上传到服务器的内容（仅受邀用户主动触发）
服务器上传功能仅向受邀用户和管理员开放。仅当受邀用户主动点击"上传"按钮时，下列内容会发送到我们的服务器（birding.today），并需经管理员审核后才会公开：
- 您选择的照片 / 录音文件；
- 您填写的署名、描述、识别特征、难度评级；
- 上传 Token（若已配置）：用于识别您的身份并归属署名；
- 上传时间。
此外，当您在闪卡中点"记录纠错"时，纠错内容、所涉物种、当前页面会同步发送，便于我们核对修正。

1.3 网络请求
- 调用您配置的 eBird API Key 查询鸟种名录（请求直接发给 ebird.org）；
- 从 birding.today 拉取鸟种媒体（图片、音频、识别特征）；
- 从 GitHub 检查 App 更新版本。

1.4 我们 **不会** 收集
- 您的精确定位用于追踪（仅在您主动选用"按位置查询"时由您的设备获取一次，见第六节）；
- 您的通讯录、短信、通话记录；
- 您相册中除您主动选取上传文件以外的内容；
- 您的手机号、身份证号、银行卡号等敏感信息；
- 设备唯一标识符、IMEI、MAC、广告 ID 等。

1.5 第三方 SDK
本 App **未集成任何统计、广告、推送、社交 SDK**，无任何第三方代码在后台采集您的信息。

二、个人信息收集清单

| 信息类型 | 收集场景 | 用途 | 是否离开本机 |
| --- | --- | --- | --- |
| 学习记录、收藏、笔记 | 使用 App | 学习进度统计 | 否（仅本机） |
| API Key / 上传 Token | 您手动填写 | 调用 eBird / 归属上传署名 | 仅随对应请求发送 |
| 位置坐标（经纬度） | 您点"按位置查询" | 查询附近鸟种名录 | 是 → 发往 eBird（境外，见第六节），我方不接收 |
| 照片 / 录音 + 署名/描述 | 受邀用户点"上传" | 审核后公开到对应物种页 | 是 → 我方服务器 |

除上表外，我们不收集任何其他个人信息。

三、第三方共享与数据出境清单

| 第三方 | 共享内容 | 触发条件 | 所在地 |
| --- | --- | --- | --- |
| eBird（康奈尔大学鸟类学实验室） | 您的位置坐标 或 地区代码 + 您的 API Key | 仅当您主动使用"按位置/地区查询"功能 | **美国（数据出境）** |
| GitHub | 仅请求版本号，不发送任何个人信息 | 检查更新 | 美国 |

**关于数据出境的重要说明**：当您主动配置 eBird API Key 并使用"按位置查询"时，您的位置坐标会由**您的设备直接发送至 eBird（美国）**，用于换取附近鸟种名录。该请求不经过我方服务器，我方不接收、不存储您的位置。此功能为可选，若您不配置 eBird API Key 即不会发生任何数据出境。您使用该功能即视为同意上述出境行为。

除上表外，我们不向任何第三方出售、出租、共享您的个人信息。

四、儿童信息保护

本 App 面向 13 岁以上观鸟爱好者。13 岁以下儿童使用需在监护人指导下进行。我们不会主动收集儿童的个人信息。

五、信息存储与安全

- 我方服务器位于中国境内（腾讯云）；
- App 与我方服务器之间的全部通信均使用 HTTPS 加密；
- 上传 Token 仅用于审核归属，不与手机号等身份信息绑定；
- 您的本机数据使用操作系统安全沙盒存储；
- 我们采取合理且必要的措施保护您的信息免受未经授权的访问。

六、您的权利（含账号注销）

- 查看 / 修改本机数据：在"设置"中完成；
- **注销 / 解绑身份**：受邀用户在"设置 → 上传 Token"中清空 Token，即视为解除身份绑定（注销）。我方 users.json 中的 Token 可应您要求撤销；
- 删除已上传的媒体：联系管理员（见末尾邮箱）告知物种与文件名，我们会人工删除；
- 撤回数据出境授权：清空"设置"中的 eBird API Key 即停止一切出境请求；
- 卸载本 App 即可清除全部本机数据。

七、数据来源与署名

App 内呈现的物种媒体来自：
- eBird (Cornell Lab of Ornithology)：名录、物种代码；
- Xeno-canto：录音；
- iNaturalist、Wikimedia Commons：照片；
- 受邀用户/管理员主动贡献：照片、录音、识别特征。
我们对所有数据均保留原作者署名（contributor 字段）。具体许可详见"数据声明与致谢"页。

八、商业用途

本 App **完全免费、无广告、非商业用途**。我们不会出售、出租或交换您的任何信息。

九、政策变更

如本政策修订，我们会在 App 内"关于"页面显示新版本号，并在首次启动时再次邀请您阅读同意。

十、联系我们

如对本政策有任何疑问、投诉或建议：
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
