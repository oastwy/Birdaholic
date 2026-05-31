import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'privacy_policy_screen.dart';
import 'user_agreement_screen.dart';

/// 首启隐私同意框。返回 true 表示同意，false 表示拒绝（应退出 App）。
Future<bool> showConsentDialog(BuildContext context) async {
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _ConsentDialog(),
  );
  return accepted ?? false;
}

class _ConsentDialog extends StatelessWidget {
  const _ConsentDialog();

  void _open(BuildContext context, Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('欢迎使用鸟瘾综合征'),
        content: SingleChildScrollView(
          child: Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 13.5, height: 1.55),
              children: [
                const TextSpan(
                  text: '在开始使用前，请阅读并同意我们的',
                ),
                TextSpan(
                  text: '《用户协议》',
                  style: const TextStyle(
                    color: Color(0xFF2d5016),
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => _open(context, const UserAgreementScreen()),
                ),
                const TextSpan(text: '和'),
                TextSpan(
                  text: '《隐私政策》',
                  style: const TextStyle(
                    color: Color(0xFF2d5016),
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => _open(context, const PrivacyPolicyScreen()),
                ),
                const TextSpan(text: '。要点：\n\n'),
                const TextSpan(
                  text: '• 我们 ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const TextSpan(text: '不收集'),
                const TextSpan(
                  text: ' 您的位置、通讯录、相册整体内容；学习记录、笔记仅保存在本机。\n\n',
                ),
                const TextSpan(
                  text: '• ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const TextSpan(
                    text: '仅当您主动点"上传"按钮时，您选取的媒体文件和填写的署名/描述会发送到我们的服务器。\n\n'),
                const TextSpan(
                  text: '• 本 App ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const TextSpan(text: '完全免费、无广告、无第三方统计 SDK、非商业用途'),
                const TextSpan(text: '。\n\n'),
                const TextSpan(
                  text: '• 鸟种基础数据 / 媒体来自 eBird、Xeno-canto、iNaturalist、Wikimedia 等公开开放资源；仅受邀用户可上传媒体，上传后需经管理员审核，用户贡献内容按 CC BY-NC 4.0 协议授权。\n\n',
                ),
                const TextSpan(
                  text: '• 仅当您主动配置 eBird API Key 并使用"按位置查询"时，位置坐标会由您的设备直接发往 eBird（美国）；此功能可选，不配置则无任何数据出境。\n\n',
                ),
                const TextSpan(
                  text: '若您不同意上述条款，请退出 App。',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('不同意并退出'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('同意并使用'),
          ),
        ],
      ),
    );
  }
}
