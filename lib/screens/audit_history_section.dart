import 'dart:async';

import 'package:flutter/material.dart';

import '../services/admin_upload_service.dart';
import '../services/pinyin.dart';
import '../services/storage.dart';

class AuditHistorySection extends StatefulWidget {
  final StorageService storage;
  final VoidCallback onBack;

  const AuditHistorySection({
    super.key,
    required this.storage,
    required this.onBack,
  });

  @override
  State<AuditHistorySection> createState() => _AuditHistorySectionState();
}

class _AuditHistorySectionState extends State<AuditHistorySection> {
  final AdminUploadService _service = AdminUploadService();
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  bool _loading = true;
  String? _error;
  List<HistoryItem> _items = [];
  String _q = '';
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  String _key(HistoryItem it) => '${it.sci}__${it.file}';

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
      final list = await _service.fetchHistory(token: token, limit: 500);
      if (!mounted) return;
      setState(() {
        _items = list;
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

  List<HistoryItem> get _filtered {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return _items;
    final isPinyinQuery = q.length >= 2 && RegExp(r'^[a-z]+$').hasMatch(q);
    return _items.where((it) {
      if (it.cn.contains(_q) ||
          it.sci.toLowerCase().contains(q) ||
          it.en.toLowerCase().contains(q) ||
          it.contributor.toLowerCase().contains(q) ||
          it.uploaderId.toLowerCase().contains(q) ||
          it.uploaderName.toLowerCase().contains(q)) {
        return true;
      }
      if (isPinyinQuery && Pinyin.initials(it.cn).contains(q)) return true;
      return false;
    }).toList();
  }

  Future<void> _revoke(HistoryItem it) async {
    final isAudio = it.kind == 'audio';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除这${isAudio ? "段音频" : "张照片"}？'),
        content: Text(
            '将从服务器删除「${it.cn.isEmpty ? it.sci : it.cn}」的「${it.file}」，不可恢复。'),
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
    final key = _key(it);
    setState(() => _busy.add(key));
    try {
      await _service.deleteServerMedia(
        sci: it.sci,
        kind: it.kind == 'audio' ? 'audio' : 'images',
        file: it.file,
        token: widget.storage.getAdminUploadToken(),
      );
      if (!mounted) return;
      setState(() => _items.removeWhere((x) => _key(x) == key));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已删除')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  String _timeAgo(int ts) {
    if (ts <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final shown = _filtered;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: Text('审核历史 (${shown.length}/${_items.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '搜索 中文 / 拉丁 / 拼音(bjw) / 上传者',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _q = '');
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onChanged: (v) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 200), () {
                  if (mounted) setState(() => _q = v);
                });
              },
            ),
          ),
        ),
      ),
      body: _buildBody(shown),
    );
  }

  Widget _buildBody(List<HistoryItem> shown) {
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
          child: Text(
            _q.isEmpty ? '暂无已审核的用户上传' : '没有匹配项',
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      itemCount: shown.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) => _buildTile(shown[i]),
    );
  }

  Widget _buildTile(HistoryItem it) {
    final busy = _busy.contains(_key(it));
    final isAudio = it.kind == 'audio';
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(10),
        color: Colors.white,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(10),
              bottomLeft: Radius.circular(10),
            ),
            child: SizedBox(
              width: 84,
              height: 84,
              child: isAudio
                  ? Container(
                      color: Colors.grey[200],
                      alignment: Alignment.center,
                      child: const Icon(Icons.audiotrack,
                          size: 28, color: Colors.grey),
                    )
                  : Image.network(
                      it.url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[300],
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image,
                            color: Colors.grey, size: 24),
                      ),
                    ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                      children: [
                        TextSpan(text: '${it.cn.isEmpty ? it.en : it.cn} · '),
                        TextSpan(
                            text: it.sci,
                            style: const TextStyle(
                                fontStyle: FontStyle.italic)),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${it.uploaderName.isEmpty ? it.uploaderId : it.uploaderName}'
                    ' · ${it.contributor.isEmpty ? "未署名" : it.contributor}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (it.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(it.description,
                        style:
                            TextStyle(fontSize: 11, color: Colors.blue[800]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _timeAgo(it.approvedAt > 0
                        ? it.approvedAt
                        : it.uploadedAt),
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: busy ? null : () => _revoke(it),
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
}
