import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/pack_downloader.dart';
import 'download_cancel.dart';
import 'pack_manager.dart';
import 'storage.dart';
import 'wikimedia_service.dart';
import 'xeno_canto_service.dart';

enum DownloadTaskStatus { idle, running, completed, failed, canceled }

enum DownloadTaskKind { speciesPack, remotePack }

class DownloadTaskSnapshot {
  final DownloadTaskStatus status;
  final String packName;
  final int current;
  final int total;
  final String currentSpecies;
  final List<DownloadResult> results;
  final String? message;
  final DownloadTaskKind kind;
  final int bytesReceived;
  final int bytesTotal;
  final double bytesPerSecond;
  final String statusMessage;

  const DownloadTaskSnapshot({
    this.status = DownloadTaskStatus.idle,
    this.packName = '',
    this.current = 0,
    this.total = 0,
    this.currentSpecies = '',
    this.results = const [],
    this.message,
    this.kind = DownloadTaskKind.speciesPack,
    this.bytesReceived = 0,
    this.bytesTotal = 0,
    this.bytesPerSecond = 0,
    this.statusMessage = '',
  });

  bool get isRunning => status == DownloadTaskStatus.running;
  bool get isFinished =>
      status == DownloadTaskStatus.completed ||
      status == DownloadTaskStatus.failed ||
      status == DownloadTaskStatus.canceled;

  int get successCount => results.where((result) => result.success).length;
  int get skippedCount => results.where((result) => result.skipped).length;
  int get failedCount => results.where((result) => result.failed).length;

  double get progress {
    if (kind == DownloadTaskKind.remotePack) {
      return bytesTotal == 0 ? 0 : bytesReceived / bytesTotal;
    }
    return total == 0 ? 0 : current / total;
  }

  String get speedLabel {
    if (bytesPerSecond <= 0) return '';
    return '${_formatBytes(bytesPerSecond.round())}/s';
  }

  String get etaLabel {
    if (bytesPerSecond <= 0 || bytesTotal <= 0) return '';
    final remaining = bytesTotal - bytesReceived;
    if (remaining <= 0) return '马上完成';
    final seconds = (remaining / bytesPerSecond).ceil();
    if (seconds < 60) return '约 ${seconds}s';
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    if (minutes < 60) {
      return rest == 0 ? '约 ${minutes}m' : '约 ${minutes}m ${rest}s';
    }
    final hours = minutes ~/ 60;
    return '约 ${hours}h ${minutes % 60}m';
  }

  String get byteProgressLabel {
    if (bytesTotal <= 0) return _formatBytes(bytesReceived);
    return '${_formatBytes(bytesReceived)} / ${_formatBytes(bytesTotal)}';
  }

  String get speciesProgressLabel {
    if (kind == DownloadTaskKind.remotePack) return byteProgressLabel;
    if (total <= 0) return '准备中';
    final done = current.clamp(0, total);
    return '$done/$total 种';
  }

  static String _formatBytes(int value) {
    if (value >= 1024 * 1024 * 1024) {
      return '${(value / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
    }
    if (value >= 1024 * 1024) {
      return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (value >= 1024) {
      return '${(value / 1024).toStringAsFixed(0)} KB';
    }
    return '$value B';
  }

  DownloadTaskSnapshot copyWith({
    DownloadTaskStatus? status,
    String? packName,
    int? current,
    int? total,
    String? currentSpecies,
    List<DownloadResult>? results,
    String? message,
    DownloadTaskKind? kind,
    int? bytesReceived,
    int? bytesTotal,
    double? bytesPerSecond,
    String? statusMessage,
  }) {
    return DownloadTaskSnapshot(
      status: status ?? this.status,
      packName: packName ?? this.packName,
      current: current ?? this.current,
      total: total ?? this.total,
      currentSpecies: currentSpecies ?? this.currentSpecies,
      results: results ?? this.results,
      message: message,
      kind: kind ?? this.kind,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      bytesTotal: bytesTotal ?? this.bytesTotal,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

class DownloadTaskService extends ChangeNotifier {
  DownloadTaskService._();

  static final DownloadTaskService instance = DownloadTaskService._();

  DownloadTaskSnapshot _snapshot = const DownloadTaskSnapshot();
  DownloadTaskSnapshot get snapshot => _snapshot;

  Future<void>? _runningTask;
  bool _cancelRequested = false;

  bool get isRunning => _snapshot.isRunning;

  bool get hasActiveOrFinishedTask =>
      _snapshot.isRunning || _snapshot.isFinished;

  void cancel() {
    if (!isRunning) return;
    _cancelRequested = true;
    _snapshot = _snapshot.copyWith(statusMessage: '正在取消…');
    notifyListeners();
  }

  void clearFinished() {
    if (!_snapshot.isFinished) return;
    _snapshot = const DownloadTaskSnapshot();
    notifyListeners();
  }

  bool start({
    required List<SpeciesEntry> speciesList,
    required String packName,
    required String region,
    required PackManager packManager,
    required StorageService storage,
    bool allowApiFallback = true,
    VoidCallback? onPackActivated,
  }) {
    if (_runningTask != null) return false;
    _cancelRequested = false;

    _snapshot = DownloadTaskSnapshot(
      status: DownloadTaskStatus.running,
      packName: packName,
      total: speciesList.length,
      results: const [],
      message: null,
    );
    notifyListeners();

    _runningTask = _run(
      speciesList: speciesList,
      packName: packName,
      region: region,
      apiKey: allowApiFallback ? storage.getXenoCantoApiKey() : '',
      packManager: packManager,
      allowApiFallback: allowApiFallback,
      onPackActivated: onPackActivated,
      shouldCancel: () => _cancelRequested,
    );
    return true;
  }

  bool startRemotePack({
    required RemotePackInfo info,
    required PackManager packManager,
    VoidCallback? onPackActivated,
  }) {
    if (_runningTask != null) return false;
    _cancelRequested = false;

    final startedAt = DateTime.now();
    _snapshot = DownloadTaskSnapshot(
      status: DownloadTaskStatus.running,
      kind: DownloadTaskKind.remotePack,
      packName: info.label,
      bytesTotal: info.sizeBytes,
      message: null,
    );
    notifyListeners();

    _runningTask = _runRemotePack(
      info: info,
      packManager: packManager,
      startedAt: startedAt,
      onPackActivated: onPackActivated,
      shouldCancel: () => _cancelRequested,
    );
    return true;
  }

  Future<void> _runRemotePack({
    required RemotePackInfo info,
    required PackManager packManager,
    required DateTime startedAt,
    VoidCallback? onPackActivated,
    required bool Function() shouldCancel,
  }) async {
    try {
      final pack = await packManager.downloadAndInstallRemotePack(
        info,
        shouldCancel: shouldCancel,
        onProgress: (received, total) {
          final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
          final speed = elapsedMs <= 0 ? 0.0 : received * 1000 / elapsedMs;
          _snapshot = _snapshot.copyWith(
            bytesReceived: received,
            bytesTotal: total,
            bytesPerSecond: speed,
          );
          notifyListeners();
        },
        onStatus: (msg) {
          _snapshot = _snapshot.copyWith(statusMessage: msg);
          notifyListeners();
        },
      );
      onPackActivated?.call();
      _snapshot = _snapshot.copyWith(
        status: DownloadTaskStatus.completed,
        bytesReceived: _snapshot.bytesTotal,
        message:
            '已安装「${pack.name}」：${pack.speciesCount} 种鸟 · ${pack.audioCount} 音频 · ${pack.imageCount} 张图',
      );
      notifyListeners();
    } on DownloadCanceledException {
      _snapshot = _snapshot.copyWith(
        status: DownloadTaskStatus.canceled,
        message: '已取消下载，可稍后重新开始并续传。',
        statusMessage: '已取消',
      );
      notifyListeners();
    } catch (e) {
      _snapshot = _snapshot.copyWith(
        status: DownloadTaskStatus.failed,
        message: '下载失败: $e',
      );
      notifyListeners();
    } finally {
      _runningTask = null;
      _cancelRequested = false;
    }
  }

  Future<void> _run({
    required List<SpeciesEntry> speciesList,
    required String packName,
    required String region,
    required String apiKey,
    required PackManager packManager,
    required bool allowApiFallback,
    VoidCallback? onPackActivated,
    required bool Function() shouldCancel,
  }) async {
    final xc = XenoCantoService(apiKey: apiKey);
    final wm = WikimediaService();
    final downloader = PackDownloaderV2(
      xcService: xc,
      wikimediaService: wm,
      allowApiFallback: allowApiFallback,
      onProgress: (current, total, name) {
        _snapshot = _snapshot.copyWith(
          current: current,
          total: total,
          currentSpecies: name,
        );
        notifyListeners();
      },
      onSpeciesComplete: (result) {
        _snapshot = _snapshot.copyWith(
          results: [..._snapshot.results, result],
        );
        notifyListeners();
      },
      shouldCancel: shouldCancel,
    );

    try {
      final packDir = await downloader.createPack(
        speciesList: speciesList,
        packName: packName,
        region: region,
      );
      await packManager.setActivePack(packDir);
      onPackActivated?.call();

      final hasSuccess =
          _snapshot.successCount > 0 || _snapshot.skippedCount > 0;
      _snapshot = _snapshot.copyWith(
        status: hasSuccess
            ? DownloadTaskStatus.completed
            : DownloadTaskStatus.failed,
        current: _snapshot.total,
        message: hasSuccess
            ? '服务器下载完成：成功 ${_snapshot.successCount}，跳过 ${_snapshot.skippedCount}，失败 ${_snapshot.failedCount}'
            : allowApiFallback
                ? '下载失败，请检查物种学名、网络和 API key'
                : '服务器暂无这些物种的数据，或网络连接失败',
      );
      notifyListeners();
    } on DownloadCanceledException {
      _snapshot = _snapshot.copyWith(
        status: DownloadTaskStatus.canceled,
        current: _snapshot.current,
        message: '已取消下载，已完成的物种会保留。',
        statusMessage: '已取消',
      );
      notifyListeners();
    } catch (e) {
      _snapshot = _snapshot.copyWith(
        status: DownloadTaskStatus.failed,
        message: '下载失败: $e',
      );
      notifyListeners();
    } finally {
      _runningTask = null;
      _cancelRequested = false;
    }
  }
}
