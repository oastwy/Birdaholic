import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/species.dart';
import '../services/admin_upload_service.dart';
import '../services/ebird_service.dart';
import '../services/pack_manager.dart';
import '../services/server_media_service.dart';
import '../services/storage.dart';
import '../widgets/audio_player_widget.dart';

class BirdPreviewScreen extends StatefulWidget {
  final List<Species> speciesList;
  final int initialIndex;
  final PackManager packManager;
  final StorageService storage;
  final ValueChanged<Species>? onDownload;

  /// Convenience constructor for a single species (e.g. from FlashcardScreen).
  BirdPreviewScreen({
    super.key,
    required Species species,
    required this.packManager,
    required this.storage,
    this.onDownload,
  })  : speciesList = [species],
        initialIndex = 0;

  const BirdPreviewScreen.list({
    super.key,
    required this.speciesList,
    this.initialIndex = 0,
    required this.packManager,
    required this.storage,
    this.onDownload,
  });

  @override
  State<BirdPreviewScreen> createState() => _BirdPreviewScreenState();
}

class _BirdPreviewScreenState extends State<BirdPreviewScreen> {
  late List<Species> _list;
  late int _idx;

  // Server media cache
  final Map<String, ServerSpeciesMedia?> _serverCache = {};
  ServerSpeciesMedia? _currentServerMedia;
  bool _serverLoading = false;

  // eBird filter
  Set<String> _ebirdFilterSci = const {};
  String _ebirdFilterLabel = '';

  // Photo page index per species sci
  final Map<String, int> _photoPageIndex = {};
  final Map<String, PageController> _photoControllers = {};

  @override
  void initState() {
    super.initState();
    _list = List.of(widget.speciesList);
    _idx = widget.initialIndex.clamp(0, _list.length - 1);
    _loadServerMedia();
  }

  @override
  void dispose() {
    for (final c in _photoControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Species get _current => _list[_idx];

  PageController _pageControllerFor(String sci) {
    return _photoControllers.putIfAbsent(sci, () => PageController());
  }

  Future<void> _loadServerMedia() async {
    final sci = _current.sci;
    if (_serverCache.containsKey(sci)) {
      setState(() => _currentServerMedia = _serverCache[sci]);
      return;
    }
    setState(() {
      _serverLoading = true;
      _currentServerMedia = null;
    });
    try {
      final media = await ServerMediaService().fetchSpeciesMedia(sci);
      _serverCache[sci] = media;
      if (mounted && _current.sci == sci) {
        setState(() {
          _currentServerMedia = media;
          _serverLoading = false;
        });
      }
    } catch (_) {
      _serverCache[sci] = null;
      if (mounted) setState(() => _serverLoading = false);
    }
  }

  void _goTo(int newIdx) {
    if (newIdx < 0 || newIdx >= _list.length) return;
    setState(() => _idx = newIdx);
    _loadServerMedia();
  }

  Future<void> _applyEBirdFilter() async {
    final apiKey = widget.storage.getEBirdApiKey();
    if (apiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置页填写 eBird API key')),
      );
      return;
    }

    final controller = TextEditingController(text: _ebirdFilterLabel);
    final query = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('eBird 地点筛选',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                '输入国家、地区或热点代码，把预习范围收窄到这个地点的鸟种。',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: '例如 中国、云南、那邦、CN、CN-53、L3124991',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: EBirdService.presets.take(8).map((preset) {
                  return ActionChip(
                    label: Text(preset.label),
                    onPressed: () => Navigator.pop(ctx, preset.code),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, '__clear__'),
                    child: const Text('清除地点'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                    child: const Text('应用'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (query == null) return;

    if (query == '__clear__') {
      setState(() {
        _ebirdFilterSci = const {};
        _ebirdFilterLabel = '';
        _list = List.of(widget.speciesList);
        _idx = 0;
      });
      _loadServerMedia();
      return;
    }
    if (query.trim().isEmpty) return;

    try {
      if (mounted) setState(() => _serverLoading = true);
      final matches =
          await EBirdService(apiKey: apiKey).fetchSpeciesMatches(query);
      final sciSet = await _matchEBirdToSci(matches);
      final filtered = widget.speciesList
          .where((s) => sciSet.contains(s.sci.trim().toLowerCase()))
          .toList();
      if (!mounted) return;
      setState(() {
        _ebirdFilterSci = sciSet;
        _ebirdFilterLabel = EBirdService.normalizeLocationCode(query);
        _list = filtered.isEmpty ? widget.speciesList : filtered;
        _idx = 0;
        _serverLoading = false;
      });
      _loadServerMedia();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(filtered.isEmpty
              ? '没有匹配结果，已显示全部'
              : '已按 $_ebirdFilterLabel 筛出 ${filtered.length} 种'),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _serverLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('eBird 筛选失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<Set<String>> _matchEBirdToSci(Set<EbirdSpeciesMatch> matches) async {
    final raw = await rootBundle.loadString('assets/data/world_birds.json');
    final data = jsonDecode(raw) as List<dynamic>;
    final byCode = <String, String>{};
    final bySci = <String>{};
    for (final value in data) {
      final item = value as Map<String, dynamic>;
      final sci = (item['sci'] as String? ?? '').trim().toLowerCase();
      if (sci.isEmpty) continue;
      bySci.add(sci);
      final code = (item['code'] as String? ?? '').trim().toLowerCase();
      if (code.isNotEmpty) byCode[code] = sci;
    }
    return matches
        .map((match) {
          final byMatchedCode = byCode[match.code.trim().toLowerCase()];
          if (byMatchedCode != null) return byMatchedCode;
          final sci = match.scientificName.trim().toLowerCase();
          return bySci.contains(sci) ? sci : '';
        })
        .where((sci) => sci.isNotEmpty)
        .toSet();
  }

  Future<void> _uploadImage() async {
    final sp = _current;
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;
    try {
      await widget.packManager.replaceSpeciesImageFromFile(sp, path);
      if (widget.storage.isAdminMode) {
        await AdminUploadService().uploadMedia(
          species: sp,
          filePath: path,
          token: widget.storage.getAdminUploadToken(),
        );
      }
      _serverCache.remove(sp.sci);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(widget.storage.isAdminMode ? '鸟图已保存并推送服务器' : '鸟图已保存到当前数据包'),
      ));
      setState(() {});
      _loadServerMedia();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _uploadAudio() async {
    final sp = _current;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;
    try {
      await widget.packManager.addSpeciesAudioFromFile(sp, path);
      if (widget.storage.isAdminMode) {
        await AdminUploadService().uploadMedia(
          species: sp,
          filePath: path,
          token: widget.storage.getAdminUploadToken(),
        );
      }
      _serverCache.remove(sp.sci);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(widget.storage.isAdminMode ? '音频已保存并推送服务器' : '音频已保存到当前数据包'),
      ));
      setState(() {});
      _loadServerMedia();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sp = _current;
    final isFav = widget.storage.isFavorite(sp.cn);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B0A),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sp.cn,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(
              sp.sci,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.7),
                  fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _ebirdFilterLabel.isEmpty ? 'eBird 筛选' : _ebirdFilterLabel,
            onPressed: _applyEBirdFilter,
            icon: Icon(
              Icons.place_outlined,
              color:
                  _ebirdFilterSci.isEmpty ? Colors.white70 : Colors.greenAccent,
            ),
          ),
          IconButton(
            tooltip: isFav ? '取消收藏' : '收藏',
            onPressed: () {
              widget.storage.toggleFavorite(sp.cn);
              setState(() {});
            },
            icon: Icon(
              isFav ? Icons.star_rounded : Icons.star_outline_rounded,
              color: isFav ? Colors.amber : Colors.white70,
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          final vx = details.primaryVelocity ?? 0;
          if (vx < -300) _goTo(_idx + 1);
          if (vx > 300) _goTo(_idx - 1);
        },
        child: _buildBody(sp),
      ),
      bottomNavigationBar: _list.length > 1 ? _buildNavBar() : null,
    );
  }

  Widget _buildNavBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            IconButton.filled(
              onPressed: _idx > 0 ? () => _goTo(_idx - 1) : null,
              style: IconButton.styleFrom(
                backgroundColor:
                    _idx > 0 ? const Color(0xFF2d7d32) : Colors.grey[800],
              ),
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 18),
            ),
            Expanded(
              child: Center(
                child: Text(
                  '${_idx + 1} / ${_list.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ),
            IconButton.filled(
              onPressed: _idx < _list.length - 1 ? () => _goTo(_idx + 1) : null,
              style: IconButton.styleFrom(
                backgroundColor: _idx < _list.length - 1
                    ? const Color(0xFF2d7d32)
                    : Colors.grey[800],
              ),
              icon: const Icon(Icons.arrow_forward_ios_rounded,
                  color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(Species sp) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
      children: [
        // Photo carousel
        _buildPhotoSection(sp),
        // EN name + species info chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sp.en,
                style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                    fontStyle: FontStyle.italic),
              ),
              if (sp.consText.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: sp.isGrade1
                        ? Colors.red.withValues(alpha: 0.25)
                        : Colors.orange.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color:
                          sp.isGrade1 ? Colors.red[300]! : Colors.orange[300]!,
                    ),
                  ),
                  child: Text(
                    sp.consText,
                    style: TextStyle(
                      fontSize: 12,
                      color: sp.isGrade1 ? Colors.red[200] : Colors.orange[200],
                    ),
                  ),
                ),
              ],
              if (sp.habitat.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 14, color: Colors.white54),
                    const SizedBox(width: 4),
                    Text(sp.habitat,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.white54)),
                  ],
                ),
              ],
              if (sp.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  sp.description,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: Colors.white70,
                  ),
                ),
                if (sp.descriptionSource.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    '简介来源：${sp.descriptionSource}',
                    style: const TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ],
              ],
            ],
          ),
        ),
        // Audio section
        _buildAudioSection(sp),
        // Identification features
        _buildFeaturesSection(sp),
        // Upload actions
        _buildUploadRow(),
      ],
    );
  }

  Widget _buildPhotoSection(Species sp) {
    final localImagePaths = _localImagePaths(sp);
    final serverImages = _currentServerMedia?.images ?? [];
    final localNames = sp.imageFiles.map((p) => p.split('/').last).toSet();
    final filteredServerImages = serverImages.where((img) {
      final segments = Uri.tryParse(img.url)?.pathSegments ?? const [];
      final name = segments.isNotEmpty ? segments.last : img.file;
      return name.isEmpty || !localNames.contains(name);
    });
    // Combine local + server images
    final allImages = <_PreviewImage>[
      for (var i = 0; i < localImagePaths.length; i++)
        _PreviewImage(
          path: localImagePaths[i],
          isNetwork: false,
          credit: i < sp.images.length && sp.images[i].credit.isNotEmpty
              ? sp.images[i].credit
              : sp.imageCredit,
        ),
      ...filteredServerImages.map((img) => _PreviewImage(
            path: img.url,
            isNetwork: true,
            credit: img.contributor.isNotEmpty
                ? img.contributor
                : (img.source.isNotEmpty ? img.source : ''),
          )),
    ];

    if (allImages.isEmpty) {
      return Container(
        height: 240,
        width: double.infinity,
        color: const Color(0xFF1A2B17),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_not_supported_outlined,
                  size: 48, color: Colors.white24),
              SizedBox(height: 8),
              Text('暂无图片',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final ctrl = _pageControllerFor(sp.sci);
    final pageIdx = _photoPageIndex[sp.sci] ?? 0;

    return Column(
      children: [
        SizedBox(
          height: 280,
          child: PageView.builder(
            controller: ctrl,
            itemCount: allImages.length,
            onPageChanged: (i) => setState(() => _photoPageIndex[sp.sci] = i),
            itemBuilder: (_, i) => _buildPhotoPage(allImages[i]),
          ),
        ),
        if (allImages.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(allImages.length, (i) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: pageIdx == i ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: pageIdx == i ? Colors.greenAccent : Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
        if (pageIdx < allImages.length && allImages[pageIdx].credit.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '© ${allImages[pageIdx].credit}',
              style: const TextStyle(fontSize: 11, color: Colors.white38),
              textAlign: TextAlign.center,
            ),
          ),
        if (_serverLoading)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '正在加载更多图片…',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ),
      ],
    );
  }

  Widget _buildPhotoPage(_PreviewImage img) {
    Widget image;
    if (img.isNetwork) {
      image = Image.network(
        img.path,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined,
              color: Colors.white24, size: 40),
        ),
      );
    } else {
      image = Image.file(
        File(img.path),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined,
              color: Colors.white24, size: 40),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _showFullscreenImage(img),
      child: Container(
        color: const Color(0xFF1A2B17),
        child: image,
      ),
    );
  }

  void _showFullscreenImage(_PreviewImage img) {
    Widget src;
    if (img.isNetwork) {
      src = Image.network(img.path, fit: BoxFit.contain);
    } else {
      src = Image.file(File(img.path), fit: BoxFit.contain);
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(8),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 6,
                child: Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: src,
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: IconButton.filled(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioSection(Species sp) {
    final localAudios = sp.audios;
    final serverAudios = _currentServerMedia?.audio ?? [];

    if (localAudios.isEmpty && serverAudios.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
        child:
            Text('暂无音频', style: TextStyle(color: Colors.white38, fontSize: 13)),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '鸟鸣',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white70),
          ),
          const SizedBox(height: 8),
          // Local audio
          if (localAudios.isNotEmpty)
            FutureBuilder<List<String>>(
              future: _resolveAudioPaths(sp),
              builder: (_, snap) {
                if (!snap.hasData) {
                  return const SizedBox(
                      height: 40,
                      child: Center(child: CircularProgressIndicator()));
                }
                final paths = snap.data!;
                if (paths.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AudioPlayerWidget(
                      audioPaths: paths,
                      audioLabels:
                          localAudios.map((a) => a.displayLabel).toList(),
                    ),
                    if (sp.audioCredit.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '录音：${sp.audioCredit}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white38),
                        ),
                      ),
                  ],
                );
              },
            ),
          // Server audio
          ...serverAudios.map((audio) {
            final label = audio.type == 'song' ? '鸣唱 song' : '鸣叫 call';
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: AudioPlayerWidget(
                      audioPaths: [audio.url],
                      audioLabels: [label],
                    ),
                  ),
                  if (audio.contributor.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: audio.contributorUrl.isNotEmpty
                          ? () => launchUrl(
                                Uri.parse(audio.contributorUrl),
                                mode: LaunchMode.externalApplication,
                              )
                          : null,
                      child: Text(
                        audio.contributor,
                        style: TextStyle(
                          fontSize: 11,
                          color: audio.contributorUrl.isNotEmpty
                              ? Colors.greenAccent[200]
                              : Colors.white38,
                          decoration: audio.contributorUrl.isNotEmpty
                              ? TextDecoration.underline
                              : null,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFeaturesSection(Species sp) {
    final note = widget.storage.getSpeciesNote(sp.sci);
    final text = note.isNotEmpty ? note : sp.identificationFeatures;
    final serverText = _currentServerMedia?.identificationFeatures ?? '';
    final display = text.isNotEmpty
        ? text
        : serverText.isNotEmpty
            ? serverText
            : '';
    if (display.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '辨识特征',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2B17),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              display,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 14, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadRow() {
    final sp = _current;
    final installed = sp.hasAudio || sp.hasImage;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          if (widget.onDownload != null)
            FilledButton.icon(
              onPressed: () => widget.onDownload?.call(sp),
              icon: Icon(
                installed ? Icons.sync : Icons.cloud_download_outlined,
                size: 18,
              ),
              label: Text(installed ? '补充媒体' : '下载到数据包'),
            ),
          OutlinedButton.icon(
            onPressed: _uploadImage,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
            ),
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: Text(
              widget.storage.isAdminMode ? '上传图片（推送服务器）' : '上传图片',
            ),
          ),
          OutlinedButton.icon(
            onPressed: _uploadAudio,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
            ),
            icon: const Icon(Icons.library_music_outlined, size: 18),
            label: Text(
              widget.storage.isAdminMode ? '上传音频（推送服务器）' : '上传音频',
            ),
          ),
        ],
      ),
    );
  }

  List<String> _localImagePaths(Species sp) {
    // We need a sync path — use cached packDir
    final dir = _cachedPackDir;
    if (dir == null) {
      _warmCachedPackDir();
      return const [];
    }
    final paths = <String>[];
    for (final image in sp.imageFiles) {
      final path = '$dir/$image';
      if (File(path).existsSync()) paths.add(path);
    }
    return paths;
  }

  String? _cachedPackDir;

  Future<void> _warmCachedPackDir() async {
    final dir = await widget.packManager.getActivePackDir();
    if (!mounted) return;
    if (dir != _cachedPackDir) {
      setState(() => _cachedPackDir = dir);
    }
  }

  Future<List<String>> _resolveAudioPaths(Species sp) async {
    final paths = <String>[];
    for (final audio in sp.audios) {
      final p = await widget.packManager.getResourcePath(audio.file);
      if (p != null) paths.add(p);
    }
    return paths;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cachedPackDir == null) _warmCachedPackDir();
  }
}

class _PreviewImage {
  final String path;
  final bool isNetwork;
  final String credit;
  const _PreviewImage({
    required this.path,
    required this.isNetwork,
    required this.credit,
  });
}
