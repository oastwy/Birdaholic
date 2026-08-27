import 'dart:io';

import '../models/species.dart';

/// An immutable view of one data pack for a flashcard session.
///
/// Species metadata and media paths share the same owner: media referenced by
/// this snapshot can only resolve inside [packDir]. The file index is captured
/// once so ordinary card rendering never rereads preferences or scans other
/// enabled packs.
class PackSnapshot {
  final String packDir;
  final List<Species> species;
  final Map<String, String> _mediaPaths;

  PackSnapshot._({
    required this.packDir,
    required this.species,
    required Map<String, String> mediaPaths,
  }) : _mediaPaths = Map.unmodifiable(mediaPaths);

  static Future<PackSnapshot> create({
    required String packDir,
    required List<Species> species,
  }) async {
    final root = Directory(packDir);
    if (!await root.exists()) throw Exception('数据包目录不存在');

    final prefix = packDir.endsWith(Platform.pathSeparator)
        ? packDir
        : '$packDir${Platform.pathSeparator}';
    final mediaPaths = <String, String>{};
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.startsWith(prefix)) continue;
      final relative = entity.path
          .substring(prefix.length)
          .replaceAll(Platform.pathSeparator, '/');
      final normalized = _safeRelativePath(relative);
      if (normalized != null) mediaPaths[normalized] = entity.path;
    }

    return PackSnapshot._(
      packDir: packDir,
      species: List.unmodifiable(species),
      mediaPaths: mediaPaths,
    );
  }

  /// Resolves a pack-relative media reference without filesystem I/O.
  /// Unsafe or absent paths deliberately resolve to null.
  String? resolveMedia(String relativePath) {
    final normalized = _safeRelativePath(relativePath);
    return normalized == null ? null : _mediaPaths[normalized];
  }

  static String? _safeRelativePath(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        normalized.contains('\u0000')) {
      return null;
    }
    final parts = normalized.split('/');
    if (parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      return null;
    }
    return parts.join('/');
  }
}
