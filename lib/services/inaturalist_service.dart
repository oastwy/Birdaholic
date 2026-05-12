import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class INaturalistPhoto {
  final String url;
  final String attribution;

  const INaturalistPhoto({required this.url, required this.attribution});
}

class INaturalistService {
  final http.Client _client;

  INaturalistService({http.Client? client}) : _client = client ?? http.Client();

  Future<INaturalistPhoto?> searchPhoto(String scientificName) async {
    final uri = Uri.https('api.inaturalist.org', '/v1/observations', {
      'taxon_name': scientificName,
      'photos': 'true',
      'quality_grade': 'research',
      'per_page': '8',
      'order_by': 'votes',
    });
    final response = await _client.get(uri);
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = data['results'] as List<dynamic>? ?? const [];
    for (final item in results) {
      final observation = item as Map<String, dynamic>;
      final photos = observation['photos'] as List<dynamic>? ?? const [];
      if (photos.isEmpty) continue;

      final photo = photos.first as Map<String, dynamic>;
      final rawUrl = photo['url'] as String? ?? '';
      if (rawUrl.isEmpty) continue;

      final user = observation['user'] as Map<String, dynamic>?;
      final name = (user?['name'] as String? ?? '').trim();
      final login = (user?['login'] as String? ?? '').trim();
      final author = name.isNotEmpty ? name : login;
      final license = (photo['license_code'] as String? ?? '').trim();
      final attribution = [
        'iNaturalist',
        if (author.isNotEmpty) author,
        if (license.isNotEmpty) license.toUpperCase(),
      ].join(' · ');

      return INaturalistPhoto(
        url: rawUrl.replaceAll('square.', 'medium.'),
        attribution: attribution,
      );
    }
    return null;
  }

  Future<String?> downloadPhoto(INaturalistPhoto photo, String savePath) async {
    if (await File(savePath).exists()) return savePath;
    try {
      final response = await _client.get(Uri.parse(photo.url));
      if (response.statusCode != 200) return null;
      final file = File(savePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<INaturalistPhoto?> searchAndDownload(
    String scientificName,
    String savePath,
  ) async {
    final photo = await searchPhoto(scientificName);
    if (photo == null) return null;
    final path = await downloadPhoto(photo, savePath);
    if (path == null) return null;
    return photo;
  }
}
