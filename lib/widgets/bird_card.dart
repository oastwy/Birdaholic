import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/species.dart';
import 'audio_player_widget.dart';

/// 学习模式
enum StudyMode {
  preview,  // 预习模式：正面显示图片+鸟名+音频
  review,   // 复习模式：正面只显示音频，需要猜
}

/// 可翻转的闪卡组件
class BirdCard extends StatefulWidget {
  final Species species;
  final String? imagePath;
  final List<String> audioPaths;
  final List<String> audioLabels;
  final StudyMode mode;
  final VoidCallback? onAudioStarted;
  final VoidCallback? onRevealed;
  final GlobalKey<AudioPlayerWidgetState>? audioPlayerKey;

  const BirdCard({
    super.key,
    required this.species,
    this.imagePath,
    this.audioPaths = const [],
    this.audioLabels = const [],
    this.mode = StudyMode.review,
    this.onAudioStarted,
    this.onRevealed,
    this.audioPlayerKey,
  });

  @override
  State<BirdCard> createState() => BirdCardState();
}

class BirdCardState extends State<BirdCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _showFront = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(_controller);
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
    if (widget.mode == StudyMode.preview) {
      return _buildPreviewFront();
    } else {
      return _buildReviewFront();
    }
  }

  /// 预习模式正面：显示图片 + 鸟名 + 音频播放
  Widget _buildPreviewFront() {
    final sp = widget.species;
    final hasImage = widget.imagePath != null && File(widget.imagePath!).existsSync();

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
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
        children: [
          // 图片
          if (hasImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(widget.imagePath!),
                height: 180,
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 60,
                  child: Center(
                      child: Text('📷 图片加载失败',
                          style: TextStyle(color: Colors.grey))),
                ),
              ),
            )
          else
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(Icons.image_not_supported, size: 48, color: Colors.grey[300]),
              ),
            ),
          const SizedBox(height: 12),
          // 中文名
          Text(
            sp.cn,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2d5016),
            ),
          ),
          const SizedBox(height: 2),
          // 英文名
          Text(
            sp.en,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
          // 保护等级
          if (sp.consText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: sp.isGrade1 ? Colors.red[50] : Colors.orange[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                sp.consText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: sp.isGrade1 ? Colors.red[700] : Colors.orange[800],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          // 音频播放器
          const Text('🔊 听一听它的鸟鸣',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 8),
          AudioPlayerWidget(
            key: widget.audioPlayerKey,
            audioPaths: widget.audioPaths,
            audioLabels: widget.audioLabels,
            onPlayStarted: widget.onAudioStarted,
          ),
          const SizedBox(height: 12),
          Text(
            '认识吗？ →',
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  /// 复习模式正面：只显示音频，猜鸟名
  Widget _buildReviewFront() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
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
        children: [
          AudioPlayerWidget(
            key: widget.audioPlayerKey,
            audioPaths: widget.audioPaths,
            audioLabels: widget.audioLabels,
            onPlayStarted: widget.onAudioStarted,
          ),
          const SizedBox(height: 24),
          const Icon(Icons.headphones, size: 48, color: Color(0xFF2d5016)),
          const SizedBox(height: 12),
          const Text(
            '听鸟鸣，猜猜这是什么鸟？',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '选择「认识」或「不认识」，然后揭晓答案',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  /// 背面：答案页（两种模式共用，但预习模式作为音频播放页）
  Widget _buildBack() {
    final sp = widget.species;
    final hasImage = widget.imagePath != null && File(widget.imagePath!).existsSync();

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
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
        children: [
          // 图片
          if (hasImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(widget.imagePath!),
                height: 200,
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 60,
                  child: Center(
                      child: Text('📷 图片加载失败',
                          style: TextStyle(color: Colors.grey))),
                ),
              ),
            ),
          const SizedBox(height: 12),
          // 中文名
          Text(
            sp.cn,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2d5016),
            ),
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
          ),
          const SizedBox(height: 4),
          // 学名
          Text(
            sp.sci,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[500],
              fontStyle: FontStyle.italic,
            ),
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
                Text(
                  sp.habitat,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
