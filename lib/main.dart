import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/consent_dialog.dart';
import 'screens/home_screen.dart';
import 'screens/privacy_policy_screen.dart';
import 'services/notification_service.dart';
import 'services/pack_manager.dart';
import 'services/storage.dart';
import 'services/usage_service.dart';
import 'utils/file_picker_guard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化服务
  final prefs = await SharedPreferences.getInstance();
  final packManager = PackManager();
  final storage = StorageService(prefs);
  await storage.initializeSensitiveCredentials();
  await StorageService.loadTaxonomySynonyms(); // 郑四↔eBird 跨分类清单匹配
  try {
    await packManager.ensureBuiltinPackInstalled();
  } catch (_) {
    // 不阻断启动；设置页的数据包管理里会提供恢复内置包入口。
  }

  // 重新登记每日打卡提醒（仅 Android；保证 App 更新/重启后仍生效）。fire-and-forget。
  if (storage.reminderEnabled) {
    unawaited(NotificationService.scheduleDaily(
        storage.reminderHour, storage.reminderMinute));
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
        child: _FilePickerLifecycleReset(
          child: _ModeGate(
            storage: storage,
            packManager: packManager,
            child: HomeScreen(
              packManager: packManager,
              storage: storage,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilePickerLifecycleReset extends StatefulWidget {
  final Widget child;
  const _FilePickerLifecycleReset({required this.child});

  @override
  State<_FilePickerLifecycleReset> createState() =>
      _FilePickerLifecycleResetState();
}

class _FilePickerLifecycleResetState extends State<_FilePickerLifecycleReset>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FilePickerGuard.forceReset();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive) {
      FilePickerGuard.forceReset();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 首次启动让用户在「新手模式」「自由模式」二选一。
/// 新手模式把内容与进阶入口锁定在「中国常见鸟 100」；自由模式=全功能。
class _ModeGate extends StatefulWidget {
  final StorageService storage;
  final PackManager packManager;
  final Widget child;
  const _ModeGate({
    required this.storage,
    required this.packManager,
    required this.child,
  });

  @override
  State<_ModeGate> createState() => _ModeGateState();
}

class _ModeGateState extends State<_ModeGate> {
  bool _busy = false;

  Future<void> _choose(String mode) async {
    setState(() => _busy = true);
    if (mode == 'beginner') {
      // 新手模式锁定到内置「中国常见鸟 100」包（确保装好+激活到带图那份）。
      // 装包失败时不写入模式：保留模式选择门 + 提示，避免落到「未安装数据包」空首页。
      try {
        await widget.packManager.ensureBuiltinPackInstalled();
        final dir = await widget.packManager.builtinPackDirIfInstalled();
        if (dir == null) throw Exception('内置包未就绪');
        await widget.packManager.setActivePack(dir);
      } catch (e) {
        if (mounted) {
          setState(() => _busy = false);
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('初始化数据包失败，请检查网络/存储后重试：$e')));
        }
        return;
      }
    }
    await widget.storage.setAppMode(mode);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.storage.hasChosenMode) return widget.child;
    const green = Color(0xFF2d5016);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Icon(Icons.eco, size: 56, color: green),
              const SizedBox(height: 16),
              const Text('选择你的使用方式',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('随时可以在「设置 → 学习模式」里切换。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 28),
              _modeCard(
                title: '新手模式',
                subtitle: '只学「中国常见鸟 100」，界面更简单，先把最常见的鸟认熟。',
                icon: Icons.school_outlined,
                highlighted: true,
                onTap: _busy ? null : () => _choose('beginner'),
              ),
              const SizedBox(height: 14),
              _modeCard(
                title: '自由模式',
                subtitle: '全部功能：自定义数据包、各国名录、地点筛选、上传等。',
                icon: Icons.explore_outlined,
                highlighted: false,
                onTap: _busy ? null : () => _choose('free'),
              ),
              const Spacer(),
              if (_busy) const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool highlighted,
    required VoidCallback? onTap,
  }) {
    const green = Color(0xFF2d5016);
    return Material(
      color: highlighted ? green.withValues(alpha: 0.08) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: highlighted ? green : Colors.grey.shade300,
              width: highlighted ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 32, color: green),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey[700],
                            height: 1.4)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: green),
            ],
          ),
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
    // 鸿蒙(HarmonyOS)：已接入华为应用市场「平台隐私托管服务」，由系统在首次启动时
    // 统一弹出隐私声明，App 不再自建隐私弹窗，避免首启出现两次弹窗（华为审核要求）。
    // 用 .name=='ohos' 兜底——TargetPlatform.ohos 枚举仅 flutter-ohos 有，普通 SDK 编不过。
    if (defaultTargetPlatform.name == 'ohos') {
      unawaited(UsageService.recordAppOpen(widget.storage));
      if (mounted) setState(() => _checked = true);
      return;
    }
    final accepted = widget.storage.getConsentAcceptedVersion();
    if (accepted == kPrivacyPolicyVersion) {
      unawaited(UsageService.recordAppOpen(widget.storage));
      if (mounted) setState(() => _checked = true);
      return;
    }
    final ok = await showConsentDialog(context);
    if (ok) {
      await widget.storage.setConsentAccepted(kPrivacyPolicyVersion);
      unawaited(UsageService.recordAppOpen(widget.storage));
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
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
