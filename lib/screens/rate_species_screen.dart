import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/admin_upload_service.dart';
import '../services/server_media_service.dart';
import '../services/storage.dart';

/// 逐种评级：依次给中国鸟（~1490 种）的物种难度 + 每张图的质量/难度打分（1-5）。
/// 管理员评分直接生效；内测用户评分进待审队列，由管理员审核。
class RateSpeciesScreen extends StatefulWidget {
  final StorageService storage;
  const RateSpeciesScreen({super.key, required this.storage});

  @override
  State<RateSpeciesScreen> createState() => _RateSpeciesScreenState();
}

class _RateSpeciesScreenState extends State<RateSpeciesScreen> {
  static const _green = Color(0xFF2d5016);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _birds = const [];
  int _idx = 0;

  bool _mediaLoading = false;
  ServerSpeciesMedia? _media;
  int? _speciesDiff;
  final Map<String, int> _imageDiff = {};

  final _service = AdminUploadService();

  bool get _isAdmin => widget.storage.isAdminMode;
  String get _token => widget.storage.getAdminUploadToken();

  @override
  void initState() {
    super.initState();
    _loadBirds();
  }

  Future<void> _loadBirds() async {
    try {
      final raw = await rootBundle.loadString('assets/data/china_birds.json');
      final data = jsonDecode(raw) as List<dynamic>;
      final birds = data
          .whereType<Map<String, dynamic>>()
          .where((b) => (b['sci'] as String? ?? '').trim().isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _birds = birds;
        _loading = false;
      });
      _loadMedia();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '名录加载失败：$e';
      });
    }
  }

  Map<String, dynamic> get _current => _birds[_idx];
  String get _sci => (_current['sci'] as String? ?? '').trim();
  String get _zh => (_current['zh'] as String? ?? '').trim();

  Future<void> _loadMedia() async {
    setState(() {
      _mediaLoading = true;
      _media = null;
      _speciesDiff = null;
      _imageDiff.clear();
    });
    try {
      final media = await ServerMediaService().fetchSpeciesMedia(_sci);
      if (!mounted) return;
      setState(() {
        _media = media;
        for (final img in media?.images ?? const []) {
          _imageDiff[img.file] = img.difficulty;
        }
        _mediaLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _mediaLoading = false);
    }
  }

  void _go(int delta) {
    final next = (_idx + delta).clamp(0, _birds.length - 1);
    if (next == _idx) return;
    setState(() => _idx = next);
    _loadMedia();
  }

  Future<void> _jump() async {
    final controller = TextEditingController();
    final q = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转到鸟种'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入中文名或学名'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('跳转')),
        ],
      ),
    );
    if (q == null || q.isEmpty) return;
    final lower = q.toLowerCase();
    final found = _birds.indexWhere((b) =>
        (b['zh'] as String? ?? '').contains(q) ||
        (b['sci'] as String? ?? '').toLowerCase().contains(lower) ||
        (b['en'] as String? ?? '').toLowerCase().contains(lower));
    if (found < 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没找到匹配的鸟种')));
      return;
    }
    setState(() => _idx = found);
    _loadMedia();
  }

  Future<void> _submit({String file = '', required int difficulty}) async {
    if (_token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置里配置上传身份（Token）')),
      );
      return;
    }
    try {
      final pending = await _service.submitRating(
        sci: _sci,
        file: file,
        zh: _zh,
        difficulty: difficulty,
        token: _token,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(pending ? '已提交，待管理员审核' : '已保存'),
        duration: const Duration(milliseconds: 900),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('逐种评级'),
        actions: [
          IconButton(
            tooltip: '跳转',
            onPressed: _loading ? null : _jump,
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _buildBody(),
      bottomNavigationBar: _loading || _error != null ? null : _buildNav(),
    );
  }

  Widget _buildBody() {
    final en = (_current['en'] as String? ?? '').trim();
    final order = (_current['order'] as String? ?? '').trim();
    final family = (_current['family'] as String? ?? '').trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (!_isAdmin)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '你是内测用户：评分会提交给管理员审核后才生效。',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
        Text('$_zh ${en.isEmpty ? '' : '· $en'}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(_sci,
            style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: Colors.grey[600])),
        if (order.isNotEmpty || family.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text([order, family].where((s) => s.isNotEmpty).join(' · '),
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ],
        const SizedBox(height: 16),
        const Text('物种难度', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        _stars(_speciesDiff ?? 0, (v) {
          setState(() => _speciesDiff = v);
          _submit(difficulty: v);
        }),
        const SizedBox(height: 18),
        Row(
          children: [
            const Text('图片质量 / 难度',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            if (_mediaLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (!_mediaLoading && (_media == null || _media!.images.isEmpty))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('该种暂无可评的图片。',
                style: TextStyle(color: Colors.grey[600])),
          )
        else
          ...(_media?.images ?? const []).map(_imageCard),
      ],
    );
  }

  Widget _imageCard(ServerImageMedia img) {
    final current = _imageDiff[img.file] ?? img.difficulty;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 180,
            width: double.infinity,
            child: Image.network(
              img.url,
              fit: BoxFit.cover,
              loadingBuilder: (c, w, p) => p == null
                  ? w
                  : const Center(child: CircularProgressIndicator()),
              errorBuilder: (_, __, ___) => const Center(child: Text('图片加载失败')),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (img.contributor.isNotEmpty)
                  Text('@${img.contributor}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[600])),
                const SizedBox(height: 4),
                _stars(current, (v) {
                  setState(() => _imageDiff[img.file] = v);
                  _submit(file: img.file, difficulty: v);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stars(int current, ValueChanged<int> onTap) {
    return Row(
      children: List.generate(5, (i) {
        final filled = i < current;
        return GestureDetector(
          onTap: () => onTap(i + 1),
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 34,
              color: filled ? Colors.amber[700] : Colors.grey[400],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildNav() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _idx > 0 ? () => _go(-1) : null,
                icon: const Icon(Icons.chevron_left),
                label: const Text('上一种'),
              ),
            ),
            const SizedBox(width: 12),
            Text('${_idx + 1} / ${_birds.length}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _idx < _birds.length - 1 ? () => _go(1) : null,
                style: FilledButton.styleFrom(backgroundColor: _green),
                icon: const Icon(Icons.chevron_right),
                label: const Text('下一种'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
