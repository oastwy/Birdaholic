import 'package:bird_flashcard/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('闪卡整套筛选设置可持久化并兼容旧范围键', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());

    await storage.setLastFlashcardSetup({
      'filter': 'unseen',
      'answerMode': 'learning',
      'studyMode': 'quiz',
      'promptMode': 'image',
      'order': 'taxonomic',
      'speciesDifficulty': 3,
      'imageDifficulty': 2,
    });

    expect(storage.lastFlashcardFilter, 'unseen');
    expect(storage.getLastFlashcardSetup(), {
      'filter': 'unseen',
      'answerMode': 'learning',
      'studyMode': 'quiz',
      'promptMode': 'image',
      'order': 'taxonomic',
      'speciesDifficulty': 3,
      'imageDifficulty': 2,
    });
  });

  test('损坏的闪卡设置会安全回退', () async {
    SharedPreferences.setMockInitialValues({
      'flashcard_last_setup_v1': '{broken',
    });
    final storage = StorageService(await SharedPreferences.getInstance());

    expect(storage.getLastFlashcardSetup(), isEmpty);
  });
}
