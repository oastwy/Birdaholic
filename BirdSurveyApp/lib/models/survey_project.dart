import 'dart:convert';

class SurveyProject {
  final String id;
  final String name;
  final List<String> pointIds; // SurveyPoint.id values

  SurveyProject({
    required this.id,
    required this.name,
    required this.pointIds,
  });

  SurveyProject copyWith({String? name, List<String>? pointIds}) => SurveyProject(
        id: id,
        name: name ?? this.name,
        pointIds: pointIds ?? List.from(this.pointIds),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pointIds': pointIds,
      };

  factory SurveyProject.fromJson(Map<String, dynamic> j) => SurveyProject(
        id: j['id'] as String,
        name: j['name'] as String,
        pointIds: (j['pointIds'] as List<dynamic>? ?? []).cast<String>(),
      );

  static List<SurveyProject> decodeList(String raw) {
    if (raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => SurveyProject.fromJson(e as Map<String, dynamic>)).toList();
  }

  static String encodeList(List<SurveyProject> projects) =>
      jsonEncode(projects.map((p) => p.toJson()).toList());
}
