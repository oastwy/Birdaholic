import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/pack_downloader.dart';
import 'pack_manager.dart';
import 'storage.dart';
import 'wikimedia_service.dart';
import 'xeno_canto_service.dart';

enum DownloadTaskStatus { idle, running, completed, failed }

class DownloadTaskSnapshot {
  final DownloadTaskStatus status;
  final String packName;
  final int current;
  final int total;
  final String currentSpecies;
  final List<DownloadResult> results;
  final String? message;

  const DownloadTaskSnapshot({
    this.status = DownloadTaskStatus.idle,
    this.packName = '',
    this.current = 0,
    this.total = 0,
    this.currentSpecies = '',
    this.results = const [],
    this.message,
  });

  bool get isRunning => status == DownloadTaskStatus.running;
  bool get isFinished =>
      status == DownloadTaskStatus.completed || status == DownloadTaskStatus.failed;

  int get successCount => results.where((result) => result.success).length;
  int get skippedCount => results.where((result) => result.skipped).length;
  int get failedCount => results.where((result) => result.failed).length;

  double get progress => total == 0 ? 0 : current / total;

  DownloadTaskSnapshot copyWith({
    DownloadTaskStatus? status,
    String? packName,
    int? current,
    int? total,
    String? currentSpecies,
    List<DownloadResult>? results,
    String? message,
  }) {
    return DownloadTaskSnapshot(
      status: status ?? this.status,
      packName: packName ?? this.packName,
      current: current ?? this.current,
      total: total ?? this.total,
      currentSpecies: currentSpecies ?? this.currentSpecies,
      results: results ?? this.results,
      message: message,
    );
  }
}

class DownloadTaskService extends ChangeNotifier {
  DownloadTaskService._();

  static final DownloadTaskService instance = DownloadTaskService._();

  DownloadTaskSnapshot _snapshot = const DownloadTaskSnapshot();
  DownloadTaskSnapshot get snapshot => _snapshot;

  Future<void>? _runningTask;

  bool get isRunning => _snapshot.isRunning;

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
    VoidCallback? onPackActivated,
  }) {
    if (_runningTask != null) return false;

    final apiKey = storage.getXenoCantoApiKey();
    if (apiKey.isEmpty) {
      throw Exception('请先填写 Xeno-Canto API key');
    }

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
      apiKey: apiKey,
      packManager: packManager,
      onPackActivated: onPackActivated,
    );
    return true;
  }

  Future<void> _run({
    required List<SpeciesEntry> speciesList,
    required String packName,
    required String region,
    required String apiKey,
    required PackManager packManager,
    VoidCallback? onPackActivated,
  }) async {
    final xc = XenoCantoService(apiKey: apiKey);
    final wm = WikimediaService();
    final downloader = PackDownloaderV2(
      xcService: xc,
      wikimediaService: wm,
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
    );

    try {
      final packDir = await downloader.createPack(
        speciesList: speciesList,
        packName: packName,
        region: region,
      );
      await packManager.setActivePack(packDir);
      onPackActivated?.call();

      final hasSuccess = _snapshot.successCount > 0 || _snapshot.skippedCount > 0;
      _snapshot = _snapshot.copyWith(
        status: hasSuccess ? DownloadTaskStatus.completed : DownloadTaskStatus.failed,
        current: _snapshot.total,
        message: hasSuccess
            ? '下载完成：成功 ${_snapshot.successCount}，跳过 ${_snapshot.skippedCount}，失败 ${_snapshot.failedCount}'
            : '下载失败，请检查物种学名、网络和 API key',
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
    }
  }
}
