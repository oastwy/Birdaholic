import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/admin_upload_service.dart';
import '../services/storage.dart';
import '../services/pack_manager.dart';
import 'about_screen.dart';
import 'pack_manage_screen.dart';

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
  late final TextEditingController _groupController;
  late int _groupSize;

  @override
  void initState() {
    super.initState();
    _groupSize = widget.storage.flashcardGroupSize;
    _groupController = TextEditingController(text: '$_groupSize');
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
                labelText: 'Xeno-Canto API Key',
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
                hintText: '管理员 / 内测用户填写各自 Token，保存后自动识别身份',
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
            await widget.storage.setUserIdentity(role: who.role, name: who.name);
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

  Future<void> _openFeedbackJournal() async {
    final entries = widget.storage.getFeedbackJournal();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '纠错日记',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (entries.isNotEmpty)
                      TextButton(
                        onPressed: () async {
                          final text = entries.map((item) {
                            final species = item.speciesCn.isNotEmpty
                                ? '${item.speciesCn} (${item.speciesSci})'
                                : item.speciesSci;
                            return '[${item.createdAt.substring(0, 16).replaceFirst('T', ' ')}] '
                                '${item.page}${species.isNotEmpty ? ' · $species' : ''}\n${item.message}';
                          }).join('\n\n');
                          await Clipboard.setData(ClipboardData(text: text));
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('已复制纠错日记')),
                          );
                        },
                        child: const Text('复制'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (entries.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        '还没有记录。\n在闪卡页点纠错按钮即可保存。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = entries[index];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.speciesCn.isNotEmpty
                                      ? '${item.speciesCn} · ${item.speciesSci}'
                                      : item.page,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.createdAt
                                      .substring(0, 16)
                                      .replaceFirst('T', ' '),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(item.message),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.style_outlined, color: Color(0xFF2d5016)),
                    SizedBox(width: 8),
                    Text(
                      '闪卡设置',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
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
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
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
                              ? '内测用户（${widget.storage.getUserName()}）'
                              : '已配置',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _editApiSettings,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.menu_book_outlined,
                  color: Color(0xFF2d5016),
                ),
                title: const Text('纠错日记'),
                subtitle:
                    Text('${widget.storage.getFeedbackJournal().length} 条记录'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openFeedbackJournal,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const AboutScreen(embedded: true),
      ],
    );
  }
}
