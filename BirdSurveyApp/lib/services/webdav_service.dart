import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class WebDavConfig {
  final String url;
  final String username;
  final String password;

  const WebDavConfig({
    required this.url,
    required this.username,
    required this.password,
  });

  bool get isConfigured => url.isNotEmpty && username.isNotEmpty;

  static const _keyUrl  = 'webdav_url';
  static const _keyUser = 'webdav_user';
  static const _keyPass = 'webdav_pass';

  static Future<WebDavConfig> load() async {
    final p = await SharedPreferences.getInstance();
    return WebDavConfig(
      url:      p.getString(_keyUrl)  ?? '',
      username: p.getString(_keyUser) ?? '',
      password: p.getString(_keyPass) ?? '',
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyUrl,  url);
    await p.setString(_keyUser, username);
    await p.setString(_keyPass, password);
  }
}

class WebDavService {
  /// Upload a local file to the WebDAV server.
  /// Returns null on success, or an error message string on failure.
  static Future<String?> uploadFile(
      WebDavConfig config, File file, String remoteName) async {
    if (!config.isConfigured) return '未配置 WebDAV';

    final base = config.url.endsWith('/') ? config.url : '${config.url}/';
    final uri = Uri.parse('$base$remoteName');
    final auth = base64Encode(utf8.encode('${config.username}:${config.password}'));

    try {
      // Ensure remote directory exists (MKCOL is idempotent).
      await http.Client().send(http.Request('MKCOL', Uri.parse(base))
        ..headers['Authorization'] = 'Basic $auth');

      final bytes = await file.readAsBytes();
      final response = await http.put(
        uri,
        headers: {
          'Authorization': 'Basic $auth',
          'Content-Type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          'Content-Length': bytes.length.toString(),
        },
        body: bytes,
      );

      if (response.statusCode == 201 || response.statusCode == 204) {
        return null; // success
      }
      return 'HTTP ${response.statusCode}';
    } catch (e) {
      return e.toString();
    }
  }

  /// Test connection by sending an OPTIONS request.
  static Future<String?> testConnection(WebDavConfig config) async {
    if (!config.isConfigured) return '请先填写服务器地址和用户名';
    final uri = Uri.parse(config.url);
    final auth = base64Encode(utf8.encode('${config.username}:${config.password}'));
    try {
      final response = await http.Client()
          .send(http.Request('OPTIONS', uri)
            ..headers['Authorization'] = 'Basic $auth')
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 400) return null;
      return 'HTTP ${response.statusCode}，请检查地址和密码';
    } catch (e) {
      return '连接失败：$e';
    }
  }
}
