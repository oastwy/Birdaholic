import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update_service.dart';
import '../services/resumable_apk_downloader.dart';

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
    var receivedBytes = 0;
    var totalBytes = 0;
    try {
      final dir = await getTemporaryDirectory();
      final safeVersion =
          widget.info.version.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
      final destination =
          File('${dir.path}/birdaholic-update-$safeVersion.apk');
      final partial = File('${destination.path}.part');
      final priorBytes = await partial.exists() ? await partial.length() : 0;
      if (priorBytes > 0 && mounted) {
        setState(() => _status = '发现未完成下载，正在从已下载部分继续…');
      }

      final apk = await ResumableApkDownloader().download(
        url: Uri.parse(widget.info.apkAssetUrl!),
        partialFile: partial,
        destination: destination,
        cancelToken: cancel,
        expectedSha256: widget.info.sha256,
        onProgress: (received, total) {
          receivedBytes = received;
          totalBytes = total;
          if (!mounted || total <= 0) return;
          setState(() {
            _pct = (received / total * 100).round();
            _status =
                '下载中 $_pct%（${_formatBytes(received)} / ${_formatBytes(total)}）';
          });
        },
      );
      if (!mounted) return;
      setState(() => _status = '下载完成,正在拉起安装…');
      final result = await OpenFilex.open(apk.path);
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
            : '下载完成但拉起安装失败,可点"手动下载"去下载页装。';
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
            ? _resumeHint(receivedBytes, totalBytes, '已取消下载')
            : stalled
                ? _resumeHint(receivedBytes, totalBytes, '下载卡住了')
                : _resumeHint(receivedBytes, totalBytes, '下载出错');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _failed = true;
        _status = _resumeHint(receivedBytes, totalBytes, '下载出错');
      });
    }
  }

  String _resumeHint(int received, int total, String prefix) {
    if (received <= 0) return '$prefix，可点"重试"或"手动下载"。';
    final detail = total > 0
        ? '${_formatBytes(received)} / ${_formatBytes(total)}'
        : _formatBytes(received);
    return '$prefix，已保留 $detail；点"重试"将从断点继续。';
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  // 一键下载/安装失败时的兜底：打开下载页让用户手动安装 arm64 包。
  Future<void> _openDownloadPage() async {
    final uri = Uri.parse(widget.info.downloadUrl);
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false; // 无可用浏览器等场景 launchUrl 会抛异常，按打不开处理。
    }
    if (!mounted) return;
    if (ok) {
      // 已交给浏览器下载，本弹窗无事可做，关掉——否则用户返回后停在红色失败态。
      Navigator.of(context).pop();
      return;
    }
    setState(() => _status = '打不开下载页，请手动访问 birding.today/download.html');
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
              if (_failed)
                TextButton(
                    onPressed: _openDownloadPage, child: const Text('手动下载')),
              FilledButton(
                  onPressed: _start, child: Text(_failed ? '重试' : '立即更新')),
            ],
    );
  }
}
