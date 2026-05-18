import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/species.dart';
import 'audio_player_widget.dart';

/// 题型
enum StudyMode {
  review, // 判断题：先看/听题面，再判断认识或不认识
  quiz, // 选择题：看/听题面后从四个选项中选择
}

/// 出题媒介
enum PromptMode {
  audio, // 听音频猜鸟
  image, // 看图片猜鸟
}

/// 可翻转的闪卡组件
class BirdCard extends StatefulWidget {
  final Species species;
  final String? imagePath;
  final String? imageSourceFile;
  final String imageCredit;
  final List<String> audioPaths;
  final List<String> audioLabels;
  final StudyMode mode;
  final PromptMode promptMode;
  final VoidCallback? onAudioStarted;
  final VoidCallback? onRevealed;
  final VoidCallback? onPreviousSpecies;
  final VoidCallback? onNextSpecies;
  final GlobalKey<AudioPlayerWidgetState>? audioPlayerKey;
  final bool initiallyShowAnswer;

  // 额外图片（来自服务器，本地路径或网络 URL）
  final List<String> extraImagePaths;
  final List<String> extraImageSourceFiles;
  final List<String> extraImageCredits;

  // 了解此鸟回调
  final VoidCallback? onLearnMore;

  // 管理员难度评分
  final bool isAdmin;
  final ValueChanged<int>? onDifficultyChanged;
  final void Function(String imageFile, int difficulty)?
      onImageDifficultyChanged;

  const BirdCard({
    super.key,
    required this.species,
    this.imagePath,
    this.imageSourceFile,
    this.imageCredit = '',
    this.audioPaths = const [],
    this.audioLabels = const [],
    this.mode = StudyMode.review,
    this.promptMode = PromptMode.audio,
    this.onAudioStarted,
    this.onRevealed,
    this.onPreviousSpecies,
    this.onNextSpecies,
    this.audioPlayerKey,
    this.initiallyShowAnswer = false,
    this.extraImagePaths = const [],
    this.extraImageSourceFiles = const [],
    this.extraImageCredits = const [],
    this.onLearnMore,
    this.isAdmin = false,
    this.onDifficultyChanged,
    this.onImageDifficultyChanged,
  });

  @override
  State<BirdCard> createState() => BirdCardState();
}

class BirdCardState extends State<BirdCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _showFront = true;
  final PageController _imagePageController = PageController();
  int _imagePageIndex = 0;
  Offset? _imagePointerStart;
  Offset? _imagePointerLatest;
  int? _difficultyOverride;
  final Map<String, int> _imageDifficultyOverrides = {};

  List<_ImageEntry> get _allImages {
    final result = <_ImageEntry>[];
    if (widget.imagePath != null && File(widget.imagePath!).existsSync()) {
      final sourceFile = widget.imageSourceFile ??
          (widget.species.imageFiles.isNotEmpty
              ? widget.species.imageFiles.first
              : null);
      SpeciesImageInfo? sourceImage;
      if (sourceFile != null) {
        for (final image in widget.species.images) {
          if (image.file == sourceFile) {
            sourceImage = image;
            break;
          }
        }
      }
      result.add(_ImageEntry(
        path: widget.imagePath!,
        isNetwork: false,
        credit: widget.imageCredit.isNotEmpty
            ? widget.imageCredit
            : widget.species.imageCredit,
        sourceFile: sourceFile,
        difficulty: sourceImage?.difficulty ?? widget.species.difficulty,
      ));
    }
    for (var i = 0; i < widget.extraImagePaths.length; i++) {
      final p = widget.extraImagePaths[i];
      final isNet = p.startsWith('http://') || p.startsWith('https://');
      final credit = i < widget.extraImageCredits.length
          ? widget.extraImageCredits[i]
          : '';
      final sourceFile = i < widget.extraImageSourceFiles.length
          ? widget.extraImageSourceFiles[i]
          : null;
      SpeciesImageInfo? sourceImage;
      if (sourceFile != null) {
        for (final image in widget.species.images) {
          if (image.file == sourceFile) {
            sourceImage = image;
            break;
          }
        }
      }
      result.add(_ImageEntry(
        path: p,
        isNetwork: isNet,
        credit: credit,
        sourceFile: sourceFile,
        difficulty: sourceImage?.difficulty ?? widget.species.difficulty,
      ));
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _showFront = !widget.initiallyShowAnswer;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: widget.initiallyShowAnswer ? 1 : 0,
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(_controller);
  }

  @override
  void didUpdateWidget(covariant BirdCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldResetFace = oldWidget.species.sci != widget.species.sci ||
        oldWidget.promptMode != widget.promptMode ||
        oldWidget.mode != widget.mode ||
        oldWidget.initiallyShowAnswer != widget.initiallyShowAnswer;
    if (!shouldResetFace) return;

    _showFront = !widget.initiallyShowAnswer;
    _controller.value = widget.initiallyShowAnswer ? 1 : 0;
    _imagePageIndex = 0;
    _difficultyOverride = null;
    _imageDifficultyOverrides.clear();
    if (_imagePageController.hasClients) {
      _imagePageController.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _imagePageController.dispose();
    super.dispose();
  }

  void reveal() {
    setState(() => _showFront = !_showFront);
    widget.onRevealed?.call();
    if (_showFront) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  void showBack() {
    if (_showFront) {
      setState(() => _showFront = false);
      widget.onRevealed?.call();
      _controller.forward();
    }
  }

  void showFront() {
    if (!_showFront) {
      setState(() => _showFront = true);
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final angle = _animation.value * 3.14159;
        final isFront = _animation.value < 0.5;

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          child: isFront
              ? _buildFront()
              : Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(3.14159),
                  child: _buildBack(),
                ),
        );
      },
    );
  }

  Widget _buildFront() {
    return _buildPromptFront();
  }

  Widget _buildPromptFront() {
    final images = _allImages;
    final isImagePrompt = widget.promptMode == PromptMode.image;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isImagePrompt) ...[
            if (images.isNotEmpty)
              _imageCarousel(images: images, height: 190)
            else
              _imagePlaceholder(190),
          ] else ...[
            AudioPlayerWidget(
              key: widget.audioPlayerKey,
              audioPaths: widget.audioPaths,
              audioLabels: widget.audioLabels,
              onPlayStarted: widget.onAudioStarted,
            ),
            const SizedBox(height: 12),
            const Icon(Icons.headphones, size: 38, color: Color(0xFF2d5016)),
          ],
        ],
      ),
    );
  }

  Widget _buildBack() {
    final sp = widget.species;
    final images = _allImages;
    final isImagePrompt = widget.promptMode == PromptMode.image;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFFF7),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFF2d5016), width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isImagePrompt) ...[
            if (images.isNotEmpty)
              _imageCarousel(images: images, height: 170)
            else
              _imagePlaceholder(170),
            const SizedBox(height: 10),
          ] else ...[
            AudioPlayerWidget(
              key: widget.audioPlayerKey,
              audioPaths: widget.audioPaths,
              audioLabels: widget.audioLabels,
              onPlayStarted: widget.onAudioStarted,
            ),
            const SizedBox(height: 10),
            const Icon(Icons.headphones, size: 30, color: Color(0xFF2d5016)),
            const SizedBox(height: 8),
          ],
          _creditLine(showImageCredit: isImagePrompt),
          Text(
            sp.cn,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2d5016),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            sp.en,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          if (sp.consText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: sp.isGrade1 ? Colors.red[50] : Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                sp.consText,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: sp.isGrade1 ? Colors.red[700] : Colors.orange[800],
                ),
              ),
            ),
          ],
          if (sp.habitat.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_on, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    sp.habitat,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ],
          // 了解此鸟 + 管理员难度星
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.onLearnMore != null)
                TextButton.icon(
                  onPressed: widget.onLearnMore,
                  icon: const Icon(Icons.menu_book_outlined, size: 16),
                  label: const Text('了解此鸟'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF2d5016),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
          ),
          if (widget.isAdmin && widget.onDifficultyChanged != null)
            _difficultyRow(),
        ],
      ),
    );
  }

  Widget _imageCarousel(
      {required List<_ImageEntry> images, required double height}) {
    if (images.length == 1) {
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _startImagePointer,
        onPointerMove: _updateImagePointer,
        onPointerUp: (_) => _finishImagePointer(images),
        onPointerCancel: (_) => _clearImagePointer(),
        child: _singleImageView(images.first, height: height),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _startImagePointer,
            onPointerMove: _updateImagePointer,
            onPointerUp: (_) => _finishImagePointer(images),
            onPointerCancel: (_) => _clearImagePointer(),
            child: PageView.builder(
              controller: _imagePageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: images.length,
              onPageChanged: (i) => setState(() => _imagePageIndex = i),
              itemBuilder: (context, i) =>
                  _singleImageView(images[i], height: height),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(images.length, (i) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _imagePageIndex == i ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: _imagePageIndex == i
                    ? const Color(0xFF2d5016)
                    : Colors.grey[300],
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
        if (images[_imagePageIndex].credit.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '© ${images[_imagePageIndex].credit}',
            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  void _startImagePointer(PointerDownEvent event) {
    _imagePointerStart = event.position;
    _imagePointerLatest = event.position;
  }

  void _updateImagePointer(PointerMoveEvent event) {
    _imagePointerLatest = event.position;
  }

  void _finishImagePointer(List<_ImageEntry> images) {
    final start = _imagePointerStart;
    final latest = _imagePointerLatest;
    _clearImagePointer();
    if (start == null || latest == null || images.isEmpty) return;

    final delta = latest - start;
    final dx = delta.dx;
    final dy = delta.dy;
    if (dx.abs() < 44 || dx.abs() < dy.abs() * 1.25) return;

    if (dx < 0) {
      if (_imagePageIndex < images.length - 1) {
        _imagePageController.animateToPage(
          _imagePageIndex + 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        widget.onNextSpecies?.call();
      }
      return;
    }

    if (_imagePageIndex > 0) {
      _imagePageController.animateToPage(
        _imagePageIndex - 1,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      widget.onPreviousSpecies?.call();
    }
  }

  void _clearImagePointer() {
    _imagePointerStart = null;
    _imagePointerLatest = null;
  }

  Widget _singleImageView(_ImageEntry entry, {required double height}) {
    Widget img;
    if (entry.isNetwork) {
      img = Image.network(
        entry.path,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
            child: Text('图片加载失败', style: TextStyle(color: Colors.grey))),
      );
    } else {
      img = Image.file(
        File(entry.path),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
            child: Text('图片加载失败', style: TextStyle(color: Colors.grey))),
      );
    }

    return GestureDetector(
      onTap: () => _showImagePreview(entry),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            color: const Color(0xFFF4F7F1),
            child: Stack(
              alignment: Alignment.topRight,
              children: [
                Positioned.fill(
                  child: Padding(padding: const EdgeInsets.all(8), child: img),
                ),
                Container(
                  margin: const EdgeInsets.all(8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.48),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.zoom_out_map, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text('放大',
                          style: TextStyle(color: Colors.white, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _imagePlaceholder(double height) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child:
            Icon(Icons.image_not_supported, size: 48, color: Colors.grey[300]),
      ),
    );
  }

  Widget _difficultyRow() {
    final images = _allImages;
    final currentImage = images.isNotEmpty
        ? images[_imagePageIndex.clamp(0, images.length - 1)]
        : null;
    final imageKey = currentImage?.sourceFile ?? currentImage?.path;
    final diff = widget.promptMode == PromptMode.image && currentImage != null
        ? (_imageDifficultyOverrides[imageKey] ?? currentImage.difficulty)
        : (_difficultyOverride ?? widget.species.difficulty);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('难度：', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ...List.generate(5, (i) {
            final filled = i < diff;
            return GestureDetector(
              onTap: () {
                final value = i + 1;
                if (widget.promptMode == PromptMode.image &&
                    currentImage?.sourceFile != null &&
                    widget.onImageDifficultyChanged != null) {
                  setState(() {
                    _imageDifficultyOverrides[currentImage!.sourceFile!] =
                        value;
                  });
                  widget.onImageDifficultyChanged!(
                    currentImage!.sourceFile!,
                    value,
                  );
                } else {
                  setState(() => _difficultyOverride = value);
                  widget.onDifficultyChanged?.call(value);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  filled ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 22,
                  color: filled ? Colors.amber[700] : Colors.grey[400],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _creditLine({required bool showImageCredit}) {
    final currentImageCredit = widget.imageCredit.isNotEmpty
        ? widget.imageCredit
        : widget.species.imageCredit;
    final credits = [
      if (showImageCredit && currentImageCredit.isNotEmpty)
        '图片感谢：$currentImageCredit',
      if (widget.species.audioCredit.isNotEmpty)
        '音频感谢：${widget.species.audioCredit}',
    ];
    // If carousel handles per-image credits, skip the image credit in credit line
    if (_allImages.length > 1 && showImageCredit) {
      final audioCreditOnly =
          credits.where((c) => c.startsWith('音频感谢')).toList();
      if (audioCreditOnly.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          audioCreditOnly.join(' · '),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
      );
    }
    if (credits.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        credits.join(' · '),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
      ),
    );
  }

  void _showImagePreview(_ImageEntry entry) {
    Widget img;
    if (entry.isNetwork) {
      img = Image.network(entry.path, fit: BoxFit.contain);
    } else {
      img = Image.file(File(entry.path), fit: BoxFit.contain);
    }
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: img,
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: IconButton.filled(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageEntry {
  final String path;
  final bool isNetwork;
  final String credit;
  final String? sourceFile;
  final int difficulty;
  const _ImageEntry({
    required this.path,
    required this.isNetwork,
    required this.credit,
    this.sourceFile,
    this.difficulty = 1,
  });
}
