import 'dart:io';

import 'package:bird_flashcard/services/pack_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('pack_snapshot_test_');
  });

  tearDown(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  test('media resolution stays inside the snapshot pack', () async {
    final activePack = Directory('${tempRoot.path}/active')..createSync();
    final otherPack = Directory('${tempRoot.path}/other')..createSync();
    const relative = 'images/shared/photo.jpg';
    final activeFile = File('${activePack.path}/$relative')
      ..createSync(recursive: true)
      ..writeAsStringSync('active');
    File('${otherPack.path}/$relative')
      ..createSync(recursive: true)
      ..writeAsStringSync('other');
    File('${otherPack.path}/images/other-only.jpg')
      ..createSync(recursive: true)
      ..writeAsStringSync('other');

    final snapshot = await PackSnapshot.create(
      packDir: activePack.path,
      species: const [],
    );

    expect(snapshot.resolveMedia(relative), activeFile.path);
    expect(snapshot.resolveMedia('images/other-only.jpg'), isNull);
  });

  test('missing and escaping media paths never resolve', () async {
    final pack = Directory('${tempRoot.path}/pack')..createSync();
    final snapshot = await PackSnapshot.create(
      packDir: pack.path,
      species: const [],
    );

    expect(snapshot.resolveMedia('missing.jpg'), isNull);
    expect(snapshot.resolveMedia('../outside.jpg'), isNull);
    expect(snapshot.resolveMedia('/absolute.jpg'), isNull);
  });
}
