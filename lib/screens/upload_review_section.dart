import 'package:flutter/material.dart';

import '../services/admin_upload_service.dart';
import '../services/storage.dart';

class UploadReviewSection extends StatefulWidget {
  final StorageService storage;
  final VoidCallback onBack;
  final VoidCallback onOpenHistory;

  const UploadReviewSection({
    super.key,
    required this.storage,
    required this.onBack,
    required this.onOpenHistory,
  });

  @override
  State<UploadReviewSection> createState() => _UploadReviewSectionState();
}

class _UploadReviewSectionState extends State<UploadReviewSection> {
  final AdminUploadService _service = AdminUploadService();
  bool _loading = true;
  List<PendingMediaItem> _items = [];
  String? _error;
  final Set<String> _busy = {}; // file paths in progress

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _itemKey(PendingMediaItem it) => '${it.sci}__${it.file}';

  Future<void> _load() async {
    final token = widget.storage.getAdminUploadToken();
    if (token.isEmpty) {
      setState(() {
        _loading = false;
        _error = '未配置上传 Token';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.fetchPending(token: token);
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

  Future<void> _approve(PendingMediaItem it) async {
    final key = _itemKey(it);
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    try {
      await _service.approve(
        sci: it.sci,
        file: it.file,
        token: widget.storage.getAdminUploadToken(),
      );
      if (!mounted) return;
      setState(() => _items.removeWhere((x) => _itemKey(x) == key));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已通过：${it.cn.isEmpty ? it.sci : it.cn}')),
      );
    } catch (e) {
      _showSnack('通过失败：$e');
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _reject(PendingMediaItem it) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('拒绝并删除？'),
        content: Text('文件「${it.file}」将从服务器删除，不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final key = _itemKey(it);
    setState(() => _busy.add(key));
    try {
      await _service.reject(
        sci: it.sci,
        file: it.file,
        token: widget.storage.getAdminUploadToken(),
      );
      if (!mounted) return;
      setState(() => _items.removeWhere((x) => _itemKey(x) == key));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已拒绝并删除')),
      );
    } catch (e) {
      final message = '$e';
      if (message.contains('Pending entry not found')) {
        if (!mounted) return;
        setState(() => _items.removeWhere((x) => _itemKey(x) == key));
        _showSnack('这条记录已经不在待审核队列，已自动刷新列表。');
        return;
      }
      _showSnack('拒绝失败：$e');
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _flagIssue(PendingMediaItem it) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('记录纠错'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${it.cn.isEmpty ? it.en : it.cn} · ${it.sci}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: '例：物种识别错误（实际是XX）/ 图片倒置 / 重复上传 …',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('提交')),
        ],
      ),
    );
    final msg = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || msg.isEmpty) return;
    try {
      final clientId = await widget.storage.ensureFeedbackClientId();
      await _service.submitFeedback(
        token: widget.storage.getAdminUploadToken(),
        clientId: clientId,
        message: msg,
        page: '审核纠错（${it.kind == "audio" ? "音频" : "图片"}：${it.file}）',
        speciesCn: it.cn,
        speciesSci: it.sci,
        context: {
          'question_type': 'upload_review',
          'question': '审核队列素材纠错',
          'correct_answer': [
            if (it.cn.trim().isNotEmpty) it.cn.trim(),
            if (it.en.trim().isNotEmpty) it.en.trim(),
            it.sci.trim(),
          ].where((part) => part.isNotEmpty).join(' · '),
          'media_kind': it.kind == 'audio' ? 'audio' : 'image',
          'media_file': it.file,
          'media_url': it.url,
        },
      );
      if (!mounted) return;
      _showSnack('已记录纠错');
    } catch (e) {
      _showSnack('记录失败：$e');
    }
  }

  String _fmtDate(int ts) {
    if (ts <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _timeAgo(int ts) {
    if (ts <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: Text('待审核 (${_items.length})'),
        actions: [
          IconButton(
            tooltip: '历史',
            icon: const Icon(Icons.history),
            onPressed: widget.onOpenHistory,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
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
    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green, size: 48),
              SizedBox(height: 10),
              Text('当前没有待审核的内容', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) => _buildItem(_items[i]),
      ),
    );
  }

  Widget _buildItem(PendingMediaItem it) {
    final busy = _busy.contains(_itemKey(it));
    final isAudio = it.kind == 'audio';
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: SizedBox(
              height: 200,
              width: double.infinity,
              child: isAudio
                  ? Container(
                      color: Colors.grey[200],
                      alignment: Alignment.center,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.audiotrack, size: 48, color: Colors.grey),
                          SizedBox(height: 6),
                          Text('音频（点开始播放，暂不支持在线试听）',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    )
                  : Image.network(
                      it.url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[300],
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image,
                            color: Colors.grey, size: 36),
                      ),
                      loadingBuilder: (ctx, child, ev) {
                        if (ev == null) return child;
                        return Container(
                          color: Colors.grey[100],
                          alignment: Alignment.center,
                          child: const CircularProgressIndicator(),
                        );
                      },
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                    children: [
                      TextSpan(text: '${it.cn.isEmpty ? it.en : it.cn} · '),
                      TextSpan(
                        text: it.sci,
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '上传者：${it.uploaderName.isEmpty ? it.uploaderId : it.uploaderName}'
                  '${it.uploaderRole.isEmpty ? "" : "（${it.uploaderRole == "admin" ? "管理员" : "内测"}）"}'
                  ' · 署名：${it.contributor.isEmpty ? "未填" : it.contributor}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
                const SizedBox(height: 2),
                Text(
                  '时间：${_fmtDate(it.uploadedAt)} · ${_timeAgo(it.uploadedAt)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
                if (it.suggestedDifficulty > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '建议难度：${"⭐" * it.suggestedDifficulty}（${it.suggestedDifficulty}/5）',
                    style: TextStyle(fontSize: 12, color: Colors.amber[800]),
                  ),
                ],
                if (it.location.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '地点：${it.location}',
                      style: TextStyle(fontSize: 12, color: Colors.orange[900]),
                    ),
                  ),
                ],
                if (it.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '描述：${it.description}',
                      style: TextStyle(fontSize: 12, color: Colors.blue[900]),
                    ),
                  ),
                ],
                if (it.features.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '识别特征：${it.features}',
                      style: TextStyle(fontSize: 12, color: Colors.green[900]),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      tooltip: '记录纠错',
                      onPressed: busy ? null : () => _flagIssue(it),
                      icon: const Icon(Icons.report_problem_outlined,
                          color: Colors.orange),
                    ),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : () => _reject(it),
                        icon: const Icon(Icons.close,
                            color: Colors.red, size: 18),
                        label: const Text('拒绝',
                            style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy ? null : () => _approve(it),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('通过并置顶'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
