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

  factory AdminFeedbackEntry.fromJson(Map<String, dynamic> j) =>
      AdminFeedbackEntry(
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

class FeedbackReplyEntry {
  final String id;
  final String message;
  final String page;
  final String speciesCn;
  final String speciesSci;
  final int createdAt;
  final String status;
  final String reply;
  final String responder;
  final int repliedAt;

  const FeedbackReplyEntry({
    required this.id,
    required this.message,
    required this.page,
    required this.speciesCn,
    required this.speciesSci,
    required this.createdAt,
    required this.status,
    required this.reply,
    required this.responder,
    required this.repliedAt,
  });

  bool get hasReply => reply.trim().isNotEmpty;

  factory FeedbackReplyEntry.fromJson(Map<String, dynamic> j) {
    String str(List<String> keys) {
      for (final key in keys) {
        final value = j[key];
        if (value == null) continue;
        final text = '$value'.trim();
        if (text.isNotEmpty) return text;
      }
      return '';
    }

    int integer(List<String> keys) {
      for (final key in keys) {
        final value = j[key];
        if (value is num) return value.toInt();
        final parsed = int.tryParse('$value');
        if (parsed != null) return parsed;
      }
      return 0;
    }

    return FeedbackReplyEntry(
      id: str(['id', 'feedback_id']),
      message: str(['message', 'feedback', 'content']),
      page: str(['page']),
      speciesCn: str(['species_cn', 'speciesCn']),
      speciesSci: str(['species_sci', 'speciesSci']),
      createdAt: integer(['created_at', 'createdAt']),
      status: str(['status']),
      reply: str(['reply', 'reply_text', 'admin_reply', 'response']),
      responder: str(['reply_by', 'replier', 'responder', 'admin_name']),
      repliedAt: integer(['replied_at', 'reply_at', 'resolved_at']),
    );
  }
}

class UploadAccessRequestStatus {
  final String id;
  final String status;
  final String token;
  final String role;
  final String name;
  final String userId;
  final String reply;
  final int createdAt;
  final int updatedAt;
  final int resolvedAt;

  const UploadAccessRequestStatus({
    required this.id,
    required this.status,
    required this.token,
    required this.role,
    required this.name,
    required this.userId,
    required this.reply,
    required this.createdAt,
    required this.updatedAt,
    required this.resolvedAt,
  });

  bool get isNone => status == 'none' || status.isEmpty;
  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved' && token.isNotEmpty;
  bool get isRejected => status == 'rejected';

  factory UploadAccessRequestStatus.fromJson(Map<String, dynamic> j) {
    int integer(String key) {
      final value = j[key];
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? 0;
    }

    return UploadAccessRequestStatus(
      id: j['id'] as String? ?? '',
      status: j['status'] as String? ?? 'none',
      token: j['token'] as String? ?? '',
      role: j['role'] as String? ?? '',
      name: j['name'] as String? ?? '',
      userId: j['user_id'] as String? ?? '',
      reply: j['reply'] as String? ?? '',
      createdAt: integer('created_at'),
      updatedAt: integer('updated_at'),
      resolvedAt: integer('resolved_at'),
    );
  }
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

/// 上传权限申请（管理员视角，来自 /api/admin/token_requests）。
class AdminTokenRequest {
  final String clientId;
  final String status; // pending / approved / rejected
  final String note;
  final String platform;
  final String appVersion;
  final int createdAt;
  final String reason;
  final String name;

  const AdminTokenRequest({
    required this.clientId,
    required this.status,
    required this.note,
    required this.platform,
    required this.appVersion,
    required this.createdAt,
    required this.reason,
    required this.name,
  });

  bool get isPending => status == 'pending' || status.isEmpty;

  static int _asInt(dynamic v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

  factory AdminTokenRequest.fromJson(Map<String, dynamic> j) =>
      AdminTokenRequest(
        clientId: (j['client_id'] ?? '').toString(),
        status: (j['status'] ?? 'pending').toString(),
        note: (j['note'] ?? '').toString(),
        platform: (j['platform'] ?? '').toString(),
        appVersion: (j['app_version'] ?? '').toString(),
        createdAt: _asInt(j['created_at']),
        reason: (j['reason'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
      );
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
  final String uploaderRole;
  final String uploaderName;
  final int uploadedAt;
  final String description;
  final String features;
  final String location;
  final int suggestedDifficulty;
  const PendingMediaItem({
    required this.sci,
    required this.cn,
    required this.en,
    required this.kind,
    required this.file,
    required this.url,
    required this.contributor,
    required this.uploaderId,
    required this.uploaderRole,
    required this.uploaderName,
    required this.uploadedAt,
    this.description = '',
    this.features = '',
    this.location = '',
    this.suggestedDifficulty = 0,
  });
}

class HistoryItem {
  final String sci;
  final String cn;
  final String en;
  final String kind;
  final String file;
  final String url;
  final String contributor;
  final String uploaderId;
  final String uploaderRole;
  final String uploaderName;
  final int uploadedAt;
  final int approvedAt;
  final String description;
  final String location;
  const HistoryItem({
    required this.sci,
    required this.cn,
    required this.en,
    required this.kind,
    required this.file,
    required this.url,
    required this.contributor,
    required this.uploaderId,
    required this.uploaderRole,
    required this.uploaderName,
    required this.uploadedAt,
    required this.approvedAt,
    required this.description,
    required this.location,
  });
}

class SpeciesMediaCount {
  final int images;
  final int audio;
  final int pendingImages;
  final int pendingAudio;
  const SpeciesMediaCount({
    required this.images,
    required this.audio,
    required this.pendingImages,
    required this.pendingAudio,
  });
}

class AdminUploadService {
  final String baseUrl;
  final http.Client _client;

  AdminUploadService({
    this.baseUrl = ServerMediaService.defaultBaseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Map<String, String> _authHeaders(String token, {bool json = false}) => {
        'Authorization': 'Bearer ${token.trim()}',
        if (json) 'Content-Type': 'application/json',
      };

  Future<void> uploadMedia({
    required Species species,
    required String filePath,
    required String token,
    String contributor = '管理员上传',
    String mediaType = '',
    String audioType = '',
    String license = 'CC BY-NC 4.0',
    String location = '',
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/upload'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['sci'] = species.sci;
    request.fields['contributor'] = contributor;
    if (mediaType.isNotEmpty) request.fields['media_type'] = mediaType;
    if (audioType.isNotEmpty) request.fields['audio_type'] = audioType;
    request.fields['license'] = license;
    if (location.trim().isNotEmpty) {
      request.fields['location'] = location.trim();
    }
    request.files.add(await http.MultipartFile.fromPath('files', filePath));

    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('服务器上传失败: ${response.statusCode} $body');
    }
  }

  /// 通用上传：返回服务器响应（含 saved/failed）。供新上传 UI 使用。
  /// 如果服务器 200 但 saved 为空、failed 不空（典型如"species not recognized"），
  /// 抛出含具体原因的异常，避免 UI 误以为上传成功。
  Future<Map<String, dynamic>> uploadFile({
    required String sci,
    required String contributor,
    required String filePath,
    required String token,
    int difficulty = 0,
    String description = '',
    String mediaType = '',
    String audioType = '',
    String license = 'CC BY-NC 4.0',
    String location = '',
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/upload'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['sci'] = sci;
    request.fields['contributor'] = contributor;
    if (mediaType.isNotEmpty) request.fields['media_type'] = mediaType;
    if (audioType.isNotEmpty) request.fields['audio_type'] = audioType;
    request.fields['license'] = license;
    if (location.trim().isNotEmpty) {
      request.fields['location'] = location.trim();
    }
    if (description.trim().isNotEmpty) {
      request.fields['description'] = description.trim();
    }
    if (difficulty > 0) request.fields['difficulty'] = '$difficulty';
    request.files.add(await http.MultipartFile.fromPath('files', filePath));
    final streamed = await request.send().timeout(const Duration(seconds: 120));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception('HTTP ${streamed.statusCode}: $body');
    }
    final data = jsonDecode(body) as Map<String, dynamic>;
    final saved = (data['saved'] as List?) ?? const [];
    final failed = (data['failed'] as List?) ?? const [];
    if (saved.isEmpty && failed.isNotEmpty) {
      final reason = (failed.first as Map)['reason'] ?? '未知原因';
      throw Exception('服务器拒收：$reason');
    }
    return data;
  }

  Future<void> deleteServerMedia({
    required String sci,
    required String kind,
    required String file,
    required String token,
  }) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/admin/media'),
      headers: _authHeaders(token, json: true),
      body: jsonEncode({
        'sci': sci,
        'kind': kind,
        'file': file,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('删除失败: ${response.statusCode} ${response.body}');
    }
  }

  Future<List<HistoryItem>> fetchHistory({
    required String token,
    String query = '',
    String sci = '',
    int limit = 200,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      if (query.isNotEmpty) 'q': query,
      if (sci.isNotEmpty) 'sci': sci,
    };
    final uri = Uri.parse('$baseUrl/api/admin/history')
        .replace(queryParameters: params);
    final response = await _client
        .get(uri, headers: _authHeaders(token))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('获取审核历史失败: ${response.statusCode} ${response.body}');
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .whereType<Map<String, dynamic>>()
        .map((e) => HistoryItem(
              sci: e['sci'] as String? ?? '',
              cn: e['cn'] as String? ?? '',
              en: e['en'] as String? ?? '',
              kind: e['kind'] as String? ?? 'images',
              file: e['file'] as String? ?? '',
              url: e['url'] as String? ?? '',
              contributor: e['contributor'] as String? ?? '',
              uploaderId: e['uploader_id'] as String? ?? '',
              uploaderRole: e['uploader_role'] as String? ?? '',
              uploaderName: e['uploader_name'] as String? ?? '',
              uploadedAt: (e['uploaded_at'] as num?)?.toInt() ?? 0,
              approvedAt: (e['approved_at'] as num?)?.toInt() ?? 0,
              description: e['description'] as String? ?? '',
              location: e['location'] as String? ?? '',
            ))
        .toList();
  }

  Future<SpeciesMediaCount> fetchSpeciesMediaCount(
      {required String sci}) async {
    final uri = Uri.parse('$baseUrl/api/species_media_count')
        .replace(queryParameters: {'sci': sci});
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      return const SpeciesMediaCount(
          images: 0, audio: 0, pendingImages: 0, pendingAudio: 0);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return SpeciesMediaCount(
      images: (data['images'] as num?)?.toInt() ?? 0,
      audio: (data['audio'] as num?)?.toInt() ?? 0,
      pendingImages: (data['pending_images'] as num?)?.toInt() ?? 0,
      pendingAudio: (data['pending_audio'] as num?)?.toInt() ?? 0,
    );
  }

  Future<WhoAmI?> whoami({required String token}) async {
    if (token.trim().isEmpty) return null;
    final uri = Uri.parse('$baseUrl/api/whoami');
    final response = await _client
        .get(uri, headers: _authHeaders(token))
        .timeout(const Duration(seconds: 15));
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
    final uri = Uri.parse('$baseUrl/api/upload_stats');
    final response = await _client
        .get(uri, headers: _authHeaders(token))
        .timeout(const Duration(seconds: 15));
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

  Future<UploadAccessRequestStatus> submitUploadAccessRequest({
    required String clientId,
    String note = '',
    String platform = '',
    String appVersion = '',
    String appBuild = '',
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/token_requests'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'client_id': clientId,
            'note': note,
            'platform': platform,
            'app_version': appVersion,
            'app_build': appBuild,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('申请失败: ${response.statusCode} ${response.body}');
    }
    return UploadAccessRequestStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<UploadAccessRequestStatus> fetchUploadAccessRequestStatus({
    required String clientId,
  }) async {
    if (clientId.trim().isEmpty) {
      return UploadAccessRequestStatus.fromJson(const {'status': 'none'});
    }
    final uri = Uri.parse('$baseUrl/api/token_requests/status')
        .replace(queryParameters: {'client_id': clientId.trim()});
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('获取申请状态失败: ${response.statusCode} ${response.body}');
    }
    return UploadAccessRequestStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<PendingMediaItem>> fetchPending({required String token}) async {
    final uri = Uri.parse('$baseUrl/api/admin/pending');
    final response = await _client
        .get(uri, headers: _authHeaders(token))
        .timeout(const Duration(seconds: 30));
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
              uploaderRole: e['uploader_role'] as String? ?? '',
              uploaderName: e['uploader_name'] as String? ?? '',
              uploadedAt: (e['uploaded_at'] as num?)?.toInt() ?? 0,
              description: e['description'] as String? ?? '',
              features: e['features'] as String? ?? '',
              location: e['location'] as String? ?? '',
              suggestedDifficulty:
                  (e['suggested_difficulty'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  Future<void> approve({
    required String sci,
    required String file,
    required String token,
    bool pin = false,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/admin/approve'),
      headers: _authHeaders(token, json: true),
      body: jsonEncode({'sci': sci, 'file': file, 'pin': pin}),
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
      headers: _authHeaders(token, json: true),
      body: jsonEncode({'sci': sci, 'file': file}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('拒绝失败: ${response.statusCode} ${response.body}');
    }
  }

  Future<void> deleteMedia({
    required String sci,
    required String file,
    required String kind,
    required String token,
  }) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/admin/media'),
      headers: _authHeaders(token, json: true),
      body: jsonEncode({
        'sci': sci,
        'file': file,
        'kind': kind,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('删除失败: ${response.statusCode} ${response.body}');
    }
  }

  Future<List<Map<String, dynamic>>> fetchRateQueue({
    required String token,
  }) async {
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/admin/rate/queue'),
          headers: _authHeaders(token),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('评级队列加载失败: ${response.statusCode} ${response.body}');
    }
    final data = jsonDecode(response.body);
    final list =
        data is Map ? (data['items'] as List<dynamic>? ?? const []) : const [];
    return list.whereType<Map<String, dynamic>>().toList();
  }

  // ── 上传权限申请审核（仅 admin） ──────────────────────────

  Future<List<AdminTokenRequest>> fetchTokenRequests({
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/api/admin/token_requests');
    final response = await _client
        .get(uri, headers: _authHeaders(token))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('获取申请列表失败: ${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    // 服务器返回 {"items":[...]}（dict）；老格式可能是裸列表，两者都兼容。
    final list = decoded is List
        ? decoded
        : (decoded is Map<String, dynamic>
            ? (decoded['items'] as List<dynamic>? ?? const [])
            : const []);
    return list
        .whereType<Map<String, dynamic>>()
        .map(AdminTokenRequest.fromJson)
        .toList();
  }

  Future<void> approveTokenRequest({
    required String clientId,
    String name = '',
    required String token,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/admin/token_requests/approve'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'client_id': clientId, 'name': name}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('批准失败: ${response.statusCode} ${response.body}');
    }
  }

  Future<void> rejectTokenRequest({
    required String clientId,
    String reason = '',
    required String token,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/admin/token_requests/reject'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'client_id': clientId, 'reason': reason}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('拒绝失败: ${response.statusCode} ${response.body}');
    }
  }

  // ── 用户管理（仅 admin） ────────────────────────────────

  Future<List<UploadUser>> listUsers({required String token}) async {
    final uri = Uri.parse('$baseUrl/api/admin/users');
    final response = await _client
        .get(uri, headers: _authHeaders(token))
        .timeout(const Duration(seconds: 15));
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
      Uri.parse('$baseUrl/api/admin/users'),
      headers: _authHeaders(token, json: true),
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
    String clientId = '',
    Map<String, dynamic> context = const {},
  }) async {
    final body = <String, dynamic>{
      'message': message,
      'page': page,
      'species_cn': speciesCn,
      'species_sci': speciesSci,
    };
    if (clientId.trim().isNotEmpty) {
      body['client_id'] = clientId.trim();
    }
    body.addAll(context);
    final response = await _client.post(
      Uri.parse('$baseUrl/api/feedback'),
      headers: _authHeaders(token, json: true),
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('反馈上传失败: ${response.statusCode} ${response.body}');
    }
  }

  Future<List<AdminFeedbackEntry>> fetchAdminFeedback(
      {required String token}) async {
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/admin/feedback'),
          headers: _authHeaders(token),
        )
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

  Future<List<FeedbackReplyEntry>> fetchFeedbackReplies({
    String token = '',
    String clientId = '',
  }) async {
    final query = <String, String>{};
    if (clientId.trim().isNotEmpty) query['client_id'] = clientId.trim();
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/feedback/replies')
              .replace(queryParameters: query),
          headers: token.trim().isEmpty ? const {} : _authHeaders(token),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('获取反馈通知失败: ${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    final List<dynamic> rawList;
    if (decoded is List) {
      rawList = decoded;
    } else if (decoded is Map<String, dynamic>) {
      final nested = decoded['replies'] ?? decoded['items'] ?? decoded['data'];
      rawList = nested is List ? nested : const [];
    } else {
      rawList = const [];
    }
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(FeedbackReplyEntry.fromJson)
        .toList()
      ..sort((a, b) {
        final ar = a.repliedAt > 0 ? a.repliedAt : a.createdAt;
        final br = b.repliedAt > 0 ? b.repliedAt : b.createdAt;
        return br.compareTo(ar);
      });
  }

  Future<void> resolveFeedback({
    required String token,
    required String id,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/admin/feedback/resolve'),
      headers: _authHeaders(token, json: true),
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
      Uri.parse('$baseUrl/api/admin/users'),
      headers: _authHeaders(token, json: true),
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

  /// 逐种评级提交：管理员直接生效、内测进待审队列（服务器按 token 角色判定）。
  /// file 为空=物种难度；否则=该图质量难度。返回是否进入待审队列（pending）。
  Future<bool> submitRating({
    required String sci,
    String file = '',
    String zh = '',
    required int difficulty,
    required String token,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/rate/submit'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'sci': sci,
        if (file.isNotEmpty) 'file': file,
        if (zh.isNotEmpty) 'zh': zh,
        'difficulty': difficulty,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('评级提交失败: ${response.statusCode} ${response.body}');
    }
    final data = jsonDecode(response.body);
    return data is Map && data['pending'] == true;
  }

  /// 管理员：拉取内测用户的待审评级队列。
  Future<List<Map<String, dynamic>>> fetchPendingRatings({
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/api/admin/rate/pending');
    final response = await _client.get(uri, headers: _authHeaders(token));
    if (response.statusCode != 200) {
      throw Exception('待审评级加载失败: ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    final list =
        data is Map ? (data['items'] as List<dynamic>? ?? const []) : const [];
    return list.whereType<Map<String, dynamic>>().toList();
  }

  /// 管理员：审核一条待审评级（approve=true 写入 manifest，否则丢弃）。
  Future<void> resolveRating({
    required String id,
    required bool approve,
    required String token,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/admin/rate/resolve'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'id': id, 'approve': approve}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('评级审核失败: ${response.statusCode} ${response.body}');
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
