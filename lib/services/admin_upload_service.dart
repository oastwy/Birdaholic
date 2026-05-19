import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/species.dart';
import 'server_media_service.dart';

class AdminUploadService {
  final String baseUrl;
  final http.Client _client;

  AdminUploadService({
    this.baseUrl = ServerMediaService.defaultBaseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<void> uploadMedia({
    required Species species,
    required String filePath,
    required String token,
    String contributor = '管理员上传',
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/upload'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['sci'] = species.sci;
    request.fields['contributor'] = contributor;
    request.files.add(await http.MultipartFile.fromPath('files', filePath));

    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('服务器上传失败: ${response.statusCode} $body');
    }
  }

  Future<void> setDifficulty({
    required String sci,
    required int difficulty,
    required String token,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/set_difficulty'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'sci': sci, 'difficulty': difficulty}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('难度上传失败: ${response.statusCode} ${response.body}');
    }
  }

  Future<void> uploadIdentificationFeatures({
    required Species species,
    required String features,
    required String token,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/features'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'sci': species.sci,
        'cn': species.cn,
        'en': species.en,
        'features': features,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('服务器上传失败: ${response.statusCode} ${response.body}');
    }
  }
}
