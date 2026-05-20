import 'package:flutter/material.dart';

import '../services/admin_upload_service.dart';
import '../services/storage.dart';

class UploadReviewSection extends StatefulWidget {
  final StorageService storage;
  final VoidCallback onBack;

  const UploadReviewSection({
    super.key,
    required this.storage,
    required this.onBack,
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
      _showSnack('拒绝失败：$e');
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
              Icon(Icons.check_circle_outline,
                  color: Colors.green, size: 48),
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
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(10)),
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
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 12)),
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
                Text(
                  '${it.cn.isEmpty ? it.en : it.cn} · ${it.sci}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '上传者：${it.uploaderName.isEmpty ? it.uploaderId : it.uploaderName}'
                  ' · 署名：${it.contributor.isEmpty ? "未填" : it.contributor}'
                  ' · ${_timeAgo(it.uploadedAt)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : () => _reject(it),
                        icon: const Icon(Icons.close, color: Colors.red),
                        label: const Text('拒绝',
                            style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy ? null : () => _approve(it),
                        icon: const Icon(Icons.check),
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
