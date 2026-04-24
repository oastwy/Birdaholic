class AviListSpecies {
  final String sci;
  final String en;
  final String order;
  final String family;
  final String range;
  final String iucn;
  final String code;
  final String avibaseId;

  const AviListSpecies({
    required this.sci,
    required this.en,
    this.order = '',
    this.family = '',
    this.range = '',
    this.iucn = '',
    this.code = '',
    this.avibaseId = '',
  });

  factory AviListSpecies.fromJson(Map<String, dynamic> json) {
    return AviListSpecies(
      sci: json['sci'] as String? ?? '',
      en: json['en'] as String? ?? '',
      order: json['order'] as String? ?? '',
      family: json['family'] as String? ?? '',
      range: json['range'] as String? ?? '',
      iucn: json['iucn'] as String? ?? '',
      code: json['code'] as String? ?? '',
      avibaseId: json['avibaseId'] as String? ?? '',
    );
  }
}
