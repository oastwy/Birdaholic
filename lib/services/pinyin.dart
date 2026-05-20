import 'package:lpinyin/lpinyin.dart';

/// 中文拼音首字母工具。基于 lpinyin 库，覆盖准确。
class Pinyin {
  /// 给定中文文本，返回每个汉字首字母拼成的小写字符串。
  /// 非汉字字符保持原样（小写）。
  /// 例：`Pinyin.initials("白头鹤")` → `"bth"`
  static String initials(String text) {
    if (text.isEmpty) return '';
    // PinyinHelper.getShortPinyin 返回首字母组合，已是小写
    try {
      return PinyinHelper.getShortPinyin(text).toLowerCase();
    } catch (_) {
      return '';
    }
  }
}
