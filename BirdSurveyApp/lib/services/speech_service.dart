import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// App-wide singleton. Android allows only one SpeechToText session at a time.
/// Using a cached Future ensures every caller waits for the same init result
/// instead of racing to initialize separate instances.
class SpeechService {
  SpeechService._();
  static final SpeechService instance = SpeechService._();

  final SpeechToText speech = SpeechToText();
  bool available = false;
  String failReason = '';
  Future<bool>? _initFuture;

  Future<bool> init() {
    _initFuture ??= _doInit();
    return _initFuture!;
  }

  /// Call this when the user taps the mic button — requests permission if
  /// denied and retries init so the user gets one prompt instead of a
  /// silent failure.
  Future<bool> requestAndInit() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      failReason = status.isPermanentlyDenied ? '请在系统设置中开启麦克风权限' : '麦克风权限被拒绝';
      return false;
    }
    // Reset cached future so we retry after permission is granted.
    _initFuture = null;
    return init();
  }

  Future<bool> _doInit() async {
    final status = await Permission.microphone.status;
    if (!status.isGranted) {
      failReason = '需要麦克风权限';
      available = false;
      return false;
    }
    available = await speech.initialize(
      onError: (e) { failReason = e.errorMsg; },
      onStatus: (_) {},
    );
    if (!available) failReason = '语音识别初始化失败';
    return available;
  }
}
