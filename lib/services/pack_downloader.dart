import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'inaturalist_service.dart';
import 'server_media_service.dart';
import 'xeno_canto_service.dart';
import 'wikimedia_service.dart';

enum DownloadStatus { success, skipped, failed }

/// 物种清单条目
class SpeciesEntry {
  final String cn; // 中文名
  final String en; // 英文名
  final String sci; // 学名
  final String cons; // 保护等级: "1" | "2" | ""
  final String habitat;

  const SpeciesEntry({
    required this.cn,
    required this.en,
    required this.sci,
    this.cons = '',
    this.habitat = '',
  });

  factory SpeciesEntry.fromJson(Map<String, dynamic> json) {
    return SpeciesEntry(
      cn: json['cn'] as String? ?? '',
      en: json['en'] as String? ?? '',
      sci: json['sci'] as String? ?? '',
      cons: json['cons'] as String? ?? '',
      habitat: json['habitat'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'cn': cn,
        'en': en,
        'sci': sci,
        if (cons.isNotEmpty) 'cons': cons,
        if (habitat.isNotEmpty) 'habitat': habitat,
      };
}

/// 单个物种的下载结果
class DownloadResult {
  final SpeciesEntry species;
  final DownloadStatus status;
  final String? error;
  final int audioCount;
  final bool hasImage;

  const DownloadResult({
    required this.species,
    required this.status,
    this.error,
    this.audioCount = 0,
    this.hasImage = false,
  });

  bool get success => status == DownloadStatus.success;
  bool get skipped => status == DownloadStatus.skipped;
  bool get failed => status == DownloadStatus.failed;
}

/// 数据包批量下载器
/// 接收物种清单，自动从 Xeno-Canto 下载音频、从 Wikimedia 下载图片，
/// 生成符合 bird_flashcard 格式的数据包
class PackDownloader {
  final XenoCantoService xcService;
  final WikimediaService wikimediaService;

  /// 下载进度回调: (已完成数量, 总数量, 当前物种名)
  void Function(int current, int total, String speciesName)? onProgress;

  /// 单个物种下载完成回调
  void Function(DownloadResult result)? onSpeciesComplete;

  PackDownloader({
    required this.xcService,
    required this.wikimediaService,
    this.onProgress,
    this.onSpeciesComplete,
  });

  /// 从物种清单创建数据包
  /// 返回数据包目录路径
  Future<String> createPack({
    required List<SpeciesEntry> speciesList,
    required String packName,
    String region = '',
  }) async {
    final docDir = await getApplicationDocumentsDirectory();
    final packDir = '${docDir.path}/packs/$packName';

    // 创建目录结构
    final soundsDir = Directory('$packDir/sounds');
    final imagesDir = Directory('$packDir/images');
    await soundsDir.create(recursive: true);
    await imagesDir.create(recursive: true);

    final total = speciesList.length;
    var completed = 0;
    var totalAudio = 0;
    var totalImage = 0;
    final speciesData = <Map<String, dynamic>>[];

    for (final entry in speciesList) {
      onProgress?.call(completed, total, entry.cn);

      DownloadResult result;
      try {
        result = await _downloadSpecies(entry, soundsDir.path, imagesDir.path);
      } catch (e) {
        result = DownloadResult(
          species: entry,
          status: DownloadStatus.failed,
          error: e.toString(),
        );
      }

      totalAudio += result.audioCount;
      if (result.hasImage) totalImage++;

      // 即使部分失败也加入数据包（只是音频/图片可能为空）
      speciesData.add(_buildSpeciesJson(entry, result));
      completed++;

      onSpeciesComplete?.call(result);
    }

    // 写入 species.json
    final speciesJson = jsonEncode(speciesData);
    await File('$packDir/species.json').writeAsString(speciesJson);

    // 写入 manifest.json
    final manifest = {
      'name': packName,
      'region': region,
      'version': '1.0',
      'created': DateTime.now().toIso8601String().split('T').first,
      'species_count': speciesList.length,
      'audio_count': totalAudio,
      'image_count': totalImage,
      'source': 'Xeno-Canto + Wikimedia Commons',
    };
    await File('$packDir/manifest.json').writeAsString(jsonEncode(manifest));

    return packDir;
  }

  /// 下载单个物种的音频和图片
  Future<DownloadResult> _downloadSpecies(
    SpeciesEntry entry,
    String soundsDir,
    String imagesDir,
  ) async {
    // 1. 搜索 Xeno-Canto 录音
    List<XCRecording> recordings;
    try {
      recordings = await xcService.searchBySpecies(entry.sci);
    } catch (e) {
      return DownloadResult(
        species: entry,
        status: DownloadStatus.failed,
        error: 'XC搜索失败: $e',
      );
    }

    // 受限物种检查
    if (recordings.isEmpty) {
      return DownloadResult(
        species: entry,
        status: DownloadStatus.failed,
        error: '受限物种或无录音',
      );
    }

    // 2. 选择最佳录音并下载
    final best = xcService.pickBestRecordings(recordings);
    final audioFiles = <Map<String, String>>[];
    int audioCount = 0;

    // 下载 song
    final songRec = best['song'];
    if (songRec != null) {
      final path = await xcService.downloadAudio(songRec, soundsDir);
      if (path != null) {
        audioFiles.add({
          'type': 'song',
          'file': 'sounds/${path.split('/').last}',
        });
        audioCount++;
      }
    }

    // 下载 call
    final callRec = best['call'];
    if (callRec != null) {
      final path = await xcService.downloadAudio(callRec, soundsDir);
      if (path != null) {
        audioFiles.add({
          'type': 'call',
          'file': 'sounds/${path.split('/').last}',
        });
        audioCount++;
      }
    }

    // 3. 下载图片
    bool hasImage = false;
    try {
      final imageFileName = '${entry.sci.replaceAll(RegExp(r'\s+'), '_')}.jpg';
      final imagePath = await wikimediaService.searchAndDownload(
        entry.sci,
        '$imagesDir/$imageFileName',
      );
      hasImage = imagePath != null;
    } catch (_) {
      // 图片下载失败不影响整体
    }

    return DownloadResult(
      species: entry,
      status: audioCount > 0 ? DownloadStatus.success : DownloadStatus.failed,
      audioCount: audioCount,
      hasImage: hasImage,
    );
  }

  /// 构建物种 JSON 数据
  Map<String, dynamic> _buildSpeciesJson(
    SpeciesEntry entry,
    DownloadResult result,
  ) {
    // 音频列表
    final audios = <Map<String, String>>[];
    // 我们需要重新读取下载的文件来确定文件名
    // 但为了简化，在这里构建路径
    final sciSlug = entry.sci.replaceAll(RegExp(r'\s+'), '_');

    // 尝试读取已有的音频文件
    // 这里用 result 中的信息来构建
    return {
      'cn': entry.cn,
      'en': entry.en,
      'sci': entry.sci,
      if (entry.cons.isNotEmpty) 'cons': entry.cons,
      if (entry.habitat.isNotEmpty) 'habitat': entry.habitat,
      'audios': audios,
      if (result.hasImage) 'image': 'images/$sciSlug.jpg',
    };
  }
}

/// 改进版：直接在下载时记录音频文件名
class PackDownloaderV2 {
  final XenoCantoService xcService;
  final WikimediaService wikimediaService;
  final INaturalistService iNaturalistService;
  final ServerMediaService serverMediaService;
  final bool allowApiFallback;

  void Function(int current, int total, String speciesName)? onProgress;
  void Function(DownloadResult result)? onSpeciesComplete;

  PackDownloaderV2({
    required this.xcService,
    required this.wikimediaService,
    INaturalistService? iNaturalistService,
    ServerMediaService? serverMediaService,
    this.allowApiFallback = true,
    this.onProgress,
    this.onSpeciesComplete,
  })  : iNaturalistService = iNaturalistService ?? INaturalistService(),
        serverMediaService = serverMediaService ?? ServerMediaService();

  /// 从物种清单创建数据包
  Future<String> createPack({
    required List<SpeciesEntry> speciesList,
    required String packName,
    String region = '',
  }) async {
    final docDir = await getApplicationDocumentsDirectory();
    final packDir = '${docDir.path}/packs/$packName';
    await Directory(packDir).create(recursive: true);

    final soundsDir = Directory('$packDir/sounds');
    final imagesDir = Directory('$packDir/images');
    await soundsDir.create(recursive: true);
    await imagesDir.create(recursive: true);

    final requestedSciSet = speciesList
        .map((entry) => entry.sci.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    final existingSpeciesData =
        await _loadExistingSpeciesData(packDir, requestedSciSet);
    final speciesBySci = <String, Map<String, dynamic>>{
      for (final item in existingSpeciesData)
        ((item['sci'] as String?) ?? '').trim().toLowerCase(): item,
    };

    final total = speciesList.length;
    var completed = speciesBySci.length;
    final speciesData = [...existingSpeciesData];
    var totalAudio = speciesData.fold<int>(
      0,
      (sum, item) => sum + ((item['audios'] as List<dynamic>?)?.length ?? 0),
    );
    var totalImage = speciesData.where((item) => item['image'] != null).length;

    for (final entry in speciesList) {
      final sciKey = entry.sci.trim().toLowerCase();
      final existing = speciesBySci[sciKey];
      onProgress?.call(completed, total, entry.cn);

      if (existing != null &&
          (((existing['audios'] as List<dynamic>?)?.isNotEmpty ?? false) ||
              ((existing['image'] as String?)?.isNotEmpty ?? false))) {
        onSpeciesComplete?.call(
          DownloadResult(
            species: entry,
            status: DownloadStatus.skipped,
            audioCount: (existing['audios'] as List<dynamic>?)?.length ?? 0,
            hasImage: existing['image'] != null,
          ),
        );
        completed++;
        continue;
      }

      DownloadResult result;
      Map<String, dynamic> speciesJson;
      try {
        final r =
            await _downloadSpeciesV2(entry, soundsDir.path, imagesDir.path);
        result = r.result;
        speciesJson = r.json;
      } catch (e) {
        result = DownloadResult(
          species: entry,
          status: DownloadStatus.failed,
          error: e.toString(),
        );
        speciesJson = {
          'cn': entry.cn,
          'en': entry.en,
          'sci': entry.sci,
          'audios': [],
        };
      }

      // 服务器媒体库可能只有图片；图片题和学习模式也可以使用。
      if (result.audioCount > 0 || result.hasImage) {
        totalAudio += result.audioCount;
        if (result.hasImage) totalImage++;
        if (existing != null) {
          speciesData.remove(existing);
        }
        speciesData.add(speciesJson);
        speciesBySci[sciKey] = speciesJson;
        completed++;
        await _writeProgressFiles(
          packDir: packDir,
          speciesData: speciesData,
          region: region,
          packName: packName,
          totalAudio: totalAudio,
          totalImage: totalImage,
        );
      }
      completed++;
      onSpeciesComplete?.call(result);
    }

    // 如果全部失败，抛出异常
    if (speciesData.isEmpty) {
      throw Exception('所有物种下载均失败，无法创建数据包');
    }

    await _writeProgressFiles(
      packDir: packDir,
      speciesData: speciesData,
      region: region,
      packName: packName,
      totalAudio: totalAudio,
      totalImage: totalImage,
    );

    return packDir;
  }

  Future<List<Map<String, dynamic>>> _loadExistingSpeciesData(
    String packDir,
    Set<String> requestedSciSet,
  ) async {
    final speciesFile = File('$packDir/species.json');
    if (!await speciesFile.exists()) return [];

    try {
      final raw = await speciesFile.readAsString();
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => Map<String, dynamic>.from(item as Map))
          .where((item) {
        final sci = ((item['sci'] as String?) ?? '').trim().toLowerCase();
        return requestedSciSet.contains(sci);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeProgressFiles({
    required String packDir,
    required List<Map<String, dynamic>> speciesData,
    required String region,
    required String packName,
    required int totalAudio,
    required int totalImage,
  }) async {
    await File('$packDir/species.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(speciesData));

    final manifestV2 = {
      'name': packName,
      'region': region,
      'version': '1.0',
      'created': DateTime.now().toIso8601String().split('T').first,
      'species_count': speciesData.length,
      'audio_count': totalAudio,
      'image_count': totalImage,
      'source': 'Xeno-Canto + iNaturalist + Wikimedia Commons',
    };
    await File('$packDir/manifest.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(manifestV2));
  }

  Future<_SpeciesDownload> _downloadSpeciesV2(
    SpeciesEntry entry,
    String soundsDir,
    String imagesDir,
  ) async {
    try {
      final serverDownload = await serverMediaService.downloadSpecies(
        cn: entry.cn,
        en: entry.en,
        sci: entry.sci,
        cons: entry.cons,
        habitat: entry.habitat,
        soundsDir: soundsDir,
        imagesDir: imagesDir,
      );
      if (serverDownload != null) {
        return _SpeciesDownload(
          result: DownloadResult(
            species: entry,
            status: DownloadStatus.success,
            audioCount: serverDownload.audioCount,
            hasImage: serverDownload.hasImage,
          ),
          json: serverDownload.json,
        );
      }
    } catch (_) {
      // 服务器媒体库不可用时，继续尝试原来的第三方来源。
    }

    if (!allowApiFallback) {
      return _SpeciesDownload(
        result: DownloadResult(
          species: entry,
          status: DownloadStatus.failed,
          error: '服务器暂无该物种媒体',
        ),
        json: {
          'cn': entry.cn,
          'en': entry.en,
          'sci': entry.sci,
          if (entry.cons.isNotEmpty) 'cons': entry.cons,
          if (entry.habitat.isNotEmpty) 'habitat': entry.habitat,
          'audios': [],
        },
      );
    }

    final audioEntries = <Map<String, String>>[];
    int audioCount = 0;

    // 搜索并下载 XC 音频；失败时仍继续尝试图片来源。
    try {
      final recordings = await xcService.searchBySpecies(entry.sci);
      final best = xcService.pickBestRecordings(recordings);

      final songRec = best['song'];
      if (songRec != null) {
        final path = await xcService.downloadAudio(songRec, soundsDir);
        if (path != null) {
          audioEntries.add({
            'type': 'song',
            'file': 'sounds/${path.split('/').last}',
            if (songRec.rec.trim().isNotEmpty) 'contributor': songRec.rec,
            if (songRec.id.trim().isNotEmpty)
              'contributor_url': 'https://xeno-canto.org/${songRec.id}',
            if (songRec.license.trim().isNotEmpty) 'license': songRec.license,
          });
          audioCount++;
        }
      }

      final callRec = best['call'];
      if (callRec != null) {
        final path = await xcService.downloadAudio(callRec, soundsDir);
        if (path != null) {
          audioEntries.add({
            'type': 'call',
            'file': 'sounds/${path.split('/').last}',
            if (callRec.rec.trim().isNotEmpty) 'contributor': callRec.rec,
            if (callRec.id.trim().isNotEmpty)
              'contributor_url': 'https://xeno-canto.org/${callRec.id}',
            if (callRec.license.trim().isNotEmpty) 'license': callRec.license,
          });
          audioCount++;
        }
      }
    } catch (_) {}

    // 下载图片
    bool hasImage = false;
    String imageCredit = '';
    final sciSlug = entry.sci.replaceAll(RegExp(r'\s+'), '_');
    try {
      final photo = await iNaturalistService.searchAndDownload(
        entry.sci,
        '$imagesDir/$sciSlug.jpg',
      );
      if (photo != null) {
        hasImage = true;
        imageCredit = photo.attribution;
      }
    } catch (_) {}

    if (!hasImage) {
      try {
        final imagePath = await wikimediaService.searchAndDownload(
          entry.sci,
          '$imagesDir/$sciSlug.jpg',
        );
        hasImage = imagePath != null;
        if (hasImage) imageCredit = 'Wikimedia Commons';
      } catch (_) {}
    }

    final audioCredit = audioEntries
        .map((item) => (item['contributor'] ?? '').trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .join(', ');

    return _SpeciesDownload(
      result: DownloadResult(
        species: entry,
        status: audioCount > 0 || hasImage
            ? DownloadStatus.success
            : DownloadStatus.failed,
        error: audioCount > 0 || hasImage ? null : '无可用音频或图片',
        audioCount: audioCount,
        hasImage: hasImage,
      ),
      json: {
        'cn': entry.cn,
        'en': entry.en,
        'sci': entry.sci,
        if (entry.cons.isNotEmpty) 'cons': entry.cons,
        if (entry.habitat.isNotEmpty) 'habitat': entry.habitat,
        'audios': audioEntries,
        if (hasImage) 'image': 'images/$sciSlug.jpg',
        if (imageCredit.isNotEmpty) 'image_credit': imageCredit,
        if (audioCredit.isNotEmpty) 'audio_credit': audioCredit,
      },
    );
  }
}

class _SpeciesDownload {
  final DownloadResult result;
  final Map<String, dynamic> json;
  const _SpeciesDownload({required this.result, required this.json});
}
