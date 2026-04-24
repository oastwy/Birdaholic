import 'package:audioplayers/audioplayers.dart';

/// 音频播放服务
/// 单例模式，全局管理播放状态
class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._();

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  String? _currentPath;

  bool get isPlaying => _isPlaying;
  String? get currentPath => _currentPath;

  /// 播放本地音频文件
  Future<void> play(String filePath) async {
    try {
      _currentPath = filePath;
      await _player.setSource(DeviceFileSource(filePath));
      await _player.resume();
      _isPlaying = true;

      // 播放结束回调
      _player.onPlayerComplete.listen((_) {
        _isPlaying = false;
      });
    } catch (e) {
      _isPlaying = false;
      rethrow;
    }
  }

  /// 停止播放
  Future<void> stop() async {
    await _player.stop();
    _isPlaying = false;
  }

  /// 暂停
  Future<void> pause() async {
    await _player.pause();
    _isPlaying = false;
  }

  /// 恢复播放
  Future<void> resume() async {
    await _player.resume();
    _isPlaying = true;
  }

  /// 释放资源
  void dispose() {
    _player.dispose();
  }
}
