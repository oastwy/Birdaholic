import 'audio_info.dart';

/// 鸟种数据模型
class Species {
  final String cn; // 中文名
  final String en; // 英文名
  final String sci; // 学名
  final String order; // 目
  final String family; // 科
  final String cons; // 保护等级: "1" | "2" | ""
  final String habitat; // 栖息地
  final List<AudioInfo> audios; // 音频列表
  final String? image; // 图片相对路径
  final String imageCredit; // 鸟图致谢
  final String audioCredit; // 鸟鸣致谢
  final String identificationFeatures; // 管理员整理的识别特征

  final List<String> enAlt; // 备用英文名（不同 IOC 版本差异）

  const Species({
    required this.cn,
    required this.en,
    required this.sci,
    this.order = '',
    this.family = '',
    this.cons = '',
    this.habitat = '',
    this.audios = const [],
    this.image,
    this.imageCredit = '',
    this.audioCredit = '',
    this.identificationFeatures = '',
    this.enAlt = const [],
  });

  /// 是否有一级保护
  bool get isGrade1 => cons == '1';

  /// 是否有二级保护
  bool get isGrade2 => cons == '2';

  /// 是否有音频
  bool get hasAudio => audios.isNotEmpty;

  /// 是否有图片
  bool get hasImage => image != null;

  Species copyWith({
    String? cn,
    String? en,
    String? sci,
    String? order,
    String? family,
    String? cons,
    String? habitat,
    List<AudioInfo>? audios,
    String? image,
    String? imageCredit,
    String? audioCredit,
    String? identificationFeatures,
    List<String>? enAlt,
  }) {
    return Species(
      cn: cn ?? this.cn,
      en: en ?? this.en,
      sci: sci ?? this.sci,
      order: order ?? this.order,
      family: family ?? this.family,
      cons: cons ?? this.cons,
      habitat: habitat ?? this.habitat,
      audios: audios ?? this.audios,
      image: image ?? this.image,
      imageCredit: imageCredit ?? this.imageCredit,
      audioCredit: audioCredit ?? this.audioCredit,
      identificationFeatures:
          identificationFeatures ?? this.identificationFeatures,
      enAlt: enAlt ?? this.enAlt,
    );
  }

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
    final audioContributors = audioList
        .map((audio) => audio.contributor.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    final imageContributor = (json['image_contributor'] as String?) ?? '';
    final imageSource = (json['image_source'] as String?) ?? '';
    final imageCredit =
        ((json['image_credit'] as String?) ?? imageContributor).trim();
    final fallbackImageCredit =
        imageSource == 'wikipedia' ? 'Wikimedia Commons' : imageSource;
    final explicitAudioCredit =
        ((json['audio_credit'] as String?) ?? '').trim();
    final platformOnlyAudioCredit = {
      'xeno',
      'xeno-canto',
      'xeno canto',
      'xeno-canto + wikimedia commons',
    }.contains(explicitAudioCredit.toLowerCase());
    final audioCredit =
        (platformOnlyAudioCredit && audioContributors.isNotEmpty)
            ? audioContributors.join(', ')
            : explicitAudioCredit.isNotEmpty
                ? explicitAudioCredit
                : audioContributors.join(', ');

    return Species(
      cn: json['cn'] as String,
      en: json['en'] as String,
      sci: json['sci'] as String,
      order: (json['order'] as String?) ?? '',
      family: (json['family'] as String?) ?? '',
      cons: (json['cons'] as String?) ?? '',
      habitat: (json['habitat'] as String?) ?? '',
      audios: audioList,
      image: json['image'] as String?,
      imageCredit: imageCredit.isNotEmpty ? imageCredit : fallbackImageCredit,
      audioCredit: audioCredit,
      identificationFeatures:
          (json['identification_features'] as String?)?.trim() ?? '',
      enAlt: (json['en_alt'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'cn': cn,
        'en': en,
        'sci': sci,
        if (order.isNotEmpty) 'order': order,
        if (family.isNotEmpty) 'family': family,
        if (cons.isNotEmpty) 'cons': cons,
        'habitat': habitat,
        'audios': audios.map((a) => a.toJson()).toList(),
        if (image != null) 'image': image,
        if (imageCredit.isNotEmpty) 'image_credit': imageCredit,
        if (audioCredit.isNotEmpty) 'audio_credit': audioCredit,
        if (identificationFeatures.isNotEmpty)
          'identification_features': identificationFeatures,
      };
}
