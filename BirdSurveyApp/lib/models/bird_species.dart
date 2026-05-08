class BirdSpecies {
  final int id;
  final String zh;
  final String en;
  final String sci;
  final String family;
  final String order;
  final String ebird;
  /// Alternative Chinese name from eBird taxonomy (different from Zheng 4).
  final String zhAlt;
  /// eBird scientific name when different from Zheng 4 (genus reclassification).
  final String sciAlt;
  int count;
  int ebirdFrequency;

  BirdSpecies({
    required this.id,
    required this.zh,
    required this.en,
    required this.sci,
    required this.family,
    required this.order,
    required this.ebird,
    this.zhAlt = '',
    this.sciAlt = '',
    this.count = 0,
    this.ebirdFrequency = 0,
  });

  factory BirdSpecies.fromJson(Map<String, dynamic> json) {
    return BirdSpecies(
      id: json['id'] as int,
      zh: json['zh'] as String,
      en: (json['en'] as String? ?? ''),
      sci: (json['sci'] as String? ?? ''),
      family: (json['family'] as String? ?? ''),
      order: (json['order'] as String? ?? ''),
      ebird: (json['ebird'] as String? ?? ''),
      zhAlt: (json['zh_alt'] as String? ?? ''),
      sciAlt: (json['sci_alt'] as String? ?? ''),
    );
  }

  BirdSpecies copyWith({int? count, int? ebirdFrequency}) {
    return BirdSpecies(
      id: id,
      zh: zh,
      en: en,
      sci: sci,
      family: family,
      order: order,
      ebird: ebird,
      zhAlt: zhAlt,
      sciAlt: sciAlt,
      count: count ?? this.count,
      ebirdFrequency: ebirdFrequency ?? this.ebirdFrequency,
    );
  }
}
