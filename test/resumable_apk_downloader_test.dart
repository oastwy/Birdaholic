import 'dart:io';

import 'package:bird_flashcard/services/resumable_apk_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const payload = 'Birdaholic resumable update payload';

  Future<void> runWithServer(
    Future<void> Function(Uri url) testBody, {
    required bool supportsRange,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      final rangeMatch =
          range == null ? null : RegExp(r'^bytes=([0-9]+)-$').firstMatch(range);
      final start = supportsRange && rangeMatch != null
          ? int.parse(rangeMatch.group(1)!)
          : 0;
      final bytes = payload.codeUnits.sublist(start);
      if (supportsRange && range != null) {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-${payload.length - 1}/${payload.length}',
        );
      }
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    });
    addTearDown(server.close);
    await testBody(
        Uri.parse('http://${server.address.address}:${server.port}/apk'));
  }

  test('resumes an existing partial file with Range', () async {
    await runWithServer((url) async {
      final dir = await Directory.systemTemp.createTemp('resume-apk-test');
      addTearDown(() => dir.delete(recursive: true));
      final partial = File('${dir.path}/update.apk.part');
      await partial.writeAsString(payload.substring(0, 10));

      final result = await ResumableApkDownloader().download(
        url: url,
        partialFile: partial,
        destination: File('${dir.path}/update.apk'),
        cancelToken: CancelToken(),
      );

      expect(await result.readAsString(), payload);
      expect(await partial.exists(), isFalse);
    }, supportsRange: true);
  });

  test('restarts safely when the server ignores Range', () async {
    await runWithServer((url) async {
      final dir = await Directory.systemTemp.createTemp('resume-apk-test');
      addTearDown(() => dir.delete(recursive: true));
      final partial = File('${dir.path}/update.apk.part');
      await partial.writeAsString('stale partial data');

      final result = await ResumableApkDownloader().download(
        url: url,
        partialFile: partial,
        destination: File('${dir.path}/update.apk'),
        cancelToken: CancelToken(),
      );

      expect(await result.readAsString(), payload);
    }, supportsRange: false);
  });

  test('verifies the final APK checksum before installing', () async {
    await runWithServer((url) async {
      final dir = await Directory.systemTemp.createTemp('resume-apk-test');
      addTearDown(() => dir.delete(recursive: true));
      final result = await ResumableApkDownloader().download(
        url: url,
        partialFile: File('${dir.path}/update.apk.part'),
        destination: File('${dir.path}/update.apk'),
        cancelToken: CancelToken(),
        expectedSha256: sha256.convert(payload.codeUnits).toString(),
      );

      expect(await result.readAsString(), payload);
    }, supportsRange: true);
  });

  test('discards an APK when its checksum does not match', () async {
    await runWithServer((url) async {
      final dir = await Directory.systemTemp.createTemp('resume-apk-test');
      addTearDown(() => dir.delete(recursive: true));
      final partial = File('${dir.path}/update.apk.part');
      final destination = File('${dir.path}/update.apk');

      await expectLater(
        ResumableApkDownloader().download(
          url: url,
          partialFile: partial,
          destination: destination,
          cancelToken: CancelToken(),
          expectedSha256: List<String>.filled(64, '0').join(),
        ),
        throwsA(isA<HttpException>()),
      );

      expect(await partial.exists(), isFalse);
      expect(await destination.exists(), isFalse);
    }, supportsRange: true);
  });
}
