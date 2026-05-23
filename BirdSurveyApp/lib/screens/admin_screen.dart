import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/survey_provider.dart';
import '../services/sync_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  bool _loading = false;
  String? _error;
  List<CloudProject> _projects = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  SyncService _svc() {
    final prov = context.read<SurveyProvider>();
    return SyncService(serverUrl: prov.syncServerUrl, token: prov.syncToken);
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _svc().fetchProjects();
      if (mounted) {
        setState(() {
          _projects = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _createOrg() async {
    final name = await _promptText('新建机构', '机构名称');
    if (name == null || name.trim().isEmpty) return;
    try {
      final org = await _svc().createOrganization(name.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('机构已创建：${org['name']}')),
      );
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _createProject() async {
    final orgId = await _pickOrgId();
    if (orgId == null) return;
    final name = await _promptText('新建项目', '项目名称');
    if (name == null || name.trim().isEmpty) return;
    try {
      await _svc().createProject(name: name.trim(), organizationId: orgId);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('项目已创建')),
      );
    } catch (e) {
      _showError(e);
    }
  }

  Future<String?> _pickOrgId() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('选择机构'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '当前项目所属的机构 ID（从已有项目里复制，或粘贴新建机构返回的 id）',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            ..._uniqueOrgs().map(
              (e) => ListTile(
                dense: true,
                title: Text(e.$2.isEmpty ? '(无名机构)' : e.$2),
                subtitle: Text(e.$1, style: const TextStyle(fontSize: 10)),
                onTap: () => Navigator.pop(context, e.$1),
              ),
            ),
            const Divider(),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: '或手动粘贴机构 ID',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('使用粘贴的 ID'),
          ),
        ],
      ),
    );
  }

  List<(String, String)> _uniqueOrgs() {
    final map = <String, String>{};
    for (final p in _projects) {
      if (p.organizationId.isNotEmpty) {
        map[p.organizationId] = p.organizationName;
      }
    }
    return map.entries.map((e) => (e.key, e.value)).toList();
  }

  Future<String?> _promptText(String title, String label) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _createOrgAdminToken(CloudProject project) async {
    final label =
        await _promptText('生成机构管理员 Token', '名称（如：张老师）');
    if (label == null || label.trim().isEmpty) return;
    try {
      final result = await _svc().createAdminToken(
        role: 'org_admin',
        label: label.trim(),
        organizationId: project.organizationId,
      );
      _showTokenDialog('机构管理员 Token', result['token'] as String? ?? '');
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _generateInviteCode(CloudProject project) async {
    try {
      final result = await _svc().createInviteCode(projectId: project.id);
      _showCodeDialog(result['code'] as String? ?? '', project.name);
    } catch (e) {
      _showError(e);
    }
  }

  void _showTokenDialog(String title, String token) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              token,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 8),
            const Text(
              '⚠️ 这个 Token 只显示一次，请立刻复制保存。\n关闭后服务器不再返回原始值。',
              style: TextStyle(fontSize: 11, color: Colors.red),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('复制'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: token));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制到剪贴板')),
              );
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showCodeDialog(String code, String projectName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('「$projectName」邀请码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              code,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '发给志愿者，在 App 设置页填入即可加入项目。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('复制'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制')),
              );
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showError(Object e) {
    if (!mounted) return;
    final msg = e.toString().replaceFirst('Exception: ', '');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('失败：$msg'), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SurveyProvider>();
    final identity = prov.syncIdentity;
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理页'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: identity == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '请先在设置页验证管理员 Token。',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: Colors.green[50],
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '当前身份：${identity.role}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            identity.label.isEmpty ? '(无名)' : identity.label,
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (identity.organizationName.isNotEmpty)
                            Text('机构：${identity.organizationName}',
                                style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (identity.role == 'super_admin')
                    OutlinedButton.icon(
                      icon: const Icon(Icons.business),
                      label: const Text('新建机构'),
                      onPressed: _createOrg,
                    ),
                  if (identity.role == 'super_admin' ||
                      identity.role == 'org_admin')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('新建项目'),
                        onPressed: _createProject,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  const Divider(height: 32),
                  Text(
                    '项目列表（${_projects.length}）',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    Card(
                      color: Colors.red[50],
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('加载失败：$_error',
                            style: const TextStyle(color: Colors.red)),
                      ),
                    )
                  else if (_projects.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('暂无项目，点击上方"新建项目"',
                          style: TextStyle(color: Colors.grey)),
                    )
                  else
                    ..._projects.map(
                      (p) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              if (p.organizationName.isNotEmpty)
                                Text('机构：${p.organizationName}',
                                    style: const TextStyle(fontSize: 12)),
                              SelectableText(
                                'ID: ${p.id}',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.grey),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.qr_code, size: 16),
                                    label: const Text('生成邀请码'),
                                    onPressed: () => _generateInviteCode(p),
                                  ),
                                  if (identity.role == 'super_admin')
                                    OutlinedButton.icon(
                                      icon: const Icon(
                                          Icons.admin_panel_settings,
                                          size: 16),
                                      label: const Text('生成管理员Token'),
                                      onPressed: () =>
                                          _createOrgAdminToken(p),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
