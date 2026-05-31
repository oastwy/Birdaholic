import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/consent_dialog.dart';
import 'screens/home_screen.dart';
import 'screens/privacy_policy_screen.dart';
import 'services/pack_manager.dart';
import 'services/storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化服务
  final prefs = await SharedPreferences.getInstance();
  final packManager = PackManager();
  final storage = StorageService(prefs);
  try {
    await packManager.ensureBuiltinPackInstalled();
  } catch (_) {
    // 不阻断启动；设置页的数据包管理里会提供恢复内置包入口。
  }

  runApp(BirdFlashcardApp(
    packManager: packManager,
    storage: storage,
  ));
}

class BirdFlashcardApp extends StatelessWidget {
  final PackManager packManager;
  final StorageService storage;

  const BirdFlashcardApp({
    super.key,
    required this.packManager,
    required this.storage,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '鸟瘾综合征',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2d5016),
        useMaterial3: true,
      ),
      home: _ConsentGate(
        storage: storage,
        child: HomeScreen(
          packManager: packManager,
          storage: storage,
        ),
      ),
    );
  }
}

class _ConsentGate extends StatefulWidget {
  final StorageService storage;
  final Widget child;
  const _ConsentGate({required this.storage, required this.child});

  @override
  State<_ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends State<_ConsentGate> {
  bool _checked = false;
  bool _declined = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final accepted = widget.storage.getConsentAcceptedVersion();
    if (accepted == kPrivacyPolicyVersion) {
      if (mounted) setState(() => _checked = true);
      return;
    }
    final ok = await showConsentDialog(context);
    if (ok) {
      await widget.storage.setConsentAccepted(kPrivacyPolicyVersion);
      if (mounted) setState(() => _checked = true);
    } else {
      // 用户拒绝：Android 直接退出；iOS 不允许程序化退出，显示提示页
      if (Platform.isAndroid) {
        // ignore: deprecated_member_use
        await SystemNavigator.pop();
      } else if (!Platform.isIOS) {
        exit(0);
      }
      if (mounted) setState(() => _declined = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_declined) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('需同意协议后才能使用',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                const Text(
                  '您已拒绝《用户协议》和《隐私政策》。如需使用本 App，请重新阅读并同意；或直接关闭 App。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    setState(() => _declined = false);
                    _check();
                  },
                  child: const Text('重新阅读协议'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (!_checked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return widget.child;
  }
}
