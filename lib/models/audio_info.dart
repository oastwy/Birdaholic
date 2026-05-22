/// 音频信息
class AudioInfo {
  final String type; // "call" | "song"
  final String file; // 相对路径，如 "sounds/107314_call.mp3"
  final String? label; // 显示标签，如 "鸣叫 call"
  final String contributor; // 鸟鸣贡献者
  final String contributorUrl;
  final String license;
  final String spectrogram;
  final String spectrogramUrl;

  const AudioInfo({
    required this.type,
    required this.file,
    this.label,
    this.contributor = '',
    this.contributorUrl = '',
    this.license = '',
    this.spectrogram = '',
    this.spectrogramUrl = '',
  });

  String get displayLabel => label ?? (type == 'song' ? '鸣唱 song' : '鸣叫 call');

  factory AudioInfo.fromJson(Map<String, dynamic> json) {
    return AudioInfo(
      type: json['type'] as String? ?? 'call',
      file: json['file'] as String,
      label: json['label'] as String?,
      contributor: (json['contributor'] as String?) ??
          (json['recordist'] as String?) ??
          '',
      contributorUrl: (json['contributor_url'] as String?) ?? '',
      license: (json['license'] as String?) ?? '',
      spectrogram: (json['spectrogram'] as String?) ?? '',
      spectrogramUrl: (json['spectrogram_url'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'file': file,
        if (label != null) 'label': label,
        if (contributor.isNotEmpty) 'contributor': contributor,
        if (contributorUrl.isNotEmpty) 'contributor_url': contributorUrl,
        if (license.isNotEmpty) 'license': license,
        if (spectrogram.isNotEmpty) 'spectrogram': spectrogram,
        if (spectrogramUrl.isNotEmpty) 'spectrogram_url': spectrogramUrl,
      };
}
