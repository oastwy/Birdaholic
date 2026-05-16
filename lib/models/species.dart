import 'audio_info.dart';

class SpeciesImageInfo {
  final String file;
  final String credit;
  final String contributor;
  final String contributorUrl;
  final String source;
  final String license;
  final int difficulty;

  const SpeciesImageInfo({
    required this.file,
    this.credit = '',
    this.contributor = '',
    this.contributorUrl = '',
    this.source = '',
    this.license = '',
    this.difficulty = 1,
  });

  factory SpeciesImageInfo.fromJson(dynamic json) {
    if (json is String) {
      return SpeciesImageInfo(file: json);
    }
    if (json is Map<String, dynamic>) {
      final contributor = (json['contributor'] as String? ?? '').trim();
      final source = (json['source'] as String? ?? '').trim();
      final credit = ((json['credit'] as String?) ??
              (json['image_credit'] as String?) ??
              contributor)
          .trim();
      return SpeciesImageInfo(
        file: (json['file'] as String? ?? json['url'] as String? ?? '').trim(),
        credit: credit.isNotEmpty ? credit : source,
        contributor: contributor,
        contributorUrl: (json['contributor_url'] as String? ?? '').trim(),
        source: source,
        license: (json['license'] as String? ?? '').trim(),
        difficulty: ((json['difficulty'] as int?) ?? 1).clamp(1, 5),
      );
    }
    return const SpeciesImageInfo(file: '');
  }

  Map<String, dynamic> toJson() => {
        'file': file,
        if (credit.isNotEmpty) 'credit': credit,
        if (contributor.isNotEmpty) 'contributor': contributor,
        if (contributorUrl.isNotEmpty) 'contributor_url': contributorUrl,
        if (source.isNotEmpty) 'source': source,
        if (license.isNotEmpty) 'license': license,
        if (difficulty != 1) 'difficulty': difficulty,
      };
}

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
  final List<SpeciesImageInfo> images; // 多图列表，第一张通常是封面
  final String imageCredit; // 鸟图致谢
  final String audioCredit; // 鸟鸣致谢
  final String identificationFeatures; // 管理员整理的识别特征

  final List<String> enAlt; // 备用英文名（不同 IOC 版本差异）
  final int difficulty; // 管理员标注的难度分（1–5，默认 1）

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
    this.images = const [],
    this.imageCredit = '',
    this.audioCredit = '',
    this.identificationFeatures = '',
    this.enAlt = const [],
    this.difficulty = 1,
  });

  /// 是否有一级保护
  bool get isGrade1 => cons == '1';

  /// 是否有二级保护
  bool get isGrade2 => cons == '2';

  /// 是否有音频
  bool get hasAudio => audios.isNotEmpty;

  /// 是否有图片
  bool get hasImage => image != null || images.isNotEmpty;

  List<String> get imageFiles {
    final files = <String>[];
    if (image != null && image!.isNotEmpty) files.add(image!);
    for (final item in images) {
      if (item.file.isNotEmpty && !files.contains(item.file)) {
        files.add(item.file);
      }
    }
    return files;
  }

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
    List<SpeciesImageInfo>? images,
    String? imageCredit,
    String? audioCredit,
    String? identificationFeatures,
    List<String>? enAlt,
    int? difficulty,
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
      images: images ?? this.images,
      imageCredit: imageCredit ?? this.imageCredit,
      audioCredit: audioCredit ?? this.audioCredit,
      identificationFeatures:
          identificationFeatures ?? this.identificationFeatures,
      enAlt: enAlt ?? this.enAlt,
      difficulty: difficulty ?? this.difficulty,
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
    final imageItems = (json['images'] as List<dynamic>?)
            ?.map(SpeciesImageInfo.fromJson)
            .where((item) => item.file.isNotEmpty)
            .toList() ??
        [];
    final legacyImage = (json['image'] as String?)?.trim();
    final normalizedImages = <SpeciesImageInfo>[];
    if (legacyImage != null && legacyImage.isNotEmpty) {
      normalizedImages.add(SpeciesImageInfo(
        file: legacyImage,
        credit: ((json['image_credit'] as String?) ?? imageContributor).trim(),
        contributor: imageContributor.trim(),
        source: imageSource.trim(),
        license: ((json['image_license'] as String?) ?? '').trim(),
      ));
    }
    for (final item in imageItems) {
      if (!normalizedImages.any((old) => old.file == item.file)) {
        normalizedImages.add(item);
      }
    }
    final imageCredit =
        ((json['image_credit'] as String?) ?? imageContributor).trim();
    final fallbackImageCredit =
        normalizedImages.isNotEmpty && normalizedImages.first.credit.isNotEmpty
            ? normalizedImages.first.credit
            : imageSource == 'wikipedia'
                ? 'Wikimedia Commons'
                : imageSource;
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
      image: legacyImage ??
          (normalizedImages.isNotEmpty ? normalizedImages.first.file : null),
      images: normalizedImages,
      imageCredit: imageCredit.isNotEmpty ? imageCredit : fallbackImageCredit,
      audioCredit: audioCredit,
      identificationFeatures:
          (json['identification_features'] as String?)?.trim() ?? '',
      enAlt: (json['en_alt'] as List<dynamic>?)?.cast<String>() ?? const [],
      difficulty: (json['difficulty'] as int?) ?? 1,
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
        if (images.isNotEmpty) 'images': images.map((i) => i.toJson()).toList(),
        if (imageCredit.isNotEmpty) 'image_credit': imageCredit,
        if (audioCredit.isNotEmpty) 'audio_credit': audioCredit,
        if (identificationFeatures.isNotEmpty)
          'identification_features': identificationFeatures,
        if (difficulty != 1) 'difficulty': difficulty,
      };
}
