/// 数据包元信息
class DataPack {
  final String name;
  final String region;
  final String version;
  final String created;
  final int speciesCount;
  final int audioCount;
  final int imageCount;
  final String packDir; // 本地解压目录绝对路径

  const DataPack({
    required this.name,
    required this.region,
    required this.version,
    required this.created,
    required this.speciesCount,
    required this.audioCount,
    required this.imageCount,
    required this.packDir,
  });

  factory DataPack.fromJson(Map<String, dynamic> json, String packDir) {
    return DataPack(
      name: json['name'] as String? ?? '未知数据包',
      region: json['region'] as String? ?? '',
      version: json['version'] as String? ?? '1.0',
      created: json['created'] as String? ?? '',
      speciesCount: json['species_count'] as int? ?? 0,
      audioCount: json['audio_count'] as int? ?? 0,
      imageCount: json['image_count'] as int? ?? 0,
      packDir: packDir,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'region': region,
    'version': version,
    'created': created,
    'species_count': speciesCount,
    'audio_count': audioCount,
    'image_count': imageCount,
  };
}
