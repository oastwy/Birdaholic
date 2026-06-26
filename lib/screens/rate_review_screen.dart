import 'package:flutter/material.dart';

import '../services/admin_upload_service.dart';
import '../services/server_media_service.dart';
import '../services/storage.dart';

/// 管理员审核内测用户提交的逐种评级：通过则写入 manifest，拒绝则丢弃。
class RateReviewScreen extends StatefulWidget {
  final StorageService storage;
  const RateReviewScreen({super.key, required this.storage});

  @override
  State<RateReviewScreen> createState() => _RateReviewScreenState();
}

class _RateReviewScreenState extends State<RateReviewScreen> {
  final _service = AdminUploadService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  String get _token => widget.storage.getAdminUploadToken();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.fetchPendingRatings(token: _token);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _resolve(Map<String, dynamic> rec, bool approve) async {
    final id = (rec['id'] as String? ?? '').trim();
    if (id.isEmpty) return;
    try {
      await _service.resolveRating(id: id, approve: approve, token: _token);
      if (!mounted) return;
      setState(() => _items = _items.where((r) => r['id'] != id).toList());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approve ? '已通过并写入' : '已拒绝'),
        duration: const Duration(milliseconds: 800),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  String _imageUrl(String sci, String file) {
    final key = sci.trim().split(RegExp(r'\s+')).join('_');
    return '${ServerMediaService.defaultBaseUrl}/species/$key/$file';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('评级审核${_items.isEmpty ? '' : ' (${_items.length})'}'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? Center(
                      child: Text('暂无待审评级',
                          style: TextStyle(color: Colors.grey[600])))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      itemCount: _items.length,
                      itemBuilder: (context, i) => _card(_items[i]),
                    ),
    );
  }

  Widget _card(Map<String, dynamic> rec) {
    final sci = (rec['sci'] as String? ?? '').trim();
    final zh = (rec['zh'] as String? ?? '').trim();
    final file = (rec['file'] as String? ?? '').trim();
    final kind = (rec['kind'] as String? ?? 'species');
    final diff = (rec['difficulty'] as num?)?.toInt() ?? 0;
    final contributor = (rec['contributor'] as String? ?? '').trim();
    final isImage = kind == 'image' && file.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(zh.isEmpty ? sci : zh, // 物种名
                style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(sci,
                style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[600])),
            const SizedBox(height: 8),
            if (isImage) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 150,
                  width: double.infinity,
                  child: Image.network(
                    _imageUrl(sci, file),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Center(child: Text('图片加载失败')),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Text(isImage ? '图片质量/难度：' : '物种难度：',
                    style: const TextStyle(fontSize: 13)),
                ...List.generate(
                  5,
                  (i) => Icon(
                    i < diff
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 18,
                    color: i < diff ? Colors.amber[700] : Colors.grey[400],
                  ),
                ),
              ],
            ),
            if (contributor.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('提交人：$contributor',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _resolve(rec, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('拒绝'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _resolve(rec, true),
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2d7d32)),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('通过'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
