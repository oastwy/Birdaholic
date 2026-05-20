import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/survey_project.dart';

class SurveyProjectService {
  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/survey_projects.json');
  }

  static Future<List<SurveyProject>> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final raw = await file.readAsString();
        return raw.isEmpty ? [] : SurveyProject.decodeList(raw);
      }
    } catch (_) {}
    return [];
  }

  static Future<void> save(List<SurveyProject> projects) async {
    final file = await _file();
    await file.writeAsString(SurveyProject.encodeList(projects));
  }

  static Future<void> add(SurveyProject project) async {
    final projects = await load();
    projects.add(project);
    await save(projects);
  }

  static Future<void> update(SurveyProject project) async {
    final projects = await load();
    final idx = projects.indexWhere((p) => p.id == project.id);
    if (idx >= 0) projects[idx] = project;
    await save(projects);
  }

  static Future<void> delete(String id) async {
    final projects = await load();
    projects.removeWhere((p) => p.id == id);
    await save(projects);
  }
}
