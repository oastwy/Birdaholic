import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

class FilePickerGuard {
  static const _staleAfter = Duration(minutes: 5);
  static const _pickerTimeout = Duration(minutes: 5);
  static const _nativeCooldown = Duration(milliseconds: 900);

  static bool _busy = false;
  static DateTime? _busySince;
  static DateTime? _cooldownUntil;
  static Timer? _staleTimer;

  static void forceReset({bool cooldown = true}) {
    _staleTimer?.cancel();
    _staleTimer = null;
    _busy = false;
    _busySince = null;
    if (cooldown) {
      _cooldownUntil = DateTime.now().add(_nativeCooldown);
    }
  }

  static void _releaseIfStale() {
    final since = _busySince;
    if (!_busy || since == null) return;
    if (DateTime.now().difference(since) >= _staleAfter) {
      forceReset();
    }
  }

  static void _armStaleTimer() {
    _staleTimer?.cancel();
    _staleTimer = Timer(_staleAfter, () => forceReset());
  }

  static bool _isMultipleRequest(Object error) {
    if (error is PlatformException && error.code == 'multiple_request') {
      return true;
    }
    return error.toString().contains('multiple_request');
  }

  static Future<void> _waitForCooldown() async {
    final until = _cooldownUntil;
    if (until == null) return;
    final wait = until.difference(DateTime.now());
    if (wait.isNegative || wait == Duration.zero) {
      _cooldownUntil = null;
      return;
    }
    await Future<void>.delayed(wait);
    _cooldownUntil = null;
  }

  static Future<FilePickerResult?> _invokePicker({
    required FileType type,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
  }) {
    return FilePicker.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
    ).timeout(_pickerTimeout);
  }

  static Future<FilePickerResult?> pickFiles({
    required FileType type,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      await _waitForCooldown();
      _releaseIfStale();
      if (_busy) {
        return null;
      }
      _busy = true;
      _busySince = DateTime.now();
      _armStaleTimer();
      try {
        return await _invokePicker(
          type: type,
          allowedExtensions: allowedExtensions,
          allowMultiple: allowMultiple,
        );
      } on TimeoutException {
        forceReset();
        throw const FilePickerTimeoutException();
      } catch (e) {
        if (_isMultipleRequest(e)) {
          forceReset();
          if (attempt == 0) {
            await Future<void>.delayed(
              Duration(milliseconds: _nativeCooldown.inMilliseconds * 2),
            );
            continue;
          }
          return null;
        }
        rethrow;
      } finally {
        // iOS may still be dismissing UIDocumentPicker/UIImagePicker when the
        // Future completes; a short delay prevents the next picker from racing it.
        await Future<void>.delayed(const Duration(milliseconds: 450));
        forceReset();
      }
    }
    return null;
  }
}

class FilePickerBusyException implements Exception {
  const FilePickerBusyException();

  @override
  String toString() => '文件选择器正在打开，请稍等一下再试';
}

class FilePickerTimeoutException implements Exception {
  const FilePickerTimeoutException();

  @override
  String toString() => '文件选择器响应超时，请重新打开';
}
