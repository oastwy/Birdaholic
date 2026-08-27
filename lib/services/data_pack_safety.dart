import 'package:archive/archive.dart';

/// Validation boundary for user-supplied data-pack archives.
///
/// ZIP entry names are attacker-controlled. Keep all validation independent of
/// the filesystem so import code can never accidentally write outside its
/// staging directory.
class DataPackSafety {
  static const maxInputBytes = 256 * 1024 * 1024;
  static const maxEntryCount = 10000;
  static const maxEntryBytes = 256 * 1024 * 1024;
  static const maxExpandedBytes = 1024 * 1024 * 1024;

  /// Gets a safe directory name from either a selected ZIP filename or a
  /// multipart archive's `split_from` value.
  static String packName(String value) {
    var name = value.trim();
    if (name.toLowerCase().endsWith('.zip')) {
      name = name.substring(0, name.length - 4).trim();
    }
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.length > 100 ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains('\u0000')) {
      throw const FormatException('数据包名称不安全');
    }
    return name;
  }

  /// Validates a ZIP-relative path and returns its normalized slash form.
  static String relativePath(String value) {
    if (value.isEmpty ||
        value.length > 240 ||
        value.startsWith('/') ||
        value.startsWith('\\') ||
        value.contains('\\') ||
        value.contains('\u0000')) {
      throw const FormatException('数据包包含不安全的文件路径');
    }

    final parts = value.split('/');
    if (parts.any((part) =>
        part.isEmpty || part == '.' || part == '..' || part.length > 120)) {
      throw const FormatException('数据包包含不安全的文件路径');
    }
    return parts.join('/');
  }

  /// Returns safe, unique file entries and rejects archive bombs before any
  /// entry content is decompressed or written to disk.
  static List<SafeArchiveEntry> archiveEntries(Archive archive) {
    if (archive.length > maxEntryCount) {
      throw const FormatException('数据包文件数量过多');
    }

    var totalBytes = 0;
    final seen = <String>{};
    final entries = <SafeArchiveEntry>[];
    for (final file in archive) {
      if (!file.isFile) continue;
      if (file.isSymbolicLink) {
        throw const FormatException('数据包不能包含符号链接');
      }
      final path = relativePath(file.name);
      if (!seen.add(path)) {
        throw const FormatException('数据包包含重复文件');
      }
      if (file.size < 0 || file.size > maxEntryBytes) {
        throw const FormatException('数据包单个文件过大');
      }
      totalBytes += file.size;
      if (totalBytes > maxExpandedBytes) {
        throw const FormatException('数据包解压后过大');
      }
      entries.add(SafeArchiveEntry(file: file, relativePath: path));
    }
    if (entries.isEmpty) throw const FormatException('数据包没有可用文件');
    return entries;
  }
}

class SafeArchiveEntry {
  final ArchiveFile file;
  final String relativePath;

  const SafeArchiveEntry({required this.file, required this.relativePath});
}
