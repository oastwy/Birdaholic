import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

/// 音频播放器控件
/// 显示播放/暂停按钮、音频类型切换标签
class AudioPlayerWidget extends StatefulWidget {
  final List<String> audioPaths;  // 音频文件绝对路径列表
  final List<String> audioLabels; // 标签列表，如 ["鸣叫 call", "鸣唱 song"]
  final VoidCallback? onPlayStarted;

  const AudioPlayerWidget({
    super.key,
    required this.audioPaths,
    required this.audioLabels,
    this.onPlayStarted,
  });

  @override
  State<AudioPlayerWidget> createState() => AudioPlayerWidgetState();
}

class AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final AudioPlayer _player = AudioPlayer();
  int _currentIndex = 0;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      setState(() => _isPlaying = false);
    });
    _player.onDurationChanged.listen((d) {
      setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      setState(() => _position = p);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _play(int index) async {
    if (index < 0 || index >= widget.audioPaths.length) return;
    setState(() {
      _currentIndex = index;
      _isPlaying = true;
      _position = Duration.zero;
    });
    try {
      await _player.setSource(DeviceFileSource(widget.audioPaths[index]));
      await _player.resume();
      widget.onPlayStarted?.call();
    } catch (e) {
      setState(() => _isPlaying = false);
    }
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
      setState(() => _isPlaying = false);
    } else {
      await _play(_currentIndex);
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.audioPaths.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text('🔇 暂无音频', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 音频类型标签切换
        if (widget.audioPaths.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.audioPaths.length, (i) {
                final active = i == _currentIndex;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(
                      widget.audioLabels[i],
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: active,
                    onSelected: (_) => _play(i),
                  ),
                );
              }),
            ),
          ),
        // 播放控制
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 播放/暂停按钮
            SizedBox(
              width: 56,
              height: 56,
              child: FloatingActionButton(
                heroTag: 'play_btn',
                backgroundColor: Colors.green[700],
                onPressed: _togglePlay,
                child: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 32,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 20),
            // 进度
            SizedBox(
              width: 160,
              child: Column(
                children: [
                  Slider(
                    value: _duration.inMilliseconds > 0
                        ? _position.inMilliseconds / _duration.inMilliseconds
                        : 0,
                    onChanged: (v) {
                      final pos = Duration(
                          milliseconds: (v * _duration.inMilliseconds).round());
                      _player.seek(pos);
                    },
                    activeColor: Colors.green[700],
                    inactiveColor: Colors.green[100],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(_position),
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      Text(_formatDuration(_duration),
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 外部调用：自动播放
  void autoPlay() {
    if (widget.audioPaths.isNotEmpty) {
      _play(0);
    }
  }
}
