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
  final List<String> audioPaths;
  final List<String> audioLabels;
  final StudyMode mode;
  final PromptMode promptMode;
  final VoidCallback? onAudioStarted;
  final VoidCallback? onRevealed;
  final GlobalKey<AudioPlayerWidgetState>? audioPlayerKey;
  final bool initiallyShowAnswer;

  const BirdCard({
    super.key,
    required this.species,
    this.imagePath,
    this.audioPaths = const [],
    this.audioLabels = const [],
    this.mode = StudyMode.review,
    this.promptMode = PromptMode.audio,
    this.onAudioStarted,
    this.onRevealed,
    this.audioPlayerKey,
    this.initiallyShowAnswer = false,
  });

  @override
  State<BirdCard> createState() => BirdCardState();
}

class BirdCardState extends State<BirdCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _showFront = true;

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
  }

  @override
  void dispose() {
    _controller.dispose();
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

  /// 正面：根据模式显示不同内容
  Widget _buildFront() {
    return _buildPromptFront();
  }

  /// 题面：音频模式只听鸟鸣，图片模式只看鸟图，答案都放在背面。
  Widget _buildPromptFront() {
    final hasImage =
        widget.imagePath != null && File(widget.imagePath!).existsSync();
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
            if (hasImage)
              _zoomableImage(height: 190)
            else
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(Icons.image_not_supported,
                      size: 48, color: Colors.grey[300]),
                ),
              ),
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

  /// 背面：答案页（两种模式共用，但预习模式作为音频播放页）
  Widget _buildBack() {
    final sp = widget.species;
    final hasImage =
        widget.imagePath != null && File(widget.imagePath!).existsSync();
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
            if (hasImage) _zoomableImage(height: 170),
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
          // 中文名
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
          // 英文名
          Text(
            sp.en,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          // 保护等级
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
          // 栖息地
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
        ],
      ),
    );
  }

  Widget _zoomableImage({required double height}) {
    return GestureDetector(
      onTap: _showImagePreview,
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
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Image.file(
                      File(widget.imagePath!),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text(
                          '图片加载失败',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
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
                      Text(
                        '放大',
                        style: TextStyle(color: Colors.white, fontSize: 11),
                      ),
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

  Widget _creditLine({required bool showImageCredit}) {
    final credits = [
      if (showImageCredit && widget.species.imageCredit.isNotEmpty)
        '图片感谢：${widget.species.imageCredit}',
      if (widget.species.audioCredit.isNotEmpty)
        '音频感谢：${widget.species.audioCredit}',
    ];
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

  void _showImagePreview() {
    if (widget.imagePath == null) return;
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
                  child:
                      Image.file(File(widget.imagePath!), fit: BoxFit.contain),
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
