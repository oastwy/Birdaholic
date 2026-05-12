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

  /// 从服务器下载并安装数据包（流式下载 + 流式解压，支持进度回调）
  Future<DataPack> downloadAndInstallRemotePack(
    RemotePackInfo info, {
    void Function(int received, int total)? onProgress,
  }) async {
    final docDir = await getApplicationDocumentsDirectory();
    final packDir = '${docDir.path}/packs/${info.dirName}';
    final stagingDir = '${docDir.path}/packs/${info.dirName}_installing';
    final downloadDir = Directory('${docDir.path}/downloads');
    await downloadDir.create(recursive: true);
    final tempZip = File('${downloadDir.path}/remote_${info.dirName}.zip.part');

    await WakelockPlus.enable();
    try {
      var existingBytes = await tempZip.exists() ? await tempZip.length() : 0;
      final request = http.Request('GET', Uri.parse(info.url));
      if (existingBytes > 0) {
        request.headers['Range'] = 'bytes=$existingBytes-';
      }
      final response = await request.send();

      if (response.statusCode == 416 &&
          info.sizeBytes > 0 &&
          existingBytes >= info.sizeBytes) {
        onProgress?.call(existingBytes, info.sizeBytes);
      } else {
        if (response.statusCode == 200 && existingBytes > 0) {
          existingBytes = 0;
          await tempZip.delete().catchError((_) => tempZip);
        }
        if (response.statusCode != 200 && response.statusCode != 206) {
          throw Exception('下载失败: HTTP ${response.statusCode}');
        }

        if (response.statusCode == 206) {
          final range = response.headers['content-range'];
          final match = range == null
              ? null
              : RegExp(r'bytes\s+(\d+)-(\d+)/(\d+|\*)').firstMatch(range);
          final rangeStart =
              match == null ? null : int.tryParse(match.group(1)!);
          if (rangeStart != null && rangeStart != existingBytes) {
            await tempZip.delete().catchError((_) => tempZip);
            return await downloadAndInstallRemotePack(
              info,
              onProgress: onProgress,
            );
          }
        }

        final contentRangeTotal = _contentRangeTotal(
          response.headers['content-range'],
        );
        final total = response.statusCode == 206
            ? contentRangeTotal ?? existingBytes + (response.contentLength ?? 0)
            : response.contentLength ?? info.sizeBytes;
        var received = existingBytes;
        onProgress?.call(received, total);

        final sink = tempZip.openWrite(
          mode: response.statusCode == 206 ? FileMode.append : FileMode.write,
        );
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
        await sink.close();
      }

      final staging = Directory(stagingDir);
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
      await staging.create(recursive: true);

      await extractFileToDisk(tempZip.path, stagingDir);
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
    }

    for (final audio in species.audios) {
      if (!remainingAudioRefs.contains(audio.file)) {
        final file = File('$packDir/${audio.file}');
        if (await file.exists()) {
          await file.delete();
        }
      }
    }

    if (species.image != null && !remainingImages.contains(species.image)) {
      final file = File('$packDir/${species.image}');
      if (await file.exists()) {
        await file.delete();
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
    manifest['image_count'] = updated
        .where((item) => (item['image'] as String?)?.isNotEmpty ?? false)
        .length;
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
      manifest['image_count'] = speciesList
          .where((item) => (item['image'] as String?)?.isNotEmpty ?? false)
          .length;
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
