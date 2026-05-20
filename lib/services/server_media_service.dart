import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ServerMediaService {
  static const defaultBaseUrl = 'https://birding.today';
  static const _maxRetries = 4;
  static const _requestTimeout = Duration(seconds: 25);

  final String baseUrl;
  final http.Client _client;

  ServerMediaService({
    this.baseUrl = defaultBaseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<T> _withRetry<T>(Future<T> Function() action, {String label = ''}) async {
    Object? lastError;
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        return await action();
      } catch (e) {
        lastError = e;
        if (attempt == _maxRetries - 1) break;
        // Exponential backoff: 1s, 2s, 4s, ...
        final delayMs = 1000 * (1 << attempt);
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
    throw Exception('$label 请求多次失败: $lastError');
  }

  Future<ServerSpeciesMedia?> fetchSpeciesMedia(String scientificName) async {
    final key = scientificName.trim().replaceAll(RegExp(r'\s+'), '_');
    if (key.isEmpty) return null;

    final uri = Uri.parse('$baseUrl/species/$key/manifest.json');
    final response = await _withRetry(
      () => _client.get(uri).timeout(_requestTimeout),
      label: 'manifest($scientificName)',
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('服务器媒体请求失败: ${response.statusCode}');
    }

    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return ServerSpeciesMedia.fromJson(data);
  }

  Future<_DownloadedFile?> _downloadFile({
    required String url,
    required String outputDir,
  }) async {
    final uri = _resolveUrl(url);

    final filename = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    if (filename.isEmpty) return null;

    final file = File('$outputDir/$filename');
    if (await file.exists() && await file.length() > 0) {
      return _DownloadedFile(file: file, filename: filename);
    }

    Object? lastError;
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final partFile = File('${file.path}.part');
        var existingBytes =
            await partFile.exists() ? await partFile.length() : 0;
        final request = http.Request('GET', uri);
        if (existingBytes > 0) {
          request.headers['Range'] = 'bytes=$existingBytes-';
        }
        final response =
            await _client.send(request).timeout(_requestTimeout);
        if (response.statusCode == 200 && existingBytes > 0) {
          existingBytes = 0;
          await partFile.delete().catchError((_) => partFile);
        }
        if (response.statusCode != 200 && response.statusCode != 206) {
          return null;
        }

        await file.parent.create(recursive: true);
        final sink = partFile.openWrite(
          mode: response.statusCode == 206 ? FileMode.append : FileMode.write,
        );
        await response.stream.pipe(sink);
        await partFile.rename(file.path);
        return _DownloadedFile(file: file, filename: filename);
      } catch (e) {
        lastError = e;
        if (attempt == _maxRetries - 1) break;
        final delayMs = 1000 * (1 << attempt);
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
    // After all retries, give up but don't throw — caller treats null as skip.
    // ignore: avoid_print
    print('下载失败 $filename: $lastError');
    return null;
  }

  Future<DownloadedServerFile?> downloadMediaFile({
    required String url,
    required String outputDir,
  }) async {
    final downloaded = await _downloadFile(url: url, outputDir: outputDir);
    if (downloaded == null) return null;
    return DownloadedServerFile(
      file: downloaded.file,
      filename: downloaded.filename,
    );
  }

  Uri _resolveUrl(String value) {
    final uri = Uri.parse(value);
    if (uri.hasScheme) return uri;
    return Uri.parse(baseUrl).resolve(value);
  }

  Future<ServerSpeciesDownload?> downloadSpecies({
    required String cn,
    required String en,
    required String sci,
    required String cons,
    required String habitat,
    required String soundsDir,
    required String imagesDir,
  }) async {
    final media = await fetchSpeciesMedia(sci);
    if (media == null || (!media.hasImage && !media.hasAudio)) return null;

    final audioEntries = <Map<String, String>>[];
    for (final audio in media.audio.take(2)) {
      final downloaded = await _downloadFile(
        url: audio.url,
        outputDir: soundsDir,
      );
      if (downloaded == null) continue;
      audioEntries.add({
        'type': audio.type.isEmpty ? 'call' : audio.type,
        'file': 'sounds/${downloaded.filename}',
        if (audio.contributor.isNotEmpty) 'contributor': audio.contributor,
        if (audio.contributorUrl.isNotEmpty)
          'contributor_url': audio.contributorUrl,
        if (audio.license.isNotEmpty) 'license': audio.license,
      });
    }

    final imageEntries = <Map<String, String>>[];
    for (final image in media.images.take(3)) {
      final downloaded = await _downloadFile(
        url: image.url,
        outputDir: imagesDir,
      );
      if (downloaded == null) continue;
      imageEntries.add({
        'file': 'images/${downloaded.filename}',
        if (image.contributor.isNotEmpty) 'contributor': image.contributor,
        if (image.contributorUrl.isNotEmpty)
          'contributor_url': image.contributorUrl,
        if (image.source.isNotEmpty) 'source': image.source,
        if (image.license.isNotEmpty) 'license': image.license,
        'credit':
            image.contributor.isNotEmpty ? image.contributor : image.source,
      });
    }

    if (audioEntries.isEmpty && imageEntries.isEmpty) return null;

    final audioCredits = audioEntries
        .map((item) => (item['contributor'] ?? '').trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .join(', ');

    return ServerSpeciesDownload(
      json: {
        'cn': cn.isNotEmpty ? cn : media.cn,
        'en': en.isNotEmpty ? en : media.en,
        'sci': sci,
        if (cons.isNotEmpty) 'cons': cons,
        if (habitat.isNotEmpty) 'habitat': habitat,
        if (media.order.isNotEmpty) 'order': media.order,
        if (media.family.isNotEmpty) 'family': media.family,
        if (media.identificationFeatures.isNotEmpty)
          'identification_features': media.identificationFeatures,
        'audios': audioEntries,
        if (imageEntries.isNotEmpty) 'image': imageEntries.first['file'],
        if (imageEntries.isNotEmpty) 'images': imageEntries,
        if (imageEntries.isNotEmpty &&
            (imageEntries.first['credit'] ?? '').isNotEmpty)
          'image_credit': imageEntries.first['credit'],
        if (imageEntries.isNotEmpty &&
            (imageEntries.first['license'] ?? '').isNotEmpty)
          'image_license': imageEntries.first['license'],
        if (audioCredits.isNotEmpty) 'audio_credit': audioCredits,
      },
      audioCount: audioEntries.length,
      hasImage: imageEntries.isNotEmpty,
    );
  }
}

class ServerSpeciesMedia {
  final String sci;
  final String cn;
  final String en;
  final String order;
  final String family;
  final String identificationFeatures;
  final List<ServerImageMedia> images;
  final List<ServerAudioMedia> audio;

  const ServerSpeciesMedia({
    required this.sci,
    required this.cn,
    required this.en,
    required this.order,
    required this.family,
    required this.identificationFeatures,
    required this.images,
    required this.audio,
  });

  bool get hasImage => images.isNotEmpty;
  bool get hasAudio => audio.isNotEmpty;

  factory ServerSpeciesMedia.fromJson(Map<String, dynamic> json) {
    return ServerSpeciesMedia(
      sci: json['sci'] as String? ?? '',
      cn: json['cn'] as String? ?? '',
      en: json['en'] as String? ?? '',
      order: json['order'] as String? ?? '',
      family: json['family'] as String? ?? '',
      identificationFeatures: json['identification_features'] as String? ?? '',
      images: (json['images'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .where((m) => m['pending'] != true)
          .map(ServerImageMedia.fromJson)
          .where((item) => item.url.isNotEmpty)
          .toList(),
      audio: (json['audio'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .where((m) => m['pending'] != true)
          .map(ServerAudioMedia.fromJson)
          .where((item) => item.url.isNotEmpty)
          .toList(),
    );
  }
}

class ServerImageMedia {
  final String file;
  final String url;
  final String contributor;
  final String contributorUrl;
  final String source;
  final String license;
  final int difficulty;

  const ServerImageMedia({
    required this.file,
    required this.url,
    required this.contributor,
    required this.contributorUrl,
    required this.source,
    required this.license,
    this.difficulty = 0,
  });

  factory ServerImageMedia.fromJson(Map<String, dynamic> json) {
    return ServerImageMedia(
      file: json['file'] as String? ?? '',
      url: json['url'] as String? ?? '',
      contributor: json['contributor'] as String? ?? '',
      contributorUrl: json['contributor_url'] as String? ?? '',
      source: json['source'] as String? ?? '',
      license: json['license'] as String? ?? '',
      difficulty: (json['difficulty'] as num?)?.toInt() ?? 0,
    );
  }
}

class ServerAudioMedia {
  final String url;
  final String type;
  final String contributor;
  final String contributorUrl;
  final String license;

  const ServerAudioMedia({
    required this.url,
    required this.type,
    required this.contributor,
    required this.contributorUrl,
    required this.license,
  });

  factory ServerAudioMedia.fromJson(Map<String, dynamic> json) {
    return ServerAudioMedia(
      url: json['url'] as String? ?? '',
      type: json['type'] as String? ?? '',
      contributor: json['contributor'] as String? ?? '',
      contributorUrl: json['contributor_url'] as String? ?? '',
      license: json['license'] as String? ?? '',
    );
  }
}

class ServerSpeciesDownload {
  final Map<String, dynamic> json;
  final int audioCount;
  final bool hasImage;

  const ServerSpeciesDownload({
    required this.json,
    required this.audioCount,
    required this.hasImage,
  });
}

class _DownloadedFile {
  final File file;
  final String filename;

  const _DownloadedFile({required this.file, required this.filename});
}

class DownloadedServerFile {
  final File file;
  final String filename;

  const DownloadedServerFile({
    required this.file,
    required this.filename,
  });
}
