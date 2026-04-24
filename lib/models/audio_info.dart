/// 音频信息
class AudioInfo {
  final String type;   // "call" | "song"
  final String file;   // 相对路径，如 "sounds/107314_call.mp3"
  final String? label; // 显示标签，如 "鸣叫 call"

  const AudioInfo({required this.type, required this.file, this.label});

  String get displayLabel => label ?? (type == 'song' ? '鸣唱 song' : '鸣叫 call');

  factory AudioInfo.fromJson(Map<String, dynamic> json) {
    return AudioInfo(
      type: json['type'] as String? ?? 'call',
      file: json['file'] as String,
      label: json['label'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'file': file,
    if (label != null) 'label': label,
  };
}
