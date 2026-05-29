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
      // User declined — exit
      if (Platform.isAndroid || Platform.isIOS) {
        // ignore: deprecated_member_use
        await SystemNavigator.pop();
      } else {
        exit(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return widget.child;
  }
}
