import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/data_pack.dart';
import '../models/species.dart';

/// 数据包管理服务（原生 Android/iOS）
class PackManager {
  static const _activePackKey = 'active_pack_dir';
  static const _builtinInstalledKey = 'builtin_pack_installed';
  static const _builtinTrialPackAsset = 'data_packs/盈江鸟鸣试用_v0.1.zip';
  static const _builtinTrialPackDirName = '盈江鸟鸣闪卡（试用版）';

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
    // 当前版本不再自动安装内置包，保留接口兼容性。
    return;
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
    final packName = (manifestJson['name'] as String? ?? sourceDir.uri.pathSegments.last)
        .trim();
    final safeName = _sanitizeFileName(packName.isEmpty ? 'bird_pack' : packName);
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final zipPath = '$outputDir/${safeName}_backup_$timestamp.zip';

    final archive = Archive();
    await for (final entity in sourceDir.list(recursive: true, followLinks: false)) {
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

  Future<DataPack> installBuiltinTrialPack() async {
    final prefs = await SharedPreferences.getInstance();
    final docDir = await getApplicationDocumentsDirectory();
    final packDir = '${docDir.path}/packs/$_builtinTrialPackDirName';
    final dir = Directory(packDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);

    final zipData = await rootBundle.load(_builtinTrialPackAsset);
    final archive = ZipDecoder().decodeBytes(zipData.buffer.asUint8List());
    for (final file in archive) {
      if (!file.isFile) continue;
      final filePath = '$packDir/${file.name}';
      final outFile = File(filePath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(file.content as List<int>);
    }

    final manifestFile = File('$packDir/manifest.json');
    if (!await manifestFile.exists()) {
      throw Exception('内置试用包缺少 manifest.json');
    }

    final manifestJson =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    await prefs.setBool(_builtinInstalledKey, true);
    await setActivePack(packDir);
    return DataPack.fromJson(manifestJson, packDir);
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
    return (jsonDecode(str) as List<dynamic>)
        .map((e) => Species.fromJson(e as Map<String, dynamic>))
        .toList();
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

    final speciesList = (jsonDecode(await speciesFile.readAsString()) as List<dynamic>)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final updated = speciesList.where((item) => item['sci'] != species.sci).toList();
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
    manifest['image_count'] =
        updated.where((item) => (item['image'] as String?)?.isNotEmpty ?? false).length;
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
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
}
