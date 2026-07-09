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
  final Set<String> _ratedImageFiles = {};

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
      var birds = <Map<String, dynamic>>[];
      var loadedRateQueue = false;
      if (_isAdmin && _token.isNotEmpty) {
        final queue = await _service.fetchRateQueue(token: _token);
        loadedRateQueue = true;
        birds = queue
            .where(_isIncompleteQueueItem)
            .map((b) => Map<String, dynamic>.from(b))
            .toList();
      }
      if (birds.isEmpty && !loadedRateQueue) {
        final raw = await rootBundle.loadString('assets/data/china_birds.json');
        final data = jsonDecode(raw) as List<dynamic>;
        birds = data
            .whereType<Map<String, dynamic>>()
            .where((b) => (b['sci'] as String? ?? '').trim().isNotEmpty)
            .map((b) => Map<String, dynamic>.from(b))
            .toList();
      }
      if (!mounted) return;
      setState(() {
        _birds = birds;
        _loading = false;
      });
      if (_birds.isNotEmpty) _loadMedia();
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
  String get _zh {
    final zh = (_current['zh'] as String? ?? '').trim();
    if (zh.isNotEmpty) return zh;
    return (_current['cn'] as String? ?? '').trim();
  }

  bool _isIncompleteQueueItem(Map<String, dynamic> item) {
    final speciesRated = item['species_rated'] == true;
    final imageCount = _asInt(item['image_count']);
    final imageRated = _asInt(item['image_rated']);
    return !speciesRated || imageRated < imageCount;
  }

  int _asInt(dynamic value) => value is num ? value.toInt() : 0;

  bool _isCurrentComplete() {
    if (_current['species_rated'] != true) return false;
    final imageCount = _asInt(_current['image_count']);
    final imageRated = _asInt(_current['image_rated']);
    return imageRated >= imageCount;
  }

  void _removeCurrentAndLoadNext() {
    if (_birds.isEmpty) return;
    setState(() {
      _birds = List<Map<String, dynamic>>.from(_birds)..removeAt(_idx);
      if (_idx >= _birds.length) {
        _idx = _birds.isEmpty ? 0 : _birds.length - 1;
      }
      _media = null;
      _speciesDiff = null;
      _imageDiff.clear();
      _ratedImageFiles.clear();
    });
    if (_birds.isNotEmpty) _loadMedia();
  }

  Future<void> _loadMedia() async {
    final targetSci = _sci;
    final target = _current;
    setState(() {
      _mediaLoading = true;
      _media = null;
      _speciesDiff = _asInt(target['species_difficulty']);
      _imageDiff.clear();
      _ratedImageFiles.clear();
    });
    try {
      final media = await ServerMediaService().fetchSpeciesMedia(targetSci);
      if (!mounted || targetSci != _sci) return;
      setState(() {
        _media = media;
        if (media?.speciesRated == true) {
          _speciesDiff = media!.speciesDifficulty;
          target['species_rated'] = true;
          target['species_difficulty'] = media.speciesDifficulty;
        }
        for (final img in media?.images ?? const []) {
          _imageDiff[img.file] = img.difficulty;
          if (img.hasDifficulty) _ratedImageFiles.add(img.file);
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
    final targetIdx = _idx;
    final targetSci = _sci;
    final targetZh = _zh;
    final target = _current;
    final wasRated = file.isNotEmpty && _ratedImageFiles.contains(file);
    try {
      final pending = await _service.submitRating(
        sci: targetSci,
        file: file,
        zh: targetZh,
        difficulty: difficulty,
        token: _token,
      );
      if (!mounted) return;
      final stillOnTarget = targetIdx == _idx && targetSci == _sci;
      if (!pending) {
        if (file.isEmpty) {
          target['species_rated'] = true;
          target['species_difficulty'] = difficulty;
        } else if (!wasRated) {
          if (stillOnTarget) _ratedImageFiles.add(file);
          target['image_rated'] = _asInt(target['image_rated']) + 1;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(pending ? '已提交，待管理员审核' : '已保存'),
        duration: const Duration(milliseconds: 900),
      ));
      if (!pending && stillOnTarget && _isCurrentComplete()) {
        _removeCurrentAndLoadNext();
      }
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
      bottomNavigationBar:
          _loading || _error != null || _birds.isEmpty ? null : _buildNav(),
    );
  }

  Widget _buildBody() {
    if (_birds.isEmpty) {
      return Center(
        child: Text(_isAdmin ? '当前没有待评级的鸟种。' : '名录为空。'),
      );
    }
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
            child:
                Text('该种暂无可评的图片。', style: TextStyle(color: Colors.grey[600])),
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
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _stars(current, (v) {
                        setState(() => _imageDiff[img.file] = v);
                        _submit(file: img.file, difficulty: v);
                      }),
                    ),
                    if (_isAdmin)
                      IconButton(
                        tooltip: '删除这张照片',
                        icon: const Icon(Icons.delete_outline),
                        color: Colors.red[700],
                        onPressed: () => _deleteImage(img),
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

  Future<void> _deleteImage(ServerImageMedia img) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除照片'),
        content: const Text('这张照片会从服务器物种页移入回收站，可在后台恢复。确定删除？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final targetIdx = _idx;
    final targetSci = _sci;
    final target = _current;
    final wasRated = _ratedImageFiles.contains(img.file);
    try {
      await _service.deleteMedia(
        sci: targetSci,
        file: img.file,
        kind: 'images',
        token: _token,
      );
      if (!mounted) return;
      final stillOnTarget = targetIdx == _idx && targetSci == _sci;
      target['image_count'] =
          (_asInt(target['image_count']) - 1).clamp(0, 1 << 30).toInt();
      if (wasRated) {
        target['image_rated'] =
            (_asInt(target['image_rated']) - 1).clamp(0, 1 << 30).toInt();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('照片已删除')),
      );
      if (stillOnTarget && _isCurrentComplete()) {
        _removeCurrentAndLoadNext();
      } else if (stillOnTarget) {
        _loadMedia();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
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
