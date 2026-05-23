import 'dart:convert';

import 'package:http/http.dart' as http;

class SyncIdentity {
  final String tokenId;
  final String role;
  final String label;
  final String organizationId;
  final String organizationName;
  final String projectId;
  final String projectName;

  const SyncIdentity({
    required this.tokenId,
    required this.role,
    required this.label,
    required this.organizationId,
    required this.organizationName,
    required this.projectId,
    required this.projectName,
  });

  factory SyncIdentity.fromJson(Map<String, dynamic> json) => SyncIdentity(
    tokenId: json['tokenId']?.toString() ?? '',
    role: json['role']?.toString() ?? '',
    label: json['label']?.toString() ?? '',
    organizationId: json['organizationId']?.toString() ?? '',
    organizationName: json['organizationName']?.toString() ?? '',
    projectId: json['projectId']?.toString() ?? '',
    projectName: json['projectName']?.toString() ?? '',
  );

  String get display {
    final org = organizationName.isEmpty ? '未绑定机构' : organizationName;
    final project = projectName.isEmpty ? '全部项目' : projectName;
    final name = label.isEmpty ? tokenId : label;
    return '$role · $org · $project · $name';
  }
}

class CloudProject {
  final String id;
  final String name;
  final String organizationId;
  final String organizationName;

  const CloudProject({
    required this.id,
    required this.name,
    required this.organizationId,
    required this.organizationName,
  });

  factory CloudProject.fromJson(Map<String, dynamic> json) => CloudProject(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    organizationId: json['organizationId']?.toString() ?? '',
    organizationName: json['organizationName']?.toString() ?? '',
  );
}

class SyncService {
  final String serverUrl;
  final String token;
  final http.Client _client;

  SyncService({
    required String serverUrl,
    required this.token,
    http.Client? client,
  }) : serverUrl = serverUrl.trim().replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client();

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  Future<SyncIdentity> validateToken() async {
    final res = await _client
        .get(Uri.parse('$serverUrl/me'), headers: _headers)
        .timeout(const Duration(seconds: 12));
    _throwIfBad(res);
    return SyncIdentity.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<CloudProject>> fetchProjects() async {
    final res = await _client
        .get(Uri.parse('$serverUrl/projects'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    _throwIfBad(res);
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (json['projects'] as List? ?? const []);
    return items
        .map((e) => CloudProject.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> syncProject({
    required String projectId,
    required List<Map<String, dynamic>> surveySessions,
    required List<Map<String, dynamic>> surveyPoints,
    required List<Map<String, dynamic>> fieldConfigs,
    required DateTime? since,
  }) async {
    final uri = Uri.parse('$serverUrl/projects/$projectId/sync').replace(
      queryParameters:
          since == null ? null : {'since': since.toUtc().toIso8601String()},
    );
    final res = await _client
        .post(
          uri,
          headers: _headers,
          body: jsonEncode({
            'surveySessions': surveySessions,
            'surveyPoints': surveyPoints,
            'fieldConfigs': fieldConfigs,
          }),
        )
        .timeout(const Duration(seconds: 30));
    _throwIfBad(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  void _throwIfBad(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    String message = res.body;
    try {
      final json = jsonDecode(res.body);
      message = json['detail']?.toString() ?? message;
    } catch (_) {}
    throw Exception('HTTP ${res.statusCode}: $message');
  }
}
