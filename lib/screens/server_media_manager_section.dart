import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../services/admin_upload_service.dart';
import '../services/pinyin.dart';
import '../services/server_media_service.dart';
import '../services/storage.dart';
import '../widgets/audio_player_widget.dart';

class _BirdSearchItem {
  final String sci;
  final String cn;
  final String en;

  const _BirdSearchItem({
    required this.sci,
    required this.cn,
    required this.en,
  });
}

class ServerMediaManagerSection extends StatefulWidget {
  final StorageService storage;
  final VoidCallback onBack;

  const ServerMediaManagerSection({
    super.key,
    required this.storage,
    required this.onBack,
  });

  @override
  State<ServerMediaManagerSection> createState() =>
      _ServerMediaManagerSectionState();
}

class _ServerMediaManagerSectionState extends State<ServerMediaManagerSection> {
  final _queryCtrl = TextEditingController();
  final _adminService = AdminUploadService();
  final _mediaService = ServerMediaService();
  List<_BirdSearchItem> _allBirds = const [];
  List<_BirdSearchItem> _results = const [];
  _BirdSearchItem? _selected;
  ServerSpeciesMedia? _media;
  bool _loading = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _loadBirds();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBirds() async {
    try {
      final raw = await rootBundle.loadString('assets/data/world_birds.json');
      final list = jsonDecode(raw) as List<dynamic>;
      final birds = list
          .whereType<Map<String, dynamic>>()
          .map((m) {
            return _BirdSearchItem(
              sci: (m['sci'] as String? ?? '').trim(),
              cn: ((m['zh'] as String?) ?? (m['cn'] as String?) ?? '').trim(),
              en: (m['en'] as String? ?? '').trim(),
            );
          })
          .where((b) => b.sci.isNotEmpty)
          .toList();
      if (mounted) setState(() => _allBirds = birds);
    } catch (e) {
      if (mounted) setState(() => _message = '名录加载失败：$e');
    }
  }

  void _search(String value) {
    final q = value.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _results = const []);
      return;
    }
    final matches = <_BirdSearchItem>[];
    for (final bird in _allBirds) {
      if (bird.cn.contains(q) ||
          bird.en.toLowerCase().contains(q) ||
          bird.sci.toLowerCase().contains(q) ||
          Pinyin.initials(bird.cn).contains(q)) {
        matches.add(bird);
        if (matches.length >= 16) break;
      }
    }
    setState(() => _results = matches);
  }

  Future<void> _select(_BirdSearchItem bird) async {
    setState(() {
      _selected = bird;
      _queryCtrl.text = _birdLabel(bird);
      _results = const [];
      _media = null;
      _message = '';
    });
    await _refresh();
  }

  String _birdLabel(_BirdSearchItem bird) =>
      '${bird.cn.isEmpty ? bird.en : bird.cn} · ${bird.sci}';

  void _clearSelection() {
    setState(() {
      _queryCtrl.clear();
      _results = const [];
      _selected = null;
      _media = null;
      _message = '';
    });
  }

  Future<void> _refresh() async {
    final bird = _selected;
    if (bird == null) return;
    setState(() => _loading = true);
    try {
      final media = await _mediaService.fetchSpeciesMedia(bird.sci);
      if (!mounted) return;
      setState(() {
        _media = media;
        _message = media == null ? '服务器没有找到这个物种的媒体。' : '';
      });
    } catch (e) {
      if (mounted) setState(() => _message = '加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete({
    required String kind,
    required String file,
    required String title,
  }) async {
    final bird = _selected;
    if (bird == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除服务器媒体？'),
        content: Text('将删除 $title，并自动更新 manifest。这个操作不能从 App 内撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final token = widget.storage.getAdminUploadToken();
    setState(() => _loading = true);
    try {
      await _adminService.deleteServerMedia(
        sci: bird.sci,
        kind: kind,
        file: file,
        token: token,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已删除并刷新服务器索引')));
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.storage.isAdminMode) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
          ),
          title: const Text('服务器媒体管理'),
        ),
        body: const Center(child: Text('仅管理员可访问')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: const Text('服务器媒体管理'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          TextField(
            controller: _queryCtrl,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _queryCtrl.text.isNotEmpty || _selected != null
                  ? IconButton(
                      tooltip: '清空鸟名',
                      icon: const Icon(Icons.close),
                      onPressed: _clearSelection,
                    )
                  : null,
              hintText: '搜索中文名 / English / 拉丁名 / 拼音首字母',
            ),
            onChanged: (value) {
              final selected = _selected;
              if (selected != null && value.trim() != _birdLabel(selected)) {
                setState(() {
                  _selected = null;
                  _media = null;
                  _message = '';
                });
              }
              _search(value);
            },
          ),
          if (_results.isNotEmpty)
            Card(
              child: Column(
                children: _results
                    .map(
                      (bird) => ListTile(
                        dense: true,
                        title: Text(bird.cn.isEmpty ? bird.en : bird.cn),
                        subtitle: Text('${bird.en} · ${bird.sci}'),
                        onTap: () => _select(bird),
                      ),
                    )
                    .toList(),
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          if (_message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_message, style: const TextStyle(color: Colors.red)),
            ),
          if (_media != null) _mediaView(_media!),
        ],
      ),
    );
  }

  Widget _mediaView(ServerSpeciesMedia media) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text(
          '${media.cn.isEmpty ? media.en : media.cn} · ${media.sci}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text('图片 ${media.images.length}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (media.images.isEmpty)
          const Text('暂无图片', style: TextStyle(color: Colors.grey))
        else
          ...media.images.map((image) => _imageItem(image)),
        const SizedBox(height: 16),
        Text('音频 ${media.audio.length}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (media.audio.isEmpty)
          const Text('暂无音频', style: TextStyle(color: Colors.grey))
        else
          ...media.audio.map((audio) => _audioItem(audio)),
      ],
    );
  }

  Widget _imageItem(ServerImageMedia image) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                image.url,
                width: 86,
                height: 86,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 86,
                  height: 86,
                  color: Colors.grey[200],
                  child: const Icon(Icons.broken_image),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                [
                  image.file,
                  if (image.contributor.isNotEmpty) '作者：${image.contributor}',
                  if (image.license.isNotEmpty) image.license,
                ].join('\n'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _delete(
                kind: 'images',
                file: image.file,
                title: image.file,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _audioItem(ServerAudioMedia audio) {
    final label = audio.type == 'song' ? '鸣唱 song' : '鸣叫 call';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      '$label · ${audio.file}',
                      if (audio.contributor.isNotEmpty)
                        '录音：${audio.contributor}',
                      if (audio.license.isNotEmpty) audio.license,
                    ].join('\n'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: '删除',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _delete(
                    kind: 'audio',
                    file: audio.file,
                    title: audio.file,
                  ),
                ),
              ],
            ),
            AudioPlayerWidget(audioPaths: [audio.url], audioLabels: [label]),
            if (audio.spectrogramUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  audio.spectrogramUrl,
                  height: 148,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
