import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/data_pack.dart';
import '../models/species.dart';
import 'server_media_service.dart';

/// 内置数据包描述
class BuiltinPackInfo {
  final String assetPath;
  final String dirName;
  final String label;
  final String description;
  const BuiltinPackInfo({
    required this.assetPath,
    required this.dirName,
    required this.label,
    required this.description,
  });
}

/// 服务器远程数据包描述
class RemotePackInfo {
  final String url;
  final String dirName;
  final String label;
  final String description;
  final int sizeBytes;

  const RemotePackInfo({
    required this.url,
    required this.dirName,
    required this.label,
    required this.description,
    required this.sizeBytes,
  });

  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
    }
    return '${(sizeBytes / 1024 / 1024).round()} MB';
  }
}

/// 数据包管理服务（原生 Android/iOS）
class PackManager {
  static const _activePackKey = 'active_pack_dir';
  static const _builtinInstalledKey = 'builtin_pack_installed';
  static Future<Map<String, _SpeciesNameTaxonomy>>? _taxonomyIndexFuture;

  /// 内置小包随 App 发布；大包通过服务器下载
  static const builtinPacks = [
    BuiltinPackInfo(
      assetPath: 'data_packs/brisbane_v1.0_opt.zip',
      dirName: 'brisbane_v1',
      label: '布里斯班包 v1.0（50种）',
      description: '50种鸟 · 澳大利亚东南部 · 86 MB',
    ),
  ];

  /// 服务器可下载数据包（备案通过后可换为域名）
  static const remotePacks = [
    RemotePackInfo(
      url: 'http://124.223.101.188:8080/packs/brisbane_v1.0_opt.zip',
      dirName: 'brisbane_v1',
      label: '布里斯班包 v1.0（50种）',
      description: '50种鸟 · 澳大利亚东南部',
      sizeBytes: 90177536,
    ),
    RemotePackInfo(
      url: 'http://124.223.101.188:8080/packs/china_birds_v1.0_opt.zip',
      dirName: 'china_birds_v1',
      label: '全国鸟类包 v1.0（1519种）',
      description: '1519种鸟 · 中国全鸟种',
      sizeBytes: 538968064,
    ),
  ];

  /// 获取当前激活的数据包目录
  Future<String?> getActivePackDir() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activePackKey);
  }

  /// 设置当前激活的数据包
  Future<void> setActivePack(String packDir) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activePackKey, packDir);
  }

  Future<void> ensureBuiltinPackInstalled() async {
    // 不再自动安装内置包，保留接口兼容性。
    return;
  }

  /// 安装内置数据包（流式解压，低内存占用）
  Future<DataPack> installBuiltinPack(BuiltinPackInfo info) async {
    final docDir = await getApplicationDocumentsDirectory();
    final packDir = '${docDir.path}/packs/${info.dirName}';
    final dir = Directory(packDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);

    // 把 asset 写入临时文件，再流式解压（避免大 ZIP 全量占用内存）
    final zipData = await rootBundle.load(info.assetPath);
    final tempDir = await getTemporaryDirectory();
    final tempZip = File('${tempDir.path}/_builtin_install.zip');
    await tempZip.writeAsBytes(zipData.buffer.asUint8List(), flush: true);

    try {
      await extractFileToDisk(tempZip.path, packDir);
    } finally {
      await tempZip.delete().catchError((_) => tempZip);
    }

    final manifestFile = File('$packDir/manifest.json');
    if (!await manifestFile.exists()) {
      throw Exception('内置包缺少 manifest.json（${info.label}）');
    }

    final manifestJson =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_builtinInstalledKey, true);
    await setActivePack(packDir);
    return DataPack.fromJson(manifestJson, packDir);
  }

  /// 兼容旧接口：安装试用包
  Future<DataPack> installBuiltinTrialPack() {
    throw UnsupportedError('当前版本不再内置数据包，请通过 ZIP 导入数据包。');
  }

  // 下载相关常量
  static const _connectTimeout = Duration(seconds: 30);
  static const _streamIdleTimeout = Duration(seconds: 30);
  static const _maxRetries = 4;

  /// 从服务器下载并安装数据包
  ///
  /// 流式下载 + 流式解压，支持：
  /// - 断点续传（Range / .part 文件）
  /// - 30s 连接超时 + 30s 流空闲超时
  /// - 网络错误自动重试（指数退避 2s/4s/8s/16s，最多 4 次）
  /// - 下载完成后大小校验
  Future<DataPack> downloadAndInstallRemotePack(
    RemotePackInfo info, {
    void Function(int received, int total)? onProgress,
    void Function(String message)? onStatus,
  }) async {
    final docDir = await getApplicationDocumentsDirectory();
    final packDir = '${docDir.path}/packs/${info.dirName}';
    final stagingDir = '${docDir.path}/packs/${info.dirName}_installing';
    final downloadDir = Directory('${docDir.path}/downloads');
    await downloadDir.create(recursive: true);
    final tempZip = File('${downloadDir.path}/remote_${info.dirName}.zip.part');

    await WakelockPlus.enable();
    try {
      // ───── Step 1: stream-download with retry ─────
      await _downloadWithRetry(
        url: info.url,
        target: tempZip,
        expectedSize: info.sizeBytes,
        onProgress: onProgress,
        onStatus: onStatus,
      );

      // ───── Step 2: extract to staging ─────
      onStatus?.call('正在解压数据包…');
      final staging = Directory(stagingDir);
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
      await staging.create(recursive: true);

      await extractFileToDisk(tempZip.path, stagingDir);

      // ───── Step 3: atomic replace ─────
      final dir = Directory(packDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      await staging.rename(packDir);
      await tempZip.delete().catchError((_) => tempZip);
    } finally {
      await WakelockPlus.disable();
    }

    final mf = File('$packDir/manifest.json');
    if (!await mf.exists()) throw Exception('安装失败：数据包缺少 manifest.json');
    final pack = DataPack.fromJson(
      jsonDecode(await mf.readAsString()) as Map<String, dynamic>,
      packDir,
    );
    await setActivePack(packDir);
    return pack;
  }

  /// 带重试和超时的流式下载
  ///
  /// 每次重试之间使用指数退避；遇到 404/416 等明确错误立即失败不重试。
  Future<void> _downloadWithRetry({
    required String url,
    required File target,
    required int expectedSize,
    void Function(int received, int total)? onProgress,
    void Function(String message)? onStatus,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        if (attempt == 0) {
          final existing = await target.exists() ? await target.length() : 0;
          if (existing > 0) {
            onStatus?.call(
              '续传中（已下载 ${_humanBytes(existing)}）',
            );
          } else {
            onStatus?.call('正在连接服务器…');
          }
        } else {
          final delaySeconds = 1 << attempt; // 2, 4, 8, 16
          onStatus?.call(
            '网络中断，${delaySeconds}s 后第 ${attempt + 1} 次尝试续传…',
          );
          await Future<void>.delayed(Duration(seconds: delaySeconds));
        }

        await _streamDownloadOnce(
          url: url,
          target: target,
          expectedSize: expectedSize,
          onProgress: onProgress,
          onStatus: onStatus,
        );

        // Final size validation (only if expectedSize known)
        if (expectedSize > 0) {
          final actual = await target.length();
          if (actual < expectedSize) {
            throw _RetryableException(
              '文件不完整：${_humanBytes(actual)} / ${_humanBytes(expectedSize)}',
            );
          }
        }
        return; // success
      } on _NonRetryableException catch (e) {
        // Bubble up immediately (404, parse errors, disk full, etc.)
        throw Exception(e.message);
      } catch (e) {
        lastError = e;
        // Continue to next retry
      }
    }
    final msg =
        lastError is _RetryableException ? lastError.message : '$lastError';
    throw Exception('下载失败（已重试 $_maxRetries 次）: $msg');
  }

  /// 单次流式下载尝试（不重试）
  Future<void> _streamDownloadOnce({
    required String url,
    required File target,
    required int expectedSize,
    void Function(int received, int total)? onProgress,
    void Function(String message)? onStatus,
  }) async {
    final client = http.Client();
    IOSink? sink;
    try {
      var existingBytes = await target.exists() ? await target.length() : 0;
      final request = http.Request('GET', Uri.parse(url));
      if (existingBytes > 0) {
        request.headers['Range'] = 'bytes=$existingBytes-';
      }

      final response = await client.send(request).timeout(
            _connectTimeout,
            onTimeout: () => throw _RetryableException(
              '连接服务器超时（${_connectTimeout.inSeconds}s 无响应）',
            ),
          );

      // 416 means "already have everything"
      if (response.statusCode == 416 &&
          expectedSize > 0 &&
          existingBytes >= expectedSize) {
        onProgress?.call(existingBytes, expectedSize);
        return;
      }

      // Server returned full content despite Range request → restart from 0
      if (response.statusCode == 200 && existingBytes > 0) {
        existingBytes = 0;
        await target.delete().catchError((_) => target);
      }

      if (response.statusCode == 404) {
        throw _NonRetryableException('服务器没有该文件（404）');
      }
      if (response.statusCode == 403) {
        throw _NonRetryableException('服务器拒绝访问（403）');
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw _RetryableException(
          '服务器响应异常: HTTP ${response.statusCode}',
        );
      }

      // Validate Content-Range start matches our resumed offset
      if (response.statusCode == 206) {
        final range = response.headers['content-range'];
        final match = range == null
            ? null
            : RegExp(r'bytes\s+(\d+)-(\d+)/(\d+|\*)').firstMatch(range);
        final rangeStart = match == null ? null : int.tryParse(match.group(1)!);
        if (rangeStart != null && rangeStart != existingBytes) {
          // Server disagrees about our resumed position → start over
          await target.delete().catchError((_) => target);
          throw _RetryableException(
            '服务器返回的 Range 起点不匹配，重新开始下载',
          );
        }
      }

      final contentRangeTotal = _contentRangeTotal(
        response.headers['content-range'],
      );
      final total = response.statusCode == 206
          ? contentRangeTotal ?? existingBytes + (response.contentLength ?? 0)
          : response.contentLength ?? expectedSize;
      var received = existingBytes;
      onProgress?.call(received, total);
      onStatus?.call('正在下载…');

      sink = target.openWrite(
        mode: response.statusCode == 206 ? FileMode.append : FileMode.write,
      );

      // Wrap stream with idle timeout: if no chunk arrives within
      // _streamIdleTimeout, treat as stalled and retry.
      final timedStream = response.stream.timeout(
        _streamIdleTimeout,
        onTimeout: (eventSink) {
          eventSink.addError(_RetryableException(
            '数据流停滞（${_streamIdleTimeout.inSeconds}s 无数据）',
          ));
          eventSink.close();
        },
      );

      await for (final chunk in timedStream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.close();
      sink = null;
    } finally {
      await sink?.close().catchError((_) {});
      client.close();
    }
  }

  String _humanBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  int? _contentRangeTotal(String? contentRange) {
    if (contentRange == null) return null;
    final match = RegExp(r'bytes\s+\d+-\d+/(\d+|\*)').firstMatch(contentRange);
    if (match == null || match.group(1) == '*') return null;
    return int.tryParse(match.group(1)!);
  }

  Future<String> exportPackToDirectory(String packDir, String outputDir) async {
    final sourceDir = Directory(packDir);
    if (!await sourceDir.exists()) {
      throw Exception('数据包目录不存在');
    }

    final manifestFile = File('$packDir/manifest.json');
    if (!await manifestFile.exists()) {
      throw Exception('数据包缺少 manifest.json');
    }

    final manifestJson =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    final packName =
        (manifestJson['name'] as String? ?? sourceDir.uri.pathSegments.last)
            .trim();
    final safeName =
        _sanitizeFileName(packName.isEmpty ? 'bird_pack' : packName);
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final zipPath = '$outputDir/${safeName}_backup_$timestamp.zip';

    final archive = Archive();
    await for (final entity
        in sourceDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relativePath = entity.path.substring('$packDir/'.length);
      archive.addFile(
        ArchiveFile(
          relativePath,
          await entity.length(),
          await entity.readAsBytes(),
        ),
      );
    }

    final zipData = ZipEncoder().encode(archive);

    final outputFile = File(zipPath);
    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsBytes(zipData, flush: true);
    return zipPath;
  }

  /// 导入 ZIP 数据包（传入文件路径）
  Future<DataPack> importPack(String zipPath) async {
    final zipData = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(zipData);

    final packName = zipPath.split('/').last.replaceAll('.zip', '');
    final docDir = await getApplicationDocumentsDirectory();
    final packDir = '${docDir.path}/packs/$packName';

    // 清理旧目录
    final dir = Directory(packDir);
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);

    // 解压
    for (final file in archive) {
      if (!file.isFile) continue;
      final filePath = '$packDir/${file.name}';
      final f = File(filePath);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(file.content as List<int>);
    }

    // 读取 manifest
    final manifestFile = File('$packDir/manifest.json');
    if (!await manifestFile.exists()) throw Exception('数据包缺少 manifest.json');

    final manifestJson =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;

    await prefsSetBuiltinFlagFalse();
    await setActivePack(packDir);
    return DataPack.fromJson(manifestJson, packDir);
  }

  /// 导入多个分包 ZIP 并合并为完整数据包
  ///
  /// 分包由 `packager/split_data_pack.py` 生成，每个 part 的 manifest 含
  /// `part`、`part_count`、`split_from` 字段。本方法会：
  /// 1. 校验所有分包来自同一源、part 编号完整覆盖 1..part_count
  /// 2. 解压所有文件到 staging 目录
  /// 3. 合并 species.json 与 manifest.json
  /// 4. 原子替换并激活合并后的数据包
  Future<DataPack> importMultiPartPack(
    List<String> zipPaths, {
    void Function(int current, int total, String stage)? onProgress,
  }) async {
    if (zipPaths.isEmpty) throw Exception('未选择数据包');

    onProgress?.call(0, zipPaths.length, '正在读取分包清单');

    // Step 1: read manifests of all parts (with archives cached in memory)
    final partInfos = <_PartInfo>[];
    String? splitFrom;
    int? expectedPartCount;

    for (var i = 0; i < zipPaths.length; i++) {
      final path = zipPaths[i];
      final bytes = await File(path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final manifestEntry = archive.findFile('manifest.json');
      if (manifestEntry == null) {
        throw Exception('${path.split('/').last} 缺少 manifest.json');
      }
      final manifest = jsonDecode(
        utf8.decode(manifestEntry.content as List<int>),
      ) as Map<String, dynamic>;

      final part = manifest['part'] as int?;
      final partCount = manifest['part_count'] as int?;
      final from = manifest['split_from'] as String?;

      if (part == null || partCount == null || from == null) {
        throw Exception(
          '${path.split('/').last} 不是分包文件\n'
          '（缺少 part / part_count / split_from 字段，请使用 split_data_pack.py 重新切片）',
        );
      }

      splitFrom ??= from;
      expectedPartCount ??= partCount;

      if (from != splitFrom) {
        throw Exception('分包来源不一致: $from ≠ $splitFrom');
      }
      if (partCount != expectedPartCount) {
        throw Exception('分包总数不一致: $partCount ≠ $expectedPartCount');
      }

      partInfos.add(_PartInfo(
        path: path,
        part: part,
        manifest: manifest,
        archive: archive,
      ));
      onProgress?.call(
          i + 1, zipPaths.length, '校验分包 ${i + 1}/${zipPaths.length}');
    }

    partInfos.sort((a, b) => a.part.compareTo(b.part));

    // Step 2: validate completeness
    final partNumbers = partInfos.map((p) => p.part).toSet();
    final missing = <int>[];
    for (var i = 1; i <= expectedPartCount!; i++) {
      if (!partNumbers.contains(i)) missing.add(i);
    }
    if (missing.isNotEmpty) {
      throw Exception(
        '缺少分包：${missing.join(', ')} / $expectedPartCount\n请选择全部 $expectedPartCount 个分包文件',
      );
    }
    if (partInfos.length != expectedPartCount) {
      throw Exception('分包重复：选中 ${partInfos.length}，期望 $expectedPartCount');
    }

    // Step 3: prepare staging directory
    final packName =
        splitFrom!.replaceAll(RegExp(r'\.zip$', caseSensitive: false), '');
    final docDir = await getApplicationDocumentsDirectory();
    final packDir = '${docDir.path}/packs/$packName';
    final stagingPath = '${docDir.path}/packs/${packName}_installing';

    final staging = Directory(stagingPath);
    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }
    await staging.create(recursive: true);

    // Step 4: extract all parts (skip part-specific manifest/species.json)
    final allSpecies = <Map<String, dynamic>>[];
    var totalAudio = 0;
    var totalImage = 0;
    String? region;
    String? version;
    String? source;

    for (var i = 0; i < partInfos.length; i++) {
      final info = partInfos[i];
      onProgress?.call(
        i + 1,
        partInfos.length,
        '解压分包 ${info.part}/$expectedPartCount',
      );

      for (final file in info.archive) {
        if (!file.isFile) continue;
        final name = file.name;
        if (name == 'manifest.json' || name == 'species.json') continue;
        final dest = File('$stagingPath/$name');
        await dest.parent.create(recursive: true);
        await dest.writeAsBytes(file.content as List<int>);
      }

      final speciesEntry = info.archive.findFile('species.json');
      if (speciesEntry != null) {
        final list = jsonDecode(
          utf8.decode(speciesEntry.content as List<int>),
        ) as List<dynamic>;
        for (final row in list) {
          allSpecies.add(Map<String, dynamic>.from(row as Map));
        }
      }

      region ??= info.manifest['region'] as String?;
      version ??= info.manifest['version'] as String?;
      source ??= info.manifest['source'] as String?;
      totalAudio += (info.manifest['audio_count'] as int?) ?? 0;
      totalImage += (info.manifest['image_count'] as int?) ?? 0;
    }

    // Step 5: write merged manifest + species.json
    onProgress?.call(partInfos.length, partInfos.length, '合并清单');
    await File('$stagingPath/species.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(allSpecies),
    );
    final mergedManifest = <String, dynamic>{
      'name': packName,
      if (region != null && region.isNotEmpty) 'region': region,
      if (version != null && version.isNotEmpty) 'version': version,
      'created': DateTime.now().toIso8601String().split('T').first,
      'species_count': allSpecies.length,
      'audio_count': totalAudio,
      'image_count': totalImage,
      if (source != null && source.isNotEmpty) 'source': source,
      'merged_from_parts': expectedPartCount,
    };
    await File('$stagingPath/manifest.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(mergedManifest),
    );

    // Step 6: atomic replace + activate
    final oldDir = Directory(packDir);
    if (await oldDir.exists()) {
      await oldDir.delete(recursive: true);
    }
    await staging.rename(packDir);

    await prefsSetBuiltinFlagFalse();
    await setActivePack(packDir);
    return DataPack.fromJson(mergedManifest, packDir);
  }

  /// 检查一组 ZIP 是否为分包（仅看第一个文件的 manifest）
  Future<bool> isPartArchive(String zipPath) async {
    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final manifestEntry = archive.findFile('manifest.json');
      if (manifestEntry == null) return false;
      final manifest = jsonDecode(
        utf8.decode(manifestEntry.content as List<int>),
      ) as Map<String, dynamic>;
      return manifest['part'] != null && manifest['part_count'] != null;
    } catch (_) {
      return false;
    }
  }

  /// 导入 ZIP 数据包（传入字节数据）
  Future<DataPack> importPackFromBytes(
      Uint8List zipBytes, String zipName) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final packName = zipName.replaceAll('.zip', '');
    final docDir = await getApplicationDocumentsDirectory();
    final packDir = '${docDir.path}/packs/$packName';

    final dir = Directory(packDir);
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);

    for (final file in archive) {
      if (!file.isFile) continue;
      final filePath = '$packDir/${file.name}';
      final f = File(filePath);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(file.content as List<int>);
    }

    final manifestFile = File('$packDir/manifest.json');
    if (!await manifestFile.exists()) throw Exception('数据包缺少 manifest.json');

    final manifestJson =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    await prefsSetBuiltinFlagFalse();
    await setActivePack(packDir);
    return DataPack.fromJson(manifestJson, packDir);
  }

  /// 加载物种列表
  Future<List<Species>> loadSpecies() async {
    final packDir = await getActivePackDir();
    if (packDir == null) throw Exception('未加载任何数据包');

    final speciesFile = File('$packDir/species.json');
    if (!await speciesFile.exists()) {
      throw Exception('数据包损坏，缺少 species.json');
    }

    final str = await speciesFile.readAsString();
    final taxonomy = await _loadTaxonomyIndex();
    return (jsonDecode(str) as List<dynamic>)
        .map((e) => Species.fromJson(e as Map<String, dynamic>))
        .map((species) => _normalizeSpecies(species, taxonomy))
        .toList();
  }

  Species _normalizeSpecies(
    Species species,
    Map<String, _SpeciesNameTaxonomy> taxonomy,
  ) {
    final info = taxonomy[species.sci.trim().toLowerCase()];
    if (info == null) return species;
    return species.copyWith(
      cn: info.zh.isNotEmpty ? info.zh : species.cn,
      order: species.order.isNotEmpty ? species.order : info.order,
      family: species.family.isNotEmpty ? species.family : info.family,
    );
  }

  Future<Map<String, _SpeciesNameTaxonomy>> _loadTaxonomyIndex() {
    return _taxonomyIndexFuture ??= _buildTaxonomyIndex();
  }

  Future<Map<String, _SpeciesNameTaxonomy>> _buildTaxonomyIndex() async {
    final index = <String, _SpeciesNameTaxonomy>{};
    Future<void> mergeAsset(String asset, {required bool preferZh}) async {
      final text = await rootBundle.loadString(asset);
      final data = jsonDecode(text) as List<dynamic>;
      for (final raw in data) {
        final item = raw as Map<String, dynamic>;
        final sci = (item['sci'] as String? ?? '').trim();
        if (sci.isEmpty) continue;
        final key = sci.toLowerCase();
        final old = index[key];
        final zh = (item['zh'] as String? ?? '').trim();
        final order = (item['order'] as String? ?? '').trim();
        final family = (item['family'] as String? ?? '').trim();
        index[key] = _SpeciesNameTaxonomy(
          zh: preferZh && zh.isNotEmpty ? zh : (old?.zh ?? zh),
          order: old?.order.isNotEmpty == true ? old!.order : order,
          family: old?.family.isNotEmpty == true ? old!.family : family,
        );
      }
    }

    await mergeAsset('assets/data/world_birds.json', preferZh: false);
    await mergeAsset('assets/data/china_birds_zheng.json', preferZh: true);
    return index;
  }

  /// 获取已安装数据包列表
  Future<List<DataPack>> getInstalledPacks() async {
    final docDir = await getApplicationDocumentsDirectory();
    final packsPath = '${docDir.path}/packs';
    final result = <DataPack>[];

    final packsDir = Directory(packsPath);
    if (!await packsDir.exists()) return result;

    await for (final entity in packsDir.list()) {
      if (entity is! Directory) continue;
      final mf = File('${entity.path}/manifest.json');
      if (await mf.exists()) {
        final str = await mf.readAsString();
        result.add(DataPack.fromJson(
            jsonDecode(str) as Map<String, dynamic>, entity.path));
      }
    }
    return result;
  }

  /// 删除数据包
  Future<void> deletePack(String packDir) async {
    final dir = Directory(packDir);
    if (await dir.exists()) await dir.delete(recursive: true);

    final active = await getActivePackDir();
    if (active == packDir) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_activePackKey);
    }
  }

  Future<void> deleteSpeciesFromActivePack(Species species) async {
    final packDir = await getActivePackDir();
    if (packDir == null) throw Exception('未加载任何数据包');

    final speciesFile = File('$packDir/species.json');
    final manifestFile = File('$packDir/manifest.json');
    if (!await speciesFile.exists() || !await manifestFile.exists()) {
      throw Exception('数据包损坏，缺少必要文件');
    }

    final speciesList =
        (jsonDecode(await speciesFile.readAsString()) as List<dynamic>)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
    final updated =
        speciesList.where((item) => item['sci'] != species.sci).toList();
    if (updated.length == speciesList.length) return;

    final remainingAudioRefs = <String>{};
    final remainingImages = <String>{};
    for (final item in updated) {
      for (final audio in (item['audios'] as List<dynamic>? ?? const [])) {
        final file = (audio as Map<String, dynamic>)['file'] as String? ?? '';
        if (file.isNotEmpty) remainingAudioRefs.add(file);
      }
      final image = item['image'] as String?;
      if (image != null && image.isNotEmpty) remainingImages.add(image);
      for (final imageItem in (item['images'] as List<dynamic>? ?? const [])) {
        if (imageItem is Map) {
          final file = imageItem['file'] as String? ?? '';
          if (file.isNotEmpty) remainingImages.add(file);
        } else if (imageItem is String && imageItem.isNotEmpty) {
          remainingImages.add(imageItem);
        }
      }
    }

    for (final audio in species.audios) {
      if (!remainingAudioRefs.contains(audio.file)) {
        final file = File('$packDir/${audio.file}');
        if (await file.exists()) {
          await file.delete();
        }
      }
    }

    for (final image in species.imageFiles) {
      if (!remainingImages.contains(image)) {
        final file = File('$packDir/$image');
        if (await file.exists()) {
          await file.delete();
        }
      }
    }

    await speciesFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(updated),
    );

    final manifest = Map<String, dynamic>.from(
      jsonDecode(await manifestFile.readAsString()) as Map,
    );
    manifest['species_count'] = updated.length;
    manifest['audio_count'] = updated.fold<int>(
      0,
      (sum, item) => sum + ((item['audios'] as List<dynamic>?)?.length ?? 0),
    );
    manifest['image_count'] = updated.fold<int>(
      0,
      (sum, item) => sum + _imageCountForManifest(item),
    );
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
    );
  }

  Future<Species> replaceSpeciesImageFromFile(
    Species species,
    String sourcePath,
  ) async {
    final packDir = await getActivePackDir();
    if (packDir == null) throw Exception('未加载任何数据包');

    final source = File(sourcePath);
    if (!await source.exists()) throw Exception('图片文件不存在');

    final speciesFile = File('$packDir/species.json');
    final manifestFile = File('$packDir/manifest.json');
    if (!await speciesFile.exists()) throw Exception('数据包缺少 species.json');

    final ext = _safeExtension(source.path);
    final imageDir = Directory('$packDir/images');
    await imageDir.create(recursive: true);
    final targetName = '${_slug(species.sci)}_custom_$ext';
    final targetRelativePath = 'images/$targetName';
    final target = File('$packDir/$targetRelativePath');
    await source.copy(target.path);

    final speciesList =
        (jsonDecode(await speciesFile.readAsString()) as List<dynamic>)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();

    Map<String, dynamic>? updatedItem;
    for (final item in speciesList) {
      if ((item['sci'] as String? ?? '') == species.sci) {
        item['image'] = targetRelativePath;
        item['image_credit'] = '用户上传';
        final images = _imageEntriesFromItem(item);
        images.removeWhere((image) => image['file'] == targetRelativePath);
        images.insert(0, {
          'file': targetRelativePath,
          'credit': '用户上传',
          'contributor': '用户上传',
          'source': 'local',
        });
        item['images'] = images;
        updatedItem = item;
        break;
      }
    }
    if (updatedItem == null) throw Exception('当前数据包中找不到该鸟种');

    await speciesFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(speciesList),
    );

    if (await manifestFile.exists()) {
      final manifest = Map<String, dynamic>.from(
        jsonDecode(await manifestFile.readAsString()) as Map,
      );
      manifest['image_count'] = speciesList.fold<int>(
        0,
        (sum, item) => sum + _imageCountForManifest(item),
      );
      await manifestFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
      );
    }

    return Species.fromJson(updatedItem);
  }

  Future<Species> addSpeciesAudioFromFile(
    Species species,
    String sourcePath,
  ) async {
    final packDir = await getActivePackDir();
    if (packDir == null) throw Exception('未加载任何数据包');

    final source = File(sourcePath);
    if (!await source.exists()) throw Exception('音频文件不存在');

    final speciesFile = File('$packDir/species.json');
    final manifestFile = File('$packDir/manifest.json');
    if (!await speciesFile.exists()) throw Exception('数据包缺少 species.json');

    final ext = _safeAudioExtension(source.path);
    final soundsDir = Directory('$packDir/sounds');
    await soundsDir.create(recursive: true);
    final targetName =
        '${_slug(species.sci)}_custom_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final targetRelativePath = 'sounds/$targetName';
    final target = File('$packDir/$targetRelativePath');
    await source.copy(target.path);

    final speciesList =
        (jsonDecode(await speciesFile.readAsString()) as List<dynamic>)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();

    Map<String, dynamic>? updatedItem;
    for (final item in speciesList) {
      if ((item['sci'] as String? ?? '') == species.sci) {
        final audios = (item['audios'] as List<dynamic>? ?? const [])
            .map((audio) => Map<String, dynamic>.from(audio as Map))
            .toList();
        audios.add({
          'type': 'call',
          'file': targetRelativePath,
          'contributor': '用户上传',
        });
        item['audios'] = audios;
        item['audio_credit'] = '用户上传';
        updatedItem = item;
        break;
      }
    }
    if (updatedItem == null) throw Exception('当前数据包中找不到该鸟种');

    await speciesFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(speciesList),
    );

    if (await manifestFile.exists()) {
      final manifest = Map<String, dynamic>.from(
        jsonDecode(await manifestFile.readAsString()) as Map,
      );
      manifest['audio_count'] = speciesList.fold<int>(
        0,
        (sum, item) => sum + ((item['audios'] as List<dynamic>?)?.length ?? 0),
      );
      await manifestFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
      );
    }

    return Species.fromJson(updatedItem);
  }

  Future<MediaUpdateResult> updateActivePackFromServer({
    void Function(int current, int total, String speciesName)? onProgress,
  }) async {
    final packDir = await getActivePackDir();
    if (packDir == null) throw Exception('未加载任何数据包');

    final speciesFile = File('$packDir/species.json');
    final manifestFile = File('$packDir/manifest.json');
    if (!await speciesFile.exists()) throw Exception('数据包缺少 species.json');

    final speciesList =
        (jsonDecode(await speciesFile.readAsString()) as List<dynamic>)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
    final imagesDir = Directory('$packDir/images');
    final soundsDir = Directory('$packDir/sounds');
    await imagesDir.create(recursive: true);
    await soundsDir.create(recursive: true);

    final service = ServerMediaService();
    var updatedSpecies = 0;
    var imageAdded = 0;
    var audioAdded = 0;
    var failed = 0;

    for (var i = 0; i < speciesList.length; i++) {
      final item = speciesList[i];
      final sci = (item['sci'] as String? ?? '').trim();
      if (sci.isEmpty) continue;
      onProgress?.call(i + 1, speciesList.length, sci);
      try {
        final media = await service.fetchSpeciesMedia(sci);
        if (media == null) continue;
        var changed = false;

        final images = _imageEntriesFromItem(item);
        final imageKeys = _mediaKeys(images);
        for (final image in media.images.take(3)) {
          final basename = _basenameFromUrl(image.url);
          if (imageKeys.contains(basename) ||
              imageKeys.contains(image.url) ||
              imageKeys.contains(image.contributorUrl)) {
            continue;
          }
          final downloaded = await service.downloadMediaFile(
            url: image.url,
            outputDir: imagesDir.path,
          );
          if (downloaded == null) continue;
          final relative = 'images/${downloaded.filename}';
          images.add({
            'file': relative,
            if (image.contributor.isNotEmpty) 'contributor': image.contributor,
            if (image.contributorUrl.isNotEmpty)
              'contributor_url': image.contributorUrl,
            if (image.source.isNotEmpty) 'source': image.source,
            if (image.license.isNotEmpty) 'license': image.license,
            'credit':
                image.contributor.isNotEmpty ? image.contributor : image.source,
          });
          imageKeys.addAll([relative, downloaded.filename, image.url]);
          if (image.contributorUrl.isNotEmpty) {
            imageKeys.add(image.contributorUrl);
          }
          imageAdded++;
          changed = true;
        }
        if (images.isNotEmpty) {
          item['images'] = images;
          final oldImage = (item['image'] as String? ?? '').trim();
          if (oldImage.isEmpty || !_isCustomImage(item)) {
            item['image'] =
                oldImage.isNotEmpty ? oldImage : images.first['file'];
            item['image_credit'] =
                (item['image_credit'] as String? ?? '').trim().isNotEmpty
                    ? item['image_credit']
                    : images.first['credit'] ?? images.first['contributor'];
          }
        }

        final audios = (item['audios'] as List<dynamic>? ?? const [])
            .map((audio) => Map<String, dynamic>.from(audio as Map))
            .toList();
        final audioKeys = _mediaKeys(audios);
        for (final audio in media.audio.take(2)) {
          final basename = _basenameFromUrl(audio.url);
          if (audioKeys.contains(basename) ||
              audioKeys.contains(audio.url) ||
              audioKeys.contains(audio.contributorUrl)) {
            continue;
          }
          final downloaded = await service.downloadMediaFile(
            url: audio.url,
            outputDir: soundsDir.path,
          );
          if (downloaded == null) continue;
          final relative = 'sounds/${downloaded.filename}';
          audios.add({
            'type': audio.type.isEmpty ? 'call' : audio.type,
            'file': relative,
            if (audio.contributor.isNotEmpty) 'contributor': audio.contributor,
            if (audio.contributorUrl.isNotEmpty)
              'contributor_url': audio.contributorUrl,
            if (audio.license.isNotEmpty) 'license': audio.license,
          });
          audioKeys.addAll([relative, downloaded.filename, audio.url]);
          if (audio.contributorUrl.isNotEmpty) {
            audioKeys.add(audio.contributorUrl);
          }
          audioAdded++;
          changed = true;
        }
        item['audios'] = audios;

        if ((item['order'] as String? ?? '').trim().isEmpty &&
            media.order.isNotEmpty) {
          item['order'] = media.order;
          changed = true;
        }
        if ((item['family'] as String? ?? '').trim().isEmpty &&
            media.family.isNotEmpty) {
          item['family'] = media.family;
          changed = true;
        }
        if ((item['identification_features'] as String? ?? '').trim().isEmpty &&
            media.identificationFeatures.isNotEmpty) {
          item['identification_features'] = media.identificationFeatures;
          changed = true;
        }
        if (changed) updatedSpecies++;
      } catch (_) {
        failed++;
      }
    }

    await speciesFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(speciesList),
    );
    if (await manifestFile.exists()) {
      final manifest = Map<String, dynamic>.from(
        jsonDecode(await manifestFile.readAsString()) as Map,
      );
      manifest['audio_count'] = speciesList.fold<int>(
        0,
        (sum, item) => sum + ((item['audios'] as List<dynamic>?)?.length ?? 0),
      );
      manifest['image_count'] = speciesList.fold<int>(
        0,
        (sum, item) => sum + _imageCountForManifest(item),
      );
      manifest['updated'] = DateTime.now().toIso8601String().split('T').first;
      await manifestFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
      );
    }

    return MediaUpdateResult(
      speciesCount: speciesList.length,
      updatedSpecies: updatedSpecies,
      imageAdded: imageAdded,
      audioAdded: audioAdded,
      failed: failed,
    );
  }

  /// 获取资源的绝对路径（音频/图片）
  Future<String?> getResourcePath(String relativePath) async {
    final packDir = await getActivePackDir();
    if (packDir == null) return null;
    final fullPath = '$packDir/$relativePath';
    if (await File(fullPath).exists()) return fullPath;
    return null;
  }

  /// 是否有激活的数据包
  Future<bool> hasActivePack() async {
    final dir = await getActivePackDir();
    if (dir == null) return false;
    return await Directory(dir).exists();
  }

  Future<void> prefsSetBuiltinFlagFalse() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_builtinInstalledKey, false);
  }

  String _sanitizeFileName(String value) {
    return value.replaceAll(RegExp(r'[\\\\/:*?"<>|]'), '_');
  }

  String _safeExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'jpg';
    final ext = path.substring(dot + 1).toLowerCase();
    if (['jpg', 'jpeg', 'png', 'webp'].contains(ext)) return ext;
    return 'jpg';
  }

  String _safeAudioExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'mp3';
    final ext = path.substring(dot + 1).toLowerCase();
    if (['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg'].contains(ext)) return ext;
    return 'mp3';
  }

  static List<Map<String, dynamic>> _imageEntriesFromItem(
    Map<String, dynamic> item,
  ) {
    final result = <Map<String, dynamic>>[];
    final image = (item['image'] as String? ?? '').trim();
    if (image.isNotEmpty) {
      result.add({
        'file': image,
        if ((item['image_credit'] as String? ?? '').trim().isNotEmpty)
          'credit': item['image_credit'],
        if ((item['image_license'] as String? ?? '').trim().isNotEmpty)
          'license': item['image_license'],
      });
    }
    for (final raw in (item['images'] as List<dynamic>? ?? const [])) {
      Map<String, dynamic>? entry;
      if (raw is String) {
        entry = {'file': raw};
      } else if (raw is Map) {
        entry = Map<String, dynamic>.from(raw);
      }
      final file = (entry?['file'] as String? ?? '').trim();
      if (entry == null ||
          file.isEmpty ||
          result.any((old) => old['file'] == file)) {
        continue;
      }
      result.add(entry);
    }
    return result;
  }

  static int _imageCountForManifest(dynamic item) {
    if (item is! Map) return 0;
    return _imageEntriesFromItem(Map<String, dynamic>.from(item)).length;
  }

  static Set<String> _mediaKeys(List<Map<String, dynamic>> items) {
    final keys = <String>{};
    for (final item in items) {
      for (final field in const ['file', 'url', 'contributor_url']) {
        final value = (item[field] as String? ?? '').trim();
        if (value.isEmpty) continue;
        keys.add(value);
        keys.add(value.split('/').last);
      }
    }
    return keys;
  }

  static String _basenameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
    return url.split('/').last;
  }

  static bool _isCustomImage(Map<String, dynamic> item) {
    final image = (item['image'] as String? ?? '').toLowerCase();
    final credit = (item['image_credit'] as String? ?? '').trim();
    return credit == '用户上传' || image.contains('_custom_');
  }

  /// 保存物种难度分到本地 species.json
  Future<void> saveSpeciesDifficulty(
    String packDir,
    String sci,
    int difficulty,
  ) async {
    final speciesFile = File('$packDir/species.json');
    if (!await speciesFile.exists()) return;
    final raw = await speciesFile.readAsString();
    final list = jsonDecode(raw) as List<dynamic>;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      if ((map['sci'] as String?) == sci) {
        if (difficulty == 1) {
          map.remove('difficulty');
        } else {
          map['difficulty'] = difficulty;
        }
        break;
      }
    }
    await speciesFile.writeAsString(jsonEncode(list));
  }

  String _slug(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (normalized.isNotEmpty) return normalized;
    return 'bird_${Random().nextInt(1 << 32)}';
  }
}

class _SpeciesNameTaxonomy {
  final String zh;
  final String order;
  final String family;

  const _SpeciesNameTaxonomy({
    required this.zh,
    required this.order,
    required this.family,
  });
}

/// 表示一个值得重试的下载错误（网络中断、超时、5xx 等）
class _RetryableException implements Exception {
  final String message;
  _RetryableException(this.message);
  @override
  String toString() => message;
}

/// 表示一个不应该重试的错误（404、403、磁盘满等）
class _NonRetryableException implements Exception {
  final String message;
  _NonRetryableException(this.message);
  @override
  String toString() => message;
}

class _PartInfo {
  final String path;
  final int part;
  final Map<String, dynamic> manifest;
  final Archive archive;

  const _PartInfo({
    required this.path,
    required this.part,
    required this.manifest,
    required this.archive,
  });
}

class MediaUpdateResult {
  final int speciesCount;
  final int updatedSpecies;
  final int imageAdded;
  final int audioAdded;
  final int failed;

  const MediaUpdateResult({
    required this.speciesCount,
    required this.updatedSpecies,
    required this.imageAdded,
    required this.audioAdded,
    required this.failed,
  });
}
