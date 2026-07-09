import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../services/app_update_service.dart';

/// 应用内一键下载并拉起安装（仅 Android，见 progress_screen 的更新横幅）。
/// 卡住(30秒无新字节)会报错转成可重试，不会像老式 OTA 插件那样无限干等。
class UpdateDownloadDialog extends StatefulWidget {
  final AppUpdateInfo info;
  const UpdateDownloadDialog({super.key, required this.info});

  @override
  State<UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<UpdateDownloadDialog> {
  bool _downloading = false;
  bool _failed = false;
  String _status = '';
  int _pct = 0;
  CancelToken? _cancel;

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _downloading = true;
      _failed = false;
      _status = '开始下载…';
      _pct = 0;
    });
    final cancel = CancelToken();
    _cancel = cancel;
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/birdaholic-update.apk';
      await Dio().download(
        widget.info.apkAssetUrl!,
        path,
        cancelToken: cancel,
        deleteOnError: true,
        options: Options(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
        onReceiveProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() {
            _pct = (received / total * 100).round();
            _status = '下载中 $_pct%';
          });
        },
      );
      if (!mounted) return;
      setState(() => _status = '下载完成,正在拉起安装…');
      final result = await OpenFilex.open(path);
      if (!mounted) return;
      if (result.type == ResultType.done) {
        // 安装器已在前台。关掉本弹窗——否则用户从安装界面按返回后会卡在
        // _downloading=true 的无按钮态(barrierDismissible:false)，只能强杀 App。
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _downloading = false;
        _failed = true;
        _status = result.type == ResultType.permissionDenied
            ? '需要允许"安装未知应用"权限,去系统设置打开后重试。'
            : '下载完成但拉起安装失败,可改用浏览器打开下载页手动装。';
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final stalled = e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionTimeout;
      setState(() {
        _downloading = false;
        _failed = true;
        _status = e.type == DioExceptionType.cancel
            ? '已取消下载。'
            : stalled
                ? '下载卡住了,可点"重试",或改用浏览器打开下载页手动装。'
                : '下载出错,可点"重试"或改用浏览器手动装。';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _failed = true;
        _status = '出错: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('发现新版本 ${widget.info.version}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_downloading) ...[
            LinearProgressIndicator(value: _pct > 0 ? _pct / 100 : null),
            const SizedBox(height: 8),
            Text(_status),
          ] else if (_status.isNotEmpty) ...[
            Text(_status,
                style: TextStyle(
                    color: _failed ? Colors.red[700] : null, height: 1.4)),
          ] else
            const Text('点击"立即更新"下载并安装。'),
        ],
      ),
      // 下载中也给一个「取消」，否则连接卡住(barrierDismissible:false)时无从退出。
      actions: _downloading
          ? [
              TextButton(
                onPressed: () => _cancel?.cancel(),
                child: const Text('取消'),
              ),
            ]
          : [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(_failed ? '关闭' : '以后再说')),
              FilledButton(
                  onPressed: _start,
                  child: Text(_failed ? '重试' : '立即更新')),
            ],
    );
  }
}
