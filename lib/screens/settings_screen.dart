import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_version.dart';
import '../services/admin_upload_service.dart';
import '../services/app_update_service.dart';
import '../services/notification_service.dart';
import '../services/storage.dart';
import '../services/pack_manager.dart';
import 'audit_history_section.dart';
import 'data_attribution_screen.dart';
import 'life_list_screen.dart';
import 'pack_manage_screen.dart';
import 'privacy_policy_screen.dart';
import 'rate_review_screen.dart';
import 'rate_species_screen.dart';
import 'tutorial_screen.dart';
import 'upload_review_section.dart';
import '../widgets/update_download_dialog.dart';
import 'user_agreement_screen.dart';

class SettingsScreen extends StatefulWidget {
  final StorageService storage;
  final PackManager packManager;
  final VoidCallback? onSettingsChanged;
  final VoidCallback? onPackChanged;

  const SettingsScreen({
    super.key,
    required this.storage,
    required this.packManager,
    this.onSettingsChanged,
    this.onPackChanged,
  });

  static Future<void> openPackManager(
    BuildContext context, {
    required PackManager packManager,
    required StorageService storage,
    VoidCallback? onPackChanged,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('数据包管理')),
          body: PackManageScreen(
            packManager: packManager,
            storage: storage,
            onPackChanged: onPackChanged,
          ),
        ),
      ),
    );
  }

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _checkingUpdate = false;

  Future<void> _checkForUpdates() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final info = await AppUpdateService.fetchLatest(forceRefresh: true);
      if (!mounted) return;
      if (AppUpdateService.isNewerThanCurrent(info.version)) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('发现新版本 v${info.version}'),
            content: Text(
              info.releaseDate.isEmpty
                  ? '当前版本 v$appVersionName，可以前往下载页更新。'
                  : '发布日期：${info.releaseDate}\n当前版本 v$appVersionName，可以前往下载页更新。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('稍后'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('去下载'),
              ),
            ],
          ),
        );
        if (go == true) {
          if (!mounted) return;
          final apkUrl = info.apkAssetUrl;
          // 直链是安卓 APK，其他平台(iOS等)一律退回打开下载页，别在非安卓上拉起装 apk。
          if (Platform.isAndroid && apkUrl != null && apkUrl.isNotEmpty) {
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => UpdateDownloadDialog(info: info),
            );
          } else {
            await launchUrl(
              Uri.parse(info.downloadUrl),
              mode: LaunchMode.externalApplication,
            );
          }
        }
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已是最新版本 v$appVersionName')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('检查更新失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _editApiSettings() async {
    final xenoController = TextEditingController(
      text: widget.storage.getXenoCantoApiKey(),
    );
    final ebirdController = TextEditingController(
      text: widget.storage.getEBirdApiKey(),
    );
    final adminController = TextEditingController(
      text: widget.storage.getAdminUploadToken(),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('API Key 与上传身份'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: xenoController,
              decoration: const InputDecoration(
                labelText: 'xeno-canto API Key',
                hintText: '用于第三方鸟鸣补充下载',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ebirdController,
              decoration: const InputDecoration(
                labelText: 'eBird API Key',
                hintText: '用于地点/附近鸟种筛选',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: adminController,
              decoration: const InputDecoration(
                labelText: '上传 Token',
                hintText: '管理员 / 受邀用户填写各自 Token，保存后自动识别身份',
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (saved == true) {
      await widget.storage.setXenoCantoApiKey(xenoController.text);
      await widget.storage.setEBirdApiKey(ebirdController.text);
      final newToken = adminController.text.trim();
      await widget.storage.setAdminUploadToken(newToken);
      String identityMsg = '';
      if (newToken.isNotEmpty) {
        try {
          final who = await AdminUploadService().whoami(token: newToken);
          if (who != null) {
            await widget.storage
                .setUserIdentity(role: who.role, name: who.name);
            identityMsg = who.role == 'admin' ? '（管理员）' : '（内测：${who.name}）';
          } else {
            await widget.storage.setUserIdentity(role: '', name: '');
            identityMsg = '（Token 无效）';
          }
        } catch (_) {
          identityMsg = '（无法连接服务器，身份未识别）';
        }
      } else {
        await widget.storage.setUserIdentity(role: '', name: '');
      }
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('设置已保存$identityMsg')),
      );
    }
  }

  Future<void> _openFeedbackNotifications() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _FeedbackNotificationsScreen(storage: widget.storage),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openUploadAccessRequest() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _UploadAccessRequestScreen(storage: widget.storage),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openContentReview() async {
    final navigator = Navigator.of(context);
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (ctx) => UploadReviewSection(
          storage: widget.storage,
          onBack: () => Navigator.of(ctx).maybePop(),
          onOpenHistory: () => Navigator.of(ctx).push(
            MaterialPageRoute(
              builder: (hctx) => AuditHistorySection(
                storage: widget.storage,
                onBack: () => Navigator.of(hctx).maybePop(),
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openTokenRequests() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _AdminTokenRequestsScreen(storage: widget.storage),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _switchAppMode() async {
    final current = widget.storage.appMode;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('学习模式',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ),
            RadioListTile<String>(
              value: 'beginner',
              groupValue: current,
              onChanged: (v) => Navigator.pop(ctx, v),
              title: const Text('新手模式'),
              subtitle: const Text('只学中国常见鸟 100，界面更简单，隐藏进阶功能'),
            ),
            RadioListTile<String>(
              value: 'free',
              groupValue: current,
              onChanged: (v) => Navigator.pop(ctx, v),
              title: const Text('自由模式'),
              subtitle: const Text('全部功能：自定义数据包、各国名录、地点筛选、上传等'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == current) return;
    await widget.storage.setAppMode(picked);
    if (picked == 'beginner') {
      // 切到新手：把激活包切回内置「中国常见鸟 100」（带图那份）。
      try {
        await widget.packManager.ensureBuiltinPackInstalled();
        final dir = await widget.packManager.builtinPackDirIfInstalled();
        if (dir != null) await widget.packManager.setActivePack(dir);
      } catch (_) {}
      widget.onPackChanged?.call();
    }
    if (mounted) setState(() {});
  }

  Widget _groupHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final beginner = widget.storage.isBeginnerMode;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        if (widget.storage.isAdminMode) ...[
          _groupHeader('审核'),
          Card(
            color: const Color(0xFFFFF7E6),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.verified_outlined,
                      color: Color(0xFF8a5a00)),
                  title: const Text('内容审核'),
                  subtitle: const Text('审核用户上传的鸟图 / 鸟鸣（通过 / 通过置顶 / 拒绝）'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openContentReview,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.how_to_reg_outlined,
                      color: Color(0xFF8a5a00)),
                  title: const Text('上传权限审批'),
                  subtitle: const Text('查看并审批用户的上传权限申请'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openTokenRequests,
                ),
                const Divider(height: 1),
                ListTile(
                  leading:
                      const Icon(Icons.rule_outlined, color: Color(0xFF8a5a00)),
                  title: const Text('评级审核'),
                  subtitle: const Text('审核内测用户提交的评级'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RateReviewScreen(storage: widget.storage),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.star_rate_outlined,
                      color: Color(0xFF8a5a00)),
                  title: const Text('逐种评级'),
                  subtitle: const Text('给物种难度与图片质量打分（直接生效）'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          RateSpeciesScreen(storage: widget.storage),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (widget.storage.isBetaMode && !widget.storage.isAdminMode) ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.star_rate_outlined,
                  color: Color(0xFF2d5016)),
              title: const Text('逐种评级'),
              subtitle: const Text('给物种难度与图片质量打分 · 提交后由管理员审核'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RateSpeciesScreen(storage: widget.storage),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        _groupHeader('学习'),
        Card(
          child: ListTile(
            leading: Icon(
              beginner ? Icons.school_outlined : Icons.explore_outlined,
              color: const Color(0xFF2d5016),
            ),
            title: const Text('学习模式'),
            subtitle: Text(beginner ? '新手模式 · 专注中国常见鸟 100' : '自由模式 · 全部功能与数据包'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _switchAppMode,
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.style_outlined, color: Color(0xFF2d5016)),
            title: const Text('闪卡设置'),
            subtitle: Text('每组 ${widget.storage.flashcardGroupSize} 张'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => _FlashcardSettingsScreen(
                    storage: widget.storage,
                    onSettingsChanged: widget.onSettingsChanged,
                  ),
                ),
              );
              if (mounted) setState(() {});
            },
          ),
        ),
        if (!beginner) ...[
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_zip, color: Color(0xFF2d5016)),
              title: const Text('数据包管理'),
              subtitle: const Text('安装、下载、导入、更新和删除数据包'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => SettingsScreen.openPackManager(
                context,
                packManager: widget.packManager,
                storage: widget.storage,
                onPackChanged: widget.onPackChanged,
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        _groupHeader('账号与上传'),
        Card(
          child: Column(
            children: [
              if (!beginner) ...[
                ListTile(
                  leading: const Icon(Icons.key, color: Color(0xFF2d5016)),
                  title: const Text('API Key 与上传身份'),
                  subtitle: Text(
                    widget.storage.getEBirdApiKey().isEmpty &&
                            widget.storage.getXenoCantoApiKey().isEmpty &&
                            widget.storage.getAdminUploadToken().isEmpty
                        ? '未填写'
                        : widget.storage.isAdminMode
                            ? '管理员（${widget.storage.getUserName()}）'
                            : widget.storage.isBetaMode
                                ? '受邀用户（${widget.storage.getUserName()}）'
                                : '已配置',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _editApiSettings,
                ),
                const Divider(height: 1),
                ListTile(
                  leading:
                      const Icon(Icons.checklist_rtl, color: Color(0xFF2d5016)),
                  title: const Text('我的观鸟清单 (life list)'),
                  subtitle: Text(
                    widget.storage.lifeListCount > 0
                        ? '已记录 ${widget.storage.lifeListCount} 种 · 导入 eBird / 记录中心 或手动标记'
                        : '导入 eBird CSV / 记录中心 Excel / 手动标记，打卡可筛「未见过」',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LifeListScreen(storage: widget.storage),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.cloud_upload_outlined,
                    color: Color(0xFF2d5016),
                  ),
                  title: const Text('申请上传权限'),
                  subtitle: Text(
                    widget.storage.hasUploadAccess
                        ? '已开通：${widget.storage.getUserName().isEmpty ? '上传用户' : widget.storage.getUserName()}'
                        : '无需注册，提交匿名申请后等待管理员审核',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openUploadAccessRequest,
                ),
              ],
              ListTile(
                leading: const Icon(
                  Icons.notifications_none_outlined,
                  color: Color(0xFF2d5016),
                ),
                title: const Text('反馈与通知'),
                subtitle: Text(
                  widget.storage.getAdminUploadToken().isEmpty
                      ? '${widget.storage.getFeedbackJournal().length} 条本地记录 · 本机回执接收回复'
                      : '${widget.storage.getFeedbackJournal().length} 条本地记录 · 查看管理员回复',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openFeedbackNotifications,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _groupHeader('帮助与关于'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.menu_book_outlined,
                    color: Color(0xFF2d5016)),
                title: const Text('新手教程'),
                subtitle: const Text('打卡 / 预习 / 上传 / API 申请 / 抽象图理念，看这一篇'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TutorialScreen()),
                ),
              ),
              const Divider(height: 0),
              ListTile(
                leading:
                    const Icon(Icons.shield_outlined, color: Color(0xFF2d5016)),
                title: const Text('隐私政策'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PrivacyPolicyScreen()),
                ),
              ),
              const Divider(height: 0),
              ListTile(
                leading:
                    const Icon(Icons.gavel_outlined, color: Color(0xFF2d5016)),
                title: const Text('用户协议'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const UserAgreementScreen()),
                ),
              ),
              const Divider(height: 0),
              ListTile(
                leading: const Icon(Icons.fact_check_outlined,
                    color: Color(0xFF2d5016)),
                title: const Text('声明与致谢'),
                subtitle: const Text('关于 App、数据来源、许可协议和联系方式'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DataAttributionScreen()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const _FollowUsCard(),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: _checkingUpdate
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.system_update_alt,
                    color: Color(0xFF2d5016),
                  ),
            title: const Text('检查版本更新'),
            subtitle: const Text('当前版本 v$appVersionName ($appBuildNumber)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _checkingUpdate ? null : _checkForUpdates,
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            '版本：v$appVersionName ($appBuildNumber)',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: GestureDetector(
            onTap: () => launchUrl(Uri.parse('https://beian.miit.gov.cn/'),
                mode: LaunchMode.externalApplication),
            child: Text(
              '粤ICP备2026057758号-2A',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _UploadAccessRequestScreen extends StatefulWidget {
  final StorageService storage;

  const _UploadAccessRequestScreen({required this.storage});

  @override
  State<_UploadAccessRequestScreen> createState() =>
      _UploadAccessRequestScreenState();
}

class _UploadAccessRequestScreenState
    extends State<_UploadAccessRequestScreen> {
  final AdminUploadService _service = AdminUploadService();
  final TextEditingController _noteController = TextEditingController();
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  UploadAccessRequestStatus? _status;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  String _platformLabel(TargetPlatform platform) {
    // 注意：不要直接写 `case TargetPlatform.ohos`——该枚举值仅 flutter-ohos 有，
    // 用普通 .flutter-sdk 编译（安卓/ iOS 单独打包）会报 Member not found: 'ohos'。
    // 改用 .name 兜住 ohos，switch 加 default，两套工具链都能编译；鸿蒙端仍返回 'ohos'。
    if (platform.name == 'ohos') return 'ohos';
    switch (platform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
      // 保留 default 兜底跨工具链（见上方注释，勿删）；普通 SDK 下分析器视其为冗余，故抑制。
      // ignore: unreachable_switch_default
      default:
        return platform.name;
    }
  }

  Future<void> _applyApprovedStatus(UploadAccessRequestStatus status) async {
    if (!status.isApproved) return;
    await widget.storage.setAdminUploadToken(status.token);
    await widget.storage.setUserIdentity(
      role: status.role.isEmpty ? 'beta' : status.role,
      name: status.name.isEmpty ? '上传用户' : status.name,
    );
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final clientId = await widget.storage.ensureFeedbackClientId();
      final status =
          await _service.fetchUploadAccessRequestStatus(clientId: clientId);
      await _applyApprovedStatus(status);
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _submitRequest() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final clientId = await widget.storage.ensureFeedbackClientId();
      final status = await _service.submitUploadAccessRequest(
        clientId: clientId,
        note: _noteController.text.trim(),
        platform: _platformLabel(defaultTargetPlatform),
        appVersion: appVersionName,
        appBuild: '$appBuildNumber',
      );
      await _applyApprovedStatus(status);
      if (!mounted) return;
      setState(() => _status = status);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status.isApproved ? '上传权限已开通' : '申请已提交，等待管理员审核',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _formatUnixTime(int seconds) {
    if (seconds <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  IconData _statusIcon(UploadAccessRequestStatus? status) {
    if (status == null || status.isNone) return Icons.outbox_outlined;
    if (status.isApproved) return Icons.check_circle_outline;
    if (status.isRejected) return Icons.cancel_outlined;
    return Icons.hourglass_empty;
  }

  String _statusTitle(UploadAccessRequestStatus? status) {
    if (widget.storage.hasUploadAccess && (status == null || status.isNone)) {
      return '已拥有上传权限';
    }
    if (status == null || status.isNone) return '还没有提交申请';
    if (status.isApproved) return '上传权限已开通';
    if (status.isRejected) return '申请未通过';
    return '申请审核中';
  }

  String _statusText(UploadAccessRequestStatus? status) {
    if (widget.storage.hasUploadAccess && (status == null || status.isNone)) {
      final name = widget.storage.getUserName();
      return name.isEmpty ? '当前设备已保存上传身份。' : '当前身份：$name。';
    }
    if (status == null || status.isNone) {
      return '提交后管理员会在后台审核；通过后这里会自动写入上传 Token。';
    }
    if (status.isApproved) {
      final name = status.name.isEmpty ? '上传用户' : status.name;
      return '当前身份：$name。现在可以在鸟种详情页上传候选图片和音频。';
    }
    if (status.isRejected) {
      return status.reply.isEmpty ? '管理员暂未开放上传权限，可以稍后重新申请。' : status.reply;
    }
    final time = _formatUnixTime(status.createdAt);
    return time.isEmpty ? '管理员还没有处理这次申请。' : '提交时间：$time。管理员还没有处理。';
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final canSubmit = !_submitting &&
        !_loading &&
        (status == null || status.isNone || status.isRejected);
    return Scaffold(
      appBar: AppBar(
        title: const Text('申请上传权限'),
        actions: [
          IconButton(
            tooltip: '刷新状态',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadStatus,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _statusIcon(status),
                    color: const Color(0xFF2d5016),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _statusTitle(status),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_loading)
                          const LinearProgressIndicator()
                        else
                          Text(
                            _statusText(status),
                            style: TextStyle(
                              color: Colors.grey[700],
                              height: 1.35,
                            ),
                          ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            '加载失败：$_error',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '说明',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '申请不会要求手机号、微信、邮箱或姓名，只会发送本机匿名申请号、App 版本和平台信息，用于管理员审核和回传上传身份。',
                    style: TextStyle(color: Colors.grey[700], height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _noteController,
                    enabled: canSubmit,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '备注（可不填）',
                      hintText: '例如：我想补充本地鸟图或鸟鸣',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: canSubmit ? _submitRequest : null,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.send_outlined),
                          label: Text(
                            status != null && status.isRejected
                                ? '重新申请'
                                : '提交申请',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: _loading ? null : _loadStatus,
                        child: const Text('刷新'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackNotificationsScreen extends StatefulWidget {
  final StorageService storage;

  const _FeedbackNotificationsScreen({required this.storage});

  @override
  State<_FeedbackNotificationsScreen> createState() =>
      _FeedbackNotificationsScreenState();
}

class _FeedbackNotificationsScreenState
    extends State<_FeedbackNotificationsScreen> {
  final AdminUploadService _service = AdminUploadService();
  bool _loading = false;
  String? _error;
  List<FeedbackReplyEntry> _replies = const [];

  @override
  void initState() {
    super.initState();
    _loadReplies();
  }

  Future<void> _loadReplies() async {
    final token = widget.storage.getAdminUploadToken();
    final clientId = await widget.storage.ensureFeedbackClientId();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final replies = await _service.fetchFeedbackReplies(
        token: token,
        clientId: clientId,
      );
      if (!mounted) return;
      setState(() {
        _replies = replies;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _formatUnixTime(int seconds) {
    if (seconds <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatLocalTime(String iso) {
    if (iso.length < 16) return iso;
    return iso.substring(0, 16).replaceFirst('T', ' ');
  }

  Future<void> _copyJournal(List<FeedbackEntry> entries) async {
    final text = entries.map((item) {
      final species = item.speciesCn.isNotEmpty
          ? '${item.speciesCn} (${item.speciesSci})'
          : item.speciesSci;
      return '[${_formatLocalTime(item.createdAt)}] '
          '${item.page}${species.isNotEmpty ? ' · $species' : ''}\n${item.message}';
    }).join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制本地纠错记录')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final token = widget.storage.getAdminUploadToken();
    final entries = widget.storage.getFeedbackJournal();
    return Scaffold(
      appBar: AppBar(
        title: const Text('反馈与通知'),
        actions: [
          if (token.isNotEmpty)
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _loadReplies,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadReplies,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _replySection(token),
            const SizedBox(height: 14),
            _journalSection(entries),
          ],
        ),
      ),
    );
  }

  Widget _replySection(String token) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.mark_chat_read_outlined, color: Color(0xFF2d5016)),
                SizedBox(width: 8),
                Text(
                  '管理员回复',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (token.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _hintPanel(
                  icon: Icons.privacy_tip_outlined,
                  text: '当前使用本机反馈回执接收回复，不需要上传身份 Token。卸载重装后，旧匿名反馈可能无法继续关联。',
                ),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _hintPanel(
                    icon: Icons.error_outline,
                    text: '拉取通知失败：$_error',
                    color: Colors.red,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _loadReplies,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              )
            else if (_replies.isEmpty)
              _hintPanel(
                icon: Icons.inbox_outlined,
                text: '还没有管理员回复。你的反馈被处理后，会显示在这里。',
              )
            else
              ..._replies.map(_replyTile),
          ],
        ),
      ),
    );
  }

  Widget _replyTile(FeedbackReplyEntry item) {
    final replyTime = _formatUnixTime(item.repliedAt);
    final createdTime = _formatUnixTime(item.createdAt);
    final species = item.speciesCn.isNotEmpty
        ? '${item.speciesCn} · ${item.speciesSci}'
        : item.speciesSci;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: item.hasReply
            ? const Color(0xFFedf5e7)
            : Colors.grey.withValues(alpha: 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                item.hasReply
                    ? Icons.check_circle_outline
                    : Icons.hourglass_empty,
                size: 18,
                color: item.hasReply ? const Color(0xFF2d5016) : Colors.grey,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.hasReply ? '已回复' : '等待回复',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (replyTime.isNotEmpty)
                Text(
                  replyTime,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
            ],
          ),
          if (item.hasReply) ...[
            const SizedBox(height: 8),
            Text(item.reply),
            if (item.responder.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '回复人：${item.responder}',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ],
          ],
          const SizedBox(height: 10),
          Text(
            '原反馈',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Text(item.message),
          if (species.isNotEmpty || item.page.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (item.page.isNotEmpty) _chip(Icons.map_outlined, item.page),
                if (species.isNotEmpty)
                  _chip(Icons.flutter_dash_outlined, species),
                if (createdTime.isNotEmpty)
                  _chip(Icons.schedule_outlined, createdTime),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _journalSection(List<FeedbackEntry> entries) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.menu_book_outlined, color: Color(0xFF2d5016)),
                const SizedBox(width: 8),
                const Text(
                  '本地纠错记录',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (entries.isNotEmpty)
                  TextButton(
                    onPressed: () => _copyJournal(entries),
                    child: const Text('复制'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (entries.isEmpty)
              _hintPanel(
                icon: Icons.edit_note_outlined,
                text: '还没有本地记录。在闪卡页点纠错按钮后，会保存在这里。',
              )
            else
              ...entries.map(_journalTile),
          ],
        ),
      ),
    );
  }

  Widget _journalTile(FeedbackEntry item) {
    final species = item.speciesCn.isNotEmpty
        ? '${item.speciesCn} · ${item.speciesSci}'
        : item.speciesSci;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            species.isNotEmpty
                ? species
                : (item.page.isEmpty ? '纠错反馈' : item.page),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            _formatLocalTime(item.createdAt),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(item.message),
        ],
      ),
    );
  }

  Widget _hintPanel({
    required IconData icon,
    required String text,
    Color? color,
  }) {
    final fg = color ?? Colors.grey[700]!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (color ?? Colors.grey).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: fg, height: 1.35)),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.grey[700]),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class _FlashcardSettingsScreen extends StatefulWidget {
  final StorageService storage;
  final VoidCallback? onSettingsChanged;

  const _FlashcardSettingsScreen({
    required this.storage,
    this.onSettingsChanged,
  });

  @override
  State<_FlashcardSettingsScreen> createState() =>
      _FlashcardSettingsScreenState();
}

class _FlashcardSettingsScreenState extends State<_FlashcardSettingsScreen> {
  late final TextEditingController _groupController;
  late int _groupSize;
  late List<String> _quizNameModes;
  late bool _startFullscreen;
  late int _dailyGoal;
  late bool _reminderOn;
  late int _reminderHour;
  late int _reminderMinute;

  @override
  void initState() {
    super.initState();
    _groupSize = widget.storage.flashcardGroupSize;
    _groupController = TextEditingController(text: '$_groupSize');
    _quizNameModes = List.of(widget.storage.quizNameModes);
    _startFullscreen = widget.storage.flashcardStartFullscreen;
    _dailyGoal = widget.storage.dailyGoal;
    _reminderOn = widget.storage.reminderEnabled;
    _reminderHour = widget.storage.reminderHour;
    _reminderMinute = widget.storage.reminderMinute;
  }

  String get _reminderTimeLabel =>
      '${_reminderHour.toString().padLeft(2, '0')}:${_reminderMinute.toString().padLeft(2, '0')}';

  Future<void> _toggleReminder(bool on) async {
    if (on) {
      final granted = await NotificationService.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未获得通知权限，请在系统设置里允许通知后再开启')),
          );
        }
        return;
      }
      await NotificationService.scheduleDaily(_reminderHour, _reminderMinute);
    } else {
      await NotificationService.cancel();
    }
    await widget.storage.setReminderEnabled(on);
    if (!mounted) return;
    setState(() => _reminderOn = on);
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reminderHour, minute: _reminderMinute),
    );
    if (picked == null) return;
    await widget.storage.setReminderTime(picked.hour, picked.minute);
    if (_reminderOn) {
      await NotificationService.scheduleDaily(picked.hour, picked.minute);
    }
    if (!mounted) return;
    setState(() {
      _reminderHour = picked.hour;
      _reminderMinute = picked.minute;
    });
  }

  Future<void> _setStartFullscreen(bool value) async {
    await widget.storage.setFlashcardStartFullscreen(value);
    if (!mounted) return;
    setState(() => _startFullscreen = value);
    widget.onSettingsChanged?.call();
  }

  Future<void> _setDailyGoal(int value) async {
    final v = value.clamp(1, 200);
    await widget.storage.setDailyGoal(v);
    if (!mounted) return;
    setState(() => _dailyGoal = v);
    widget.onSettingsChanged?.call();
  }

  Future<void> _toggleQuizMode(String mode) async {
    final next = List<String>.from(_quizNameModes);
    if (next.contains(mode)) {
      if (next.length <= 1) return; // 至少保留一项
      next.remove(mode);
    } else {
      next.add(mode);
    }
    await widget.storage.setQuizNameModes(next);
    if (!mounted) return;
    setState(() => _quizNameModes = next);
    widget.onSettingsChanged?.call();
  }

  @override
  void dispose() {
    _groupController.dispose();
    super.dispose();
  }

  Future<void> _setGroupSize(int value) async {
    final normalized = value.clamp(1, 100);
    await widget.storage.setFlashcardGroupSize(normalized);
    if (!mounted) return;
    setState(() {
      _groupSize = normalized;
      _groupController.text = '$normalized';
    });
    widget.onSettingsChanged?.call();
  }

  Future<void> _applyCustomGroupSize() async {
    final value = int.tryParse(_groupController.text.trim());
    if (value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 1-100 之间的数字')),
      );
      return;
    }
    await _setGroupSize(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已设置每组 $_groupSize 张')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('闪卡设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Card(
            child: SwitchListTile(
              value: _startFullscreen,
              onChanged: _setStartFullscreen,
              title: const Text('开始打卡直接进入全屏'),
              subtitle: const Text('关闭时，开始打卡先停在带筛选条的窗口视图，方便先选范围；点「开始打卡」按钮再进全屏'),
              activeColor: const Color(0xFF2d5016),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('每日目标'),
                  const SizedBox(height: 4),
                  Text('每天打卡多少张算达标（首页显示进度与连续天数）',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final g in [5, 10, 20, 30, 50])
                        ChoiceChip(
                          label: Text('$g 张'),
                          selected: _dailyGoal == g,
                          onSelected: (_) => _setDailyGoal(g),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 每日打卡提醒：仅 Android 提供系统通知（iOS/鸿蒙暂不支持）
          if (Platform.isAndroid) ...[
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    value: _reminderOn,
                    onChanged: _toggleReminder,
                    title: const Text('每日打卡提醒'),
                    subtitle: const Text('到点用系统通知提醒你来打卡（App 关着也会提醒）'),
                    activeColor: const Color(0xFF2d5016),
                  ),
                  if (_reminderOn) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.schedule_outlined,
                          color: Color(0xFF2d5016)),
                      title: const Text('提醒时间'),
                      trailing: Text(_reminderTimeLabel,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      onTap: _pickReminderTime,
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('每组卡片数量'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('10 张'),
                        selected: _groupSize == 10,
                        onSelected: (_) => _setGroupSize(10),
                      ),
                      ChoiceChip(
                        label: const Text('20 张'),
                        selected: _groupSize == 20,
                        onSelected: (_) => _setGroupSize(20),
                      ),
                      ChoiceChip(
                        label: const Text('30 张'),
                        selected: _groupSize == 30,
                        onSelected: (_) => _setGroupSize(30),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _groupController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '自定义',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _applyCustomGroupSize(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _applyCustomGroupSize,
                        child: const Text('应用'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '当前每组 $_groupSize 张。修改后重新进入或刷新闪卡会按新组数推进。',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('选择题鸟名显示'),
                  const SizedBox(height: 4),
                  Text(
                    '选项里显示哪些名字，可多选，至少保留一项。',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('中文'),
                        selected: _quizNameModes.contains('cn'),
                        onSelected: (_) => _toggleQuizMode('cn'),
                      ),
                      FilterChip(
                        label: const Text('英文'),
                        selected: _quizNameModes.contains('en'),
                        onSelected: (_) => _toggleQuizMode('en'),
                      ),
                      FilterChip(
                        label: const Text('拉丁名'),
                        selected: _quizNameModes.contains('sci'),
                        onSelected: (_) => _toggleQuizMode('sci'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowUsCard extends StatelessWidget {
  const _FollowUsCard();

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.favorite_border, color: Color(0xFF2d5016)),
                SizedBox(width: 8),
                Text(
                  '关注我们',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.podcasts_outlined, size: 18),
                  label: const Text('小宇宙'),
                  onPressed: () => _open(
                    'https://www.xiaoyuzhoufm.com/podcast/6688a873ae8e21859ade308b',
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.bookmark_border, size: 18),
                  label: const Text('小红书'),
                  onPressed: () => _open(
                    'https://www.xiaohongshu.com/user/profile/6516e3ef00000000240167e9',
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.ondemand_video_outlined, size: 18),
                  label: const Text('B站'),
                  onPressed: () => _open(
                    'https://space.bilibili.com/3546850323860358',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const SelectableText(
              '有问题请联系：birderrrr@gmail.com\n微信 / v：hotpeaker',
              style: TextStyle(fontSize: 12.5, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

/// 管理员审批用户上传权限申请（/api/admin/token_requests）。
class _AdminTokenRequestsScreen extends StatefulWidget {
  final StorageService storage;
  const _AdminTokenRequestsScreen({required this.storage});

  @override
  State<_AdminTokenRequestsScreen> createState() =>
      _AdminTokenRequestsScreenState();
}

class _AdminTokenRequestsScreenState extends State<_AdminTokenRequestsScreen> {
  final AdminUploadService _service = AdminUploadService();
  bool _loading = true;
  String? _error;
  List<AdminTokenRequest> _items = const [];
  bool _showAll = false;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.storage.getAdminUploadToken();
    if (token.isEmpty) {
      setState(() {
        _loading = false;
        _error = '未配置管理员 Token';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.fetchTokenRequests(token: token);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _approve(AdminTokenRequest r) async {
    final controller = TextEditingController(text: r.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批准上传权限'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '给该用户的署名（可选）',
            hintText: '留空则自动生成',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('批准'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    await _act(
      r,
      () => _service.approveTokenRequest(
        clientId: r.clientId,
        name: name,
        token: widget.storage.getAdminUploadToken(),
      ),
      '已批准，已为该用户生成上传 Token',
    );
  }

  Future<void> _reject(AdminTokenRequest r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('拒绝申请？'),
        content: const Text('确定拒绝该用户的上传权限申请？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('拒绝'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _act(
      r,
      () => _service.rejectTokenRequest(
        clientId: r.clientId,
        token: widget.storage.getAdminUploadToken(),
      ),
      '已拒绝',
    );
  }

  Future<void> _act(
      AdminTokenRequest r, Future<void> Function() action, String okMsg) async {
    if (_busy.contains(r.clientId)) return;
    setState(() => _busy.add(r.clientId));
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(okMsg)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('操作失败：$e')));
    } finally {
      if (mounted) setState(() => _busy.remove(r.clientId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _items.where((r) => r.isPending).toList();
    final shown = _showAll ? _items : pending;
    return Scaffold(
      appBar: AppBar(
        title: Text('上传权限申请 (${pending.length})'),
        actions: [
          IconButton(
            tooltip: _showAll ? '只看待处理' : '查看全部',
            icon: Icon(_showAll ? Icons.filter_alt : Icons.filter_alt_outlined),
            onPressed: () => setState(() => _showAll = !_showAll),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(shown),
    );
  }

  Widget _buildBody(List<AdminTokenRequest> shown) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 36),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (shown.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_showAll ? '暂无任何申请记录。' : '没有待处理的申请。',
              style: const TextStyle(fontSize: 14)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: shown.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) => _buildItem(shown[i]),
      ),
    );
  }

  Widget _buildItem(AdminTokenRequest r) {
    final busy = _busy.contains(r.clientId);
    final theme = Theme.of(context);
    final statusLabel = r.status == 'approved'
        ? '已通过'
        : r.status == 'rejected'
            ? '已拒绝'
            : '待处理';
    final statusColor = r.status == 'approved'
        ? Colors.green
        : r.status == 'rejected'
            ? Colors.red
            : Colors.orange;
    final shortId =
        r.clientId.length > 8 ? r.clientId.substring(0, 8) : r.clientId;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.name.isEmpty ? '匿名申请号 $shortId' : r.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(statusLabel,
                    style: TextStyle(color: statusColor, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('申请号：${r.clientId}',
              style: TextStyle(fontSize: 12, color: theme.hintColor)),
          if (r.platform.isNotEmpty || r.appVersion.isNotEmpty)
            Text(
              '${r.platform}${r.appVersion.isNotEmpty ? ' · v${r.appVersion}' : ''}',
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
          if (r.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('留言：${r.note}'),
            ),
          if (r.status == 'rejected' && r.reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('拒绝理由：${r.reason}',
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          if (r.isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : () => _reject(r),
                    icon: const Icon(Icons.close, color: Colors.red, size: 18),
                    label:
                        const Text('拒绝', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : () => _approve(r),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('批准'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
