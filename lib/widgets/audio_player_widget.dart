import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

/// 音频播放器控件
/// 显示播放/暂停按钮、音频类型切换标签
class AudioPlayerWidget extends StatefulWidget {
  final List<String> audioPaths; // 音频文件绝对路径列表
  final List<String> audioLabels; // 标签列表，如 ["鸣叫 call", "鸣唱 song"]
  final VoidCallback? onPlayStarted;
  final ValueChanged<int>? onAudioIndexChanged; // 当前播放音频索引变化

  const AudioPlayerWidget({
    super.key,
    required this.audioPaths,
    required this.audioLabels,
    this.onPlayStarted,
    this.onAudioIndexChanged,
  });

  @override
  State<AudioPlayerWidget> createState() => AudioPlayerWidgetState();
}

class AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final AudioPlayer _player = AudioPlayer();
  int _currentIndex = 0;
  bool _isPlaying = false;
  String? _error;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  List<String> get _paths =>
      widget.audioPaths.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

  List<String> get _labels {
    final paths = _paths;
    return List.generate(paths.length, (i) {
      if (i < widget.audioLabels.length && widget.audioLabels[i].trim().isNotEmpty) {
        return widget.audioLabels[i].trim();
      }
      return '音频 ${i + 1}';
    });
  }

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state == PlayerState.playing);
    });
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() => _isPlaying = false);
    });
    _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AudioPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioPaths.join('|') != widget.audioPaths.join('|')) {
      stop();
      _currentIndex = 0;
      _duration = Duration.zero;
      _position = Duration.zero;
      _error = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onAudioIndexChanged?.call(0);
      });
    }
  }

  Future<void> _play(int index) async {
    final paths = _paths;
    if (index < 0 || index >= paths.length) return;
    final indexChanged = _currentIndex != index;
    setState(() {
      _currentIndex = index;
      _isPlaying = true;
      _position = Duration.zero;
      _error = null;
    });
    if (indexChanged) widget.onAudioIndexChanged?.call(index);
    try {
      final path = paths[index];
      final uri = Uri.tryParse(path);
      final source = uri != null &&
              uri.hasScheme &&
              (uri.scheme == 'http' || uri.scheme == 'https')
          ? UrlSource(path)
          : DeviceFileSource(path);
      await _player.setSource(source);
      await _player.resume();
      widget.onPlayStarted?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _error = '音频加载失败';
      });
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
    final paths = _paths;
    final labels = _labels;
    if (paths.isEmpty) {
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
        if (paths.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(paths.length, (i) {
                final active = i == _currentIndex;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(
                      labels[i],
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
          children: [
            // 播放/暂停按钮
            SizedBox(
              width: 44,
              height: 44,
              child: FloatingActionButton(
                heroTag: null,
                backgroundColor: Colors.green[700],
                onPressed: _togglePlay,
                child: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 26,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 进度（自适应宽度）
            Expanded(
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
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                      Text(_formatDuration(_duration),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.red)),
        ],
      ],
    );
  }

  /// 外部调用：自动播放
  void autoPlay() {
    if (_paths.isNotEmpty) {
      _play(0);
    }
  }

  Future<void> stop() async {
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
      _position = Duration.zero;
    });
  }
}
