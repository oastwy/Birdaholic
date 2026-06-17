import 'package:flutter_test/flutter_test.dart';
import 'package:bird_flashcard/services/pinyin.dart';

void main() {
  group('Pinyin.initials（搜索用拼音首字母）', () {
    test('常见鸟名取首字母', () {
      expect(Pinyin.initials('白头鹤'), 'bth');
      expect(Pinyin.initials('黑脸琵鹭'), 'hlpl');
      expect(Pinyin.initials('鹪鹩'), 'jl');
    });

    test('空字符串返回空', () {
      expect(Pinyin.initials(''), '');
    });

    test('结果恒为小写', () {
      final s = Pinyin.initials('家燕');
      expect(s, s.toLowerCase());
    });
  });
}
