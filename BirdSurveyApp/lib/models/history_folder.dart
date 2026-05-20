import 'dart:convert';

class HistoryFolder {
  final String id;
  final String name;
  final DateTime createdAt;

  HistoryFolder({required this.id, required this.name, DateTime? createdAt})
    : createdAt = createdAt ?? DateTime.now();

  HistoryFolder copyWith({String? name}) =>
      HistoryFolder(id: id, name: name ?? this.name, createdAt: createdAt);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory HistoryFolder.fromJson(Map<String, dynamic> json) => HistoryFolder(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );

  static List<HistoryFolder> decodeList(String raw) {
    if (raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => HistoryFolder.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String encodeList(List<HistoryFolder> folders) =>
      jsonEncode(folders.map((f) => f.toJson()).toList());
}
