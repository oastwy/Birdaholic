import 'dart:convert';

import 'survey_session.dart';

class SurveyVersion {
  final int? id;
  final int surveyId;
  final DateTime savedAt;
  final String summary;
  final SurveySession snapshot;

  SurveyVersion({
    this.id,
    required this.surveyId,
    required this.savedAt,
    required this.summary,
    required this.snapshot,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'surveyId': surveyId,
    'savedAt': savedAt.toIso8601String(),
    'summary': summary,
    'snapshot': jsonEncode(snapshot.toMap()),
  };

  factory SurveyVersion.fromMap(Map<String, dynamic> map) {
    final raw = map['snapshot'] as String? ?? '{}';
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return SurveyVersion(
      id: map['id'] as int?,
      surveyId: map['surveyId'] as int,
      savedAt: DateTime.parse(map['savedAt'] as String),
      summary: map['summary'] as String? ?? '',
      snapshot: SurveySession.fromMap(decoded),
    );
  }
}
