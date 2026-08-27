import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// Downloads an APK to [destination] while retaining [partialFile] on errors.
///
/// The next call requests the remaining bytes with HTTP Range. If a server
/// ignores Range and returns a full response, the partial file is discarded and
/// that response is used from byte zero, preventing a corrupt APK.
class ResumableApkDownloader {
  ResumableApkDownloader({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<File> download({
    required Uri url,
    required File partialFile,
    required File destination,
    required CancelToken cancelToken,
    String? expectedSha256,
    void Function(int received, int total)? onProgress,
  }) async {
    var existingBytes =
        await partialFile.exists() ? await partialFile.length() : 0;
    var response = await _request(url, existingBytes, cancelToken);

    // 416 means the stale partial file is no longer valid for this resource.
    if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
      await _discardPartial(partialFile);
      existingBytes = 0;
      response = await _request(url, 0, cancelToken);
    } else if (existingBytes > 0 && response.statusCode == HttpStatus.ok) {
      // The server ignored Range but has already sent the complete file. Reuse
      // this response from byte zero instead of downloading it a second time.
      await _discardPartial(partialFile);
      existingBytes = 0;
    }

    final statusCode = response.statusCode;
    if (statusCode != HttpStatus.ok &&
        statusCode != HttpStatus.partialContent) {
      throw HttpException('下载服务器返回 HTTP $statusCode', uri: url);
    }

    final body = response.data;
    if (body == null) {
      throw HttpException('下载服务器未返回文件内容', uri: url);
    }

    final totalBytes = _totalBytes(response, existingBytes);
    var receivedBytes = existingBytes;
    onProgress?.call(receivedBytes, totalBytes);

    final sink = partialFile.openWrite(
      mode: existingBytes > 0 ? FileMode.append : FileMode.write,
    );
    try {
      await for (final chunk in body.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        onProgress?.call(receivedBytes, totalBytes);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (totalBytes > 0 && receivedBytes != totalBytes) {
      throw HttpException('下载不完整，请重试继续下载', uri: url);
    }

    final expected = expectedSha256?.trim().toLowerCase();
    if (expected != null && expected.isNotEmpty) {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
        throw ArgumentError.value(
            expectedSha256, 'expectedSha256', '必须是 SHA-256');
      }
      final actual =
          (await sha256.bind(partialFile.openRead()).first).toString();
      if (actual != expected) {
        await _discardPartial(partialFile);
        throw HttpException('更新包校验失败，已丢弃损坏文件，请重试', uri: url);
      }
    }

    if (await destination.exists()) {
      await destination.delete();
    }
    return partialFile.rename(destination.path);
  }

  Future<Response<ResponseBody>> _request(
    Uri url,
    int start,
    CancelToken cancelToken,
  ) {
    return _dio.get<ResponseBody>(
      url.toString(),
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: start > 0 ? {HttpHeaders.rangeHeader: 'bytes=$start-'} : null,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 30),
        validateStatus: (status) =>
            status == HttpStatus.ok ||
            status == HttpStatus.partialContent ||
            status == HttpStatus.requestedRangeNotSatisfiable,
      ),
    );
  }

  int _totalBytes(Response<ResponseBody> response, int existingBytes) {
    final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
    final totalMatch = RegExp(r'/([0-9]+)$').firstMatch(contentRange ?? '');
    if (totalMatch != null) return int.parse(totalMatch.group(1)!);

    final contentLength = int.tryParse(
        response.headers.value(HttpHeaders.contentLengthHeader) ?? '');
    if (contentLength == null) return 0;
    return response.statusCode == HttpStatus.partialContent
        ? existingBytes + contentLength
        : contentLength;
  }

  Future<void> _discardPartial(File partialFile) async {
    if (await partialFile.exists()) {
      await partialFile.delete();
    }
  }
}
