import 'audio_info.dart';

/// 鸟种数据模型
class Species {
  final String cn;          // 中文名
  final String en;          // 英文名
  final String sci;         // 学名
  final String cons;        // 保护等级: "1" | "2" | ""
  final String habitat;     // 栖息地
  final List<AudioInfo> audios;  // 音频列表
  final String? image;      // 图片相对路径

  const Species({
    required this.cn,
    required this.en,
    required this.sci,
    this.cons = '',
    this.habitat = '',
    this.audios = const [],
    this.image,
  });

  /// 是否有一级保护
  bool get isGrade1 => cons == '1';

  /// 是否有二级保护
  bool get isGrade2 => cons == '2';

  /// 是否有音频
  bool get hasAudio => audios.isNotEmpty;

  /// 是否有图片
  bool get hasImage => image != null;

  /// 保护等级显示文本
  String get consText {
    if (isGrade1) return '国家一级保护';
    if (isGrade2) return '国家二级保护';
    return '';
  }

  factory Species.fromJson(Map<String, dynamic> json) {
    final audioList = (json['audios'] as List<dynamic>?)
            ?.map((a) => AudioInfo.fromJson(a as Map<String, dynamic>))
            .toList() ??
        [];

    return Species(
      cn: json['cn'] as String,
      en: json['en'] as String,
      sci: json['sci'] as String,
      cons: (json['cons'] as String?) ?? '',
      habitat: (json['habitat'] as String?) ?? '',
      audios: audioList,
      image: json['image'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'cn': cn,
    'en': en,
    'sci': sci,
    if (cons.isNotEmpty) 'cons': cons,
    'habitat': habitat,
    'audios': audios.map((a) => a.toJson()).toList(),
    if (image != null) 'image': image,
  };
}
