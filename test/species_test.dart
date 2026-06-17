import 'package:flutter_test/flutter_test.dart';
import 'package:bird_flashcard/models/species.dart';

void main() {
  group('Species.fromJson', () {
    test('最小字段：难度默认 1，无图无音频', () {
      final s = Species.fromJson({'cn': '测试鸟', 'en': 'Test Bird', 'sci': 'Testus birdus'});
      expect(s.cn, '测试鸟');
      expect(s.difficulty, 1);
      expect(s.hasImage, false);
      expect(s.hasAudio, false);
    });

    test('legacy image 字段并入 images，imageFiles 去重', () {
      final s = Species.fromJson({
        'cn': '白鹭',
        'en': 'Little Egret',
        'sci': 'Egretta garzetta',
        'image': 'images/a.jpg',
        'images': [
          {'file': 'images/a.jpg'}, // 与 legacy 重复，应去重
          {'file': 'images/b.jpg'},
        ],
      });
      expect(s.hasImage, true);
      expect(s.imageFiles, ['images/a.jpg', 'images/b.jpg']);
    });

    test('保护级别文本', () {
      final g1 = Species.fromJson({'cn': 'x', 'en': 'x', 'sci': 'x', 'cons': '1'});
      final g2 = Species.fromJson({'cn': 'x', 'en': 'x', 'sci': 'x', 'cons': '2'});
      final none = Species.fromJson({'cn': 'x', 'en': 'x', 'sci': 'x'});
      expect(g1.isGrade1, true);
      expect(g1.consText, '国家一级保护');
      expect(g2.consText, '国家二级保护');
      expect(none.consText, '');
    });
  });

  group('SpeciesImageInfo 难度', () {
    test('难度越界被 clamp 到 [1,5]', () {
      expect(SpeciesImageInfo.fromJson({'file': 'images/x.jpg', 'difficulty': 9}).difficulty, 5);
      expect(SpeciesImageInfo.fromJson({'file': 'images/x.jpg', 'difficulty': 0}).difficulty, 1);
    });

    test('toJson：难度为 1（默认）时省略，非默认时写入', () {
      final def = const SpeciesImageInfo(file: 'images/x.jpg', difficulty: 1).toJson();
      expect(def.containsKey('difficulty'), false);
      final hard = const SpeciesImageInfo(file: 'images/x.jpg', difficulty: 4).toJson();
      expect(hard['difficulty'], 4);
    });
  });
}
