import 'dart:convert';

enum FieldType { text, number, select }

class CustomField {
  final String id;
  final String name;
  final FieldType type;
  final List<String> options; // only for select type
  final String defaultValue;

  CustomField({
    required this.id,
    required this.name,
    required this.type,
    this.options = const [],
    this.defaultValue = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'options': options,
        'defaultValue': defaultValue,
      };

  factory CustomField.fromJson(Map<String, dynamic> j) => CustomField(
        id: j['id'] as String,
        name: j['name'] as String,
        type: FieldType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => FieldType.text,
        ),
        options: (j['options'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        defaultValue: j['defaultValue'] as String? ?? '',
      );

  static List<CustomField> decodeList(String json) {
    if (json.isEmpty) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list
        .map((e) => CustomField.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String encodeList(List<CustomField> fields) =>
      jsonEncode(fields.map((f) => f.toJson()).toList());
}
