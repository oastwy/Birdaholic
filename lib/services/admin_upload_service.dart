import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/species.dart';
import 'server_media_service.dart';

class WhoAmI {
  final String id;
  final String role; // admin / beta
  final String name;
  const WhoAmI({required this.id, required this.role, required this.name});
  bool get isAdmin => role == 'admin';
  bool get isBeta => role == 'beta';
}

class UploadStats {
  final int myImages;
  final int myAudio;
  final int myPending;
  final int pendingTotal; // 仅 admin 有效
  final String role;
  const UploadStats({
    required this.myImages,
    required this.myAudio,
    required this.myPending,
    required this.pendingTotal,
    required this.role,
  });
}

class AdminFeedbackEntry {
  final String id;
  final String uploaderId;
  final String uploaderName;
  final String role;
  final String message;
  final String page;
  final String speciesCn;
  final String speciesSci;
  final int createdAt;
  final String status; // open / resolved
  const AdminFeedbackEntry({
    required this.id,
    required this.uploaderId,
    required this.uploaderName,
    required this.role,
    required this.message,
    required this.page,
    required this.speciesCn,
    required this.speciesSci,
    required this.createdAt,
    required this.status,
  });

  factory AdminFeedbackEntry.fromJson(Map<String, dynamic> j) => AdminFeedbackEntry(
        id: j['id'] as String? ?? '',
        uploaderId: j['uploader_id'] as String? ?? '',
        uploaderName: j['uploader_name'] as String? ?? '',
        role: j['role'] as String? ?? 'beta',
        message: j['message'] as String? ?? '',
        page: j['page'] as String? ?? '',
        speciesCn: j['species_cn'] as String? ?? '',
        speciesSci: j['species_sci'] as String? ?? '',
        createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
        status: j['status'] as String? ?? 'open',
      );
}

class UploadUser {
  final String token;
  final String id;
  final String role;
  final String name;
  final bool isSelf;
  const UploadUser({
    required this.token,
    required this.id,
    required this.role,
    required this.name,
    required this.isSelf,
  });
  bool get isAdmin => role == 'admin';
}

class PendingMediaItem {
  final String sci;
  final String cn;
  final String en;
  final String kind; // images / audio
  final String file;
  final String url;
  final String contributor;
  final String uploaderId;
  final String uploaderName;
  final int uploadedAt;
  const PendingMediaItem({
    required this.sci,
    required this.cn,
    required this.en,
    required this.kind,
    required this.file,
    required this.url,
    required this.contributor,
    required this.uploaderId,
    required this.uploaderName,
    required this.uploadedAt,
  });
}

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

  /// 通用上传：返回服务器响应（含 saved/failed）。供新上传 UI 使用。
  Future<Map<String, dynamic>> uploadFile({
    required String sci,
    required String contributor,
    required String filePath,
    required String token,
    int difficulty = 0,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/upload'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['token'] = token;
    request.fields['sci'] = sci;
    request.fields['contributor'] = contributor;
    if (difficulty > 0) request.fields['difficulty'] = '$difficulty';
    request.files.add(await http.MultipartFile.fromPath('files', filePath));
    final streamed = await request.send().timeout(const Duration(seconds: 120));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception('HTTP ${streamed.statusCode}: $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<WhoAmI?> whoami({required String token}) async {
    if (token.trim().isEmpty) return null;
    final uri = Uri.parse('$baseUrl/api/whoami?token=$token');
    final response = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return WhoAmI(
      id: data['id'] as String? ?? '',
      role: data['role'] as String? ?? 'beta',
      name: data['name'] as String? ?? '',
    );
  }

  Future<UploadStats?> fetchStats({required String token}) async {
    if (token.trim().isEmpty) return null;
    final uri = Uri.parse('$baseUrl/api/upload_stats?token=$token');
    final response = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return UploadStats(
      myImages: (data['my_images'] as num?)?.toInt() ?? 0,
      myAudio: (data['my_audio'] as num?)?.toInt() ?? 0,
      myPending: (data['my_pending'] as num?)?.toInt() ?? 0,
      pendingTotal: (data['pending_total'] as num?)?.toInt() ?? 0,
      role: data['role'] as String? ?? 'beta',
    );
  }

  Future<List<PendingMediaItem>> fetchPending({required String token}) async {
    final uri = Uri.parse('$baseUrl/api/admin/pending?token=$token');
    final response = await _client.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('获取审核队列失败: ${response.statusCode} ${response.body}');
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .whereType<Map<String, dynamic>>()
        .map((e) => PendingMediaItem(
              sci: e['sci'] as String? ?? '',
              cn: e['cn'] as String? ?? '',
              en: e['en'] as String? ?? '',
              kind: e['kind'] as String? ?? 'images',
              file: e['file'] as String? ?? '',
              url: e['url'] as String? ?? '',
              contributor: e['contributor'] as String? ?? '',
              uploaderId: e['uploader_id'] as String? ?? '',
              uploaderName: e['uploader_name'] as String? ?? '',
              uploadedAt: (e['uploaded_at'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  Future<void> approve({
    required String sci,
    required String file,
    required String token,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/admin/approve'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'sci': sci, 'file': file, 'token': token}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('审批失败: ${response.statusCode} ${response.body}');
    }
  }

  Future<void> reject({
    required String sci,
    required String file,
    required String token,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/admin/reject'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'sci': sci, 'file': file, 'token': token}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('拒绝失败: ${response.statusCode} ${response.body}');
    }
  }

  // ── 用户管理（仅 admin） ────────────────────────────────

  Future<List<UploadUser>> listUsers({required String token}) async {
    final uri = Uri.parse('$baseUrl/api/admin/users?token=$token');
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('获取用户列表失败: ${response.statusCode} ${response.body}');
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .whereType<Map<String, dynamic>>()
        .map((e) => UploadUser(
              token: e['token'] as String? ?? '',
              id: e['id'] as String? ?? '',
              role: e['role'] as String? ?? 'beta',
              name: e['name'] as String? ?? '',
              isSelf: e['is_self'] as bool? ?? false,
            ))
        .toList();
  }

  /// 创建新用户。custom_token 留空让服务器自动生成。
  Future<UploadUser> createUser({
    required String token,
    required String name,
    required String role,
    String? userId,
    String? customToken,
  }) async {
    final body = <String, dynamic>{'name': name, 'role': role};
    if (userId != null && userId.trim().isNotEmpty) body['id'] = userId.trim();
    if (customToken != null && customToken.trim().isNotEmpty) {
      body['token'] = customToken.trim();
    }
    final response = await _client.post(
      Uri.parse('$baseUrl/api/admin/users?token=$token'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('创建失败: ${response.statusCode} ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return UploadUser(
      token: data['token'] as String? ?? '',
      id: data['id'] as String? ?? '',
      role: data['role'] as String? ?? 'beta',
      name: data['name'] as String? ?? '',
      isSelf: false,
    );
  }

  // ── 反馈 ──────────────────────────────────────────────

  Future<void> submitFeedback({
    required String token,
    required String message,
    String page = '',
    String speciesCn = '',
    String speciesSci = '',
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/feedback?token=$token'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'message': message,
        'page': page,
        'species_cn': speciesCn,
        'species_sci': speciesSci,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('反馈上传失败: ${response.statusCode} ${response.body}');
    }
  }

  Future<List<AdminFeedbackEntry>> fetchAdminFeedback({required String token}) async {
    final response = await _client
        .get(Uri.parse('$baseUrl/api/admin/feedback?token=$token'))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('获取反馈失败: ${response.statusCode} ${response.body}');
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .whereType<Map<String, dynamic>>()
        .map(AdminFeedbackEntry.fromJson)
        .toList();
  }

  Future<void> resolveFeedback({
    required String token,
    required String id,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/admin/feedback/resolve?token=$token'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'id': id}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('标记失败: ${response.statusCode} ${response.body}');
    }
  }

  Future<void> deleteUser({
    required String token,
    required String targetToken,
  }) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/admin/users?token=$token'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'token': targetToken}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('删除失败: ${response.statusCode} ${response.body}');
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

  Future<void> setImageDifficulty({
    required String sci,
    required String file,
    required int difficulty,
    required String token,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/set_image_difficulty'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'sci': sci,
        'file': file,
        'difficulty': difficulty,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('图片难度上传失败: ${response.statusCode} ${response.body}');
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
