import 'package:archive/archive.dart';
import 'package:bird_flashcard/services/data_pack_safety.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Archive archiveWith(String path) {
    final archive = Archive();
    archive.addFile(ArchiveFile(path, 1, <int>[1]));
    return archive;
  }

  test('accepts ordinary relative ZIP entries', () {
    final entries = DataPackSafety.archiveEntries(
      archiveWith('images/Corvus_corax/photo.jpg'),
    );

    expect(entries.single.relativePath, 'images/Corvus_corax/photo.jpg');
  });

  test('rejects archive paths that could escape the staging directory', () {
    for (final path in <String>[
      '../outside.txt',
      '/absolute.txt',
      'images\\windows-path.jpg',
      'images//empty-segment.jpg',
    ]) {
      expect(
        () => DataPackSafety.archiveEntries(archiveWith(path)),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('rejects duplicate archive entries and unsafe pack names', () {
    final duplicate = Archive()
      ..addFile(ArchiveFile('species.json', 1, <int>[1]))
      ..addFile(ArchiveFile('manifest.json', 1, <int>[2]));
    // Archive.add() intentionally replaces matching paths, whereas a decoded
    // ZIP can contain duplicates. Force the iterable shape that the guard
    // receives after decoding to exercise the duplicate check.
    duplicate.modifyAtIndex(1, ArchiveFile('species.json', 1, <int>[2]));

    expect(
      () => DataPackSafety.archiveEntries(duplicate),
      throwsA(isA<FormatException>()),
    );
    for (final name in <String>['../../other.zip', '..', 'a/b.zip']) {
      expect(
        () => DataPackSafety.packName(name),
        throwsA(isA<FormatException>()),
      );
    }
  });
}
