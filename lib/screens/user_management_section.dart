import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/admin_upload_service.dart';
import '../services/storage.dart';

class UserManagementSection extends StatefulWidget {
  final StorageService storage;
  final VoidCallback onBack;

  const UserManagementSection({
    super.key,
    required this.storage,
    required this.onBack,
  });

  @override
  State<UserManagementSection> createState() => _UserManagementSectionState();
}

class _UserManagementSectionState extends State<UserManagementSection> {
  final AdminUploadService _service = AdminUploadService();
  bool _loading = true;
  String? _error;
  List<UploadUser> _users = [];
  final Set<String> _busy = {}; // tokens being deleted

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
      final list = await _service.listUsers(token: token);
      if (!mounted) return;
      setState(() {
        _users = list;
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

  Future<void> _createUser() async {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final tokenCtrl = TextEditingController();
    String role = 'beta';
    UploadUser? created;
    bool submitting = false;
    final result = await showDialog<UploadUser?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('新增上传用户'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '昵称 *',
                    hintText: '显示给管理员看的名字',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: idCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ID（可选，会自动生成）',
                    hintText: '英文/数字，全局唯一',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(
                    labelText: '角色',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'beta', child: Text('内测用户（需审核）')),
                    DropdownMenuItem(value: 'admin', child: Text('管理员（直接生效）')),
                  ],
                  onChanged: (v) => setLocal(() => role = v ?? 'beta'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tokenCtrl,
                  decoration: const InputDecoration(
                    labelText: '自定义 Token（可选）',
                    hintText: '留空则服务器随机生成',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: submitting ? null : () => Navigator.pop(ctx, null),
                child: const Text('取消')),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) return;
                      setLocal(() => submitting = true);
                      try {
                        created = await _service.createUser(
                          token: widget.storage.getAdminUploadToken(),
                          name: name,
                          role: role,
                          userId: idCtrl.text.trim(),
                          customToken: tokenCtrl.text.trim(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx, created);
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('$e')),
                          );
                          setLocal(() => submitting = false);
                        }
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('创建'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    idCtrl.dispose();
    tokenCtrl.dispose();
    if (result != null && mounted) {
      await _showTokenDialog(result);
      _load();
    }
  }

  Future<void> _showTokenDialog(UploadUser user) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('已创建：${user.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${user.id}',
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 8),
            const Text('Token（请发送给该用户，不会再次显示）：',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            SelectableText(
              user.token,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                backgroundColor: Color(0xFFF1F4EC),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: user.token));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Token 已复制')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('复制'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteUser(UploadUser user) async {
    if (user.isSelf) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤销该用户？'),
        content: Text(
            '撤销后 ${user.name} 的 Token 将立即失效。已上传的媒体不会删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy.add(user.token));
    try {
      await _service.deleteUser(
        token: widget.storage.getAdminUploadToken(),
        targetToken: user.token,
      );
      if (!mounted) return;
      setState(() => _users.removeWhere((u) => u.token == user.token));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy.remove(user.token));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: const Text('上传用户管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: _loading || _error != null
          ? null
          : FloatingActionButton.extended(
              onPressed: _createUser,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('新增'),
            ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
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
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
        itemCount: _users.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) => _buildUserTile(_users[i]),
      ),
    );
  }

  Widget _buildUserTile(UploadUser u) {
    final busy = _busy.contains(u.token);
    final isAdmin = u.isAdmin;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(10),
        color: u.isSelf ? const Color(0xFFF1F4EC) : Colors.white,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: isAdmin ? Colors.green[700] : Colors.blue[400],
            radius: 18,
            child: Icon(
              isAdmin ? Icons.shield_outlined : Icons.person_outline,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(u.name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isAdmin ? Colors.green[100] : Colors.blue[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isAdmin ? '管理员' : '内测',
                        style: TextStyle(
                          fontSize: 10,
                          color:
                              isAdmin ? Colors.green[800] : Colors.blue[800],
                        ),
                      ),
                    ),
                    if (u.isSelf) ...[
                      const SizedBox(width: 6),
                      const Text('（我）',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text('ID: ${u.id}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Token: ${_maskToken(u.token)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: '复制完整 Token',
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: u.token));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Token 已复制')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!u.isSelf)
            IconButton(
              tooltip: '撤销',
              onPressed: busy ? null : () => _deleteUser(u),
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_outline, color: Colors.red),
            ),
        ],
      ),
    );
  }

  String _maskToken(String t) {
    if (t.length <= 12) return t;
    return '${t.substring(0, 6)}…${t.substring(t.length - 4)}';
  }
}
