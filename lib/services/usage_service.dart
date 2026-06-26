import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../app_version.dart';
import 'server_media_service.dart';
import 'storage.dart';

/// 启动时匿名上报本机随机 ID + 平台/版本，供服务器端统计装机量与活跃度。
///
/// 设计原则：
/// - 复用反馈/权限申请已有的匿名 client_id，不引入新权限、不收集任何个人信息。
/// - 服务器不记录 IP。
/// - 完全 fire-and-forget：任何异常都吞掉，绝不阻断或拖慢 App 启动。
/// - 只应在用户已同意隐私协议后调用（调用点见 main.dart 的 _ConsentGate）。
class UsageService {
  static Future<void> recordAppOpen(StorageService storage) async {
    try {
      final clientId = await storage.ensureFeedbackClientId();
      if (clientId.isEmpty) return;
      final uri = Uri.parse('${ServerMediaService.defaultBaseUrl}/api/ping');
      await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'client_id': clientId,
              'platform': Platform.operatingSystem,
              'app_version': appVersionName,
              'app_build': appBuildNumber,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // 统计失败不影响使用，静默忽略。
    }
  }
}
