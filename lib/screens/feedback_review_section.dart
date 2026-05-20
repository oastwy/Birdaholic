import 'package:flutter/material.dart';

import '../services/admin_upload_service.dart';
import '../services/storage.dart';

class FeedbackReviewSection extends StatefulWidget {
  final StorageService storage;
  final VoidCallback onBack;

  const FeedbackReviewSection({
    super.key,
    required this.storage,
    required this.onBack,
  });

  @override
  State<FeedbackReviewSection> createState() => _FeedbackReviewSectionState();
}

class _FeedbackReviewSectionState extends State<FeedbackReviewSection> {
  final AdminUploadService _service = AdminUploadService();
  bool _loading = true;
  String? _error;
  List<AdminFeedbackEntry> _items = [];
  bool _showResolved = false;
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
      final items = await _service.fetchAdminFeedback(token: token);
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

  Future<void> _resolve(AdminFeedbackEntry e) async {
    setState(() => _busy.add(e.id));
    try {
      await _service.resolveFeedback(
        token: widget.storage.getAdminUploadToken(),
        id: e.id,
      );
      if (!mounted) return;
      setState(() {
        final idx = _items.indexWhere((x) => x.id == e.id);
        if (idx >= 0) {
          _items[idx] = AdminFeedbackEntry(
            id: e.id,
            uploaderId: e.uploaderId,
            uploaderName: e.uploaderName,
            role: e.role,
            message: e.message,
            page: e.page,
            speciesCn: e.speciesCn,
            speciesSci: e.speciesSci,
            createdAt: e.createdAt,
            status: 'resolved',
          );
        }
      });
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$err')));
    } finally {
      if (mounted) setState(() => _busy.remove(e.id));
    }
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
    final visible = _showResolved
        ? _items
        : _items.where((e) => e.status != 'resolved').toList();
    final openCount = _items.where((e) => e.status != 'resolved').length;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: Text('纠错审核（$openCount）'),
        actions: [
          IconButton(
            tooltip: _showResolved ? '隐藏已处理' : '显示已处理',
            icon: Icon(_showResolved
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined),
            onPressed: () => setState(() => _showResolved = !_showResolved),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(visible),
    );
  }

  Widget _buildBody(List<AdminFeedbackEntry> visible) {
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
    if (visible.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline,
                  color: Colors.green, size: 48),
              SizedBox(height: 10),
              Text('当前没有待处理的反馈', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: visible.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) => _buildItem(visible[i]),
      ),
    );
  }

  Widget _buildItem(AdminFeedbackEntry e) {
    final busy = _busy.contains(e.id);
    final isResolved = e.status == 'resolved';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(10),
        color: isResolved ? Colors.grey[100] : Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isResolved
                    ? Icons.check_circle
                    : Icons.report_problem_outlined,
                size: 18,
                color: isResolved ? Colors.green : Colors.orange[700],
              ),
              const SizedBox(width: 6),
              Text(
                e.uploaderName.isEmpty ? e.uploaderId : e.uploaderName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: e.role == 'admin'
                      ? Colors.green[100]
                      : Colors.blue[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  e.role == 'admin' ? '管理员' : '内测',
                  style: TextStyle(
                    fontSize: 10,
                    color: e.role == 'admin'
                        ? Colors.green[800]
                        : Colors.blue[800],
                  ),
                ),
              ),
              const Spacer(),
              Text(_timeAgo(e.createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ],
          ),
          const SizedBox(height: 8),
          Text(e.message,
              style: TextStyle(
                  fontSize: 14,
                  color: isResolved ? Colors.grey[600] : Colors.black87,
                  decoration:
                      isResolved ? TextDecoration.lineThrough : null)),
          if (e.speciesCn.isNotEmpty || e.page.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                if (e.page.isNotEmpty)
                  _chipTag(Icons.map_outlined, e.page),
                if (e.speciesCn.isNotEmpty)
                  _chipTag(Icons.flutter_dash_outlined,
                      '${e.speciesCn} · ${e.speciesSci}'),
              ],
            ),
          ],
          if (!isResolved) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: busy ? null : () => _resolve(e),
                icon: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.done, size: 16),
                label: const Text('标记已处理'),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chipTag(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey[700]),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(fontSize: 11, color: Colors.grey[700])),
        ],
      ),
    );
  }
}
