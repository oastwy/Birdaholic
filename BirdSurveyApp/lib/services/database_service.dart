import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/survey_session.dart';
import '../models/survey_version.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'bird_survey.db');
    return openDatabase(
      path,
      version: 8,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE surveys (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT DEFAULT '',
            folderId TEXT DEFAULT '',
            startTime TEXT NOT NULL,
            endTime TEXT,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            tideHeight REAL,
            tideUnit TEXT,
            tideDirection TEXT DEFAULT '',
            weather TEXT DEFAULT '',
            observations TEXT,
            speciesNames TEXT,
            customValues TEXT DEFAULT '',
            notes TEXT DEFAULT '',
            speciesNotes TEXT DEFAULT '',
            speciesFields TEXT DEFAULT '',
            speciesFieldCounts TEXT DEFAULT '',
            nestedSpeciesFieldCounts TEXT DEFAULT '',
            surveyMode TEXT DEFAULT 'point',
            transectTrack TEXT DEFAULT '',
            observationEvents TEXT DEFAULT ''
          )
        ''');
        await _createVersionTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE surveys ADD COLUMN customValues TEXT DEFAULT ''",
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE surveys ADD COLUMN notes TEXT DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE surveys ADD COLUMN speciesNotes TEXT DEFAULT ''",
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE surveys ADD COLUMN speciesFields TEXT DEFAULT ''",
          );
        }
        if (oldVersion < 5) {
          await db.execute(
            "ALTER TABLE surveys ADD COLUMN speciesFieldCounts TEXT DEFAULT ''",
          );
        }
        if (oldVersion < 6) {
          await db.execute(
            "ALTER TABLE surveys ADD COLUMN tideDirection TEXT DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE surveys ADD COLUMN weather TEXT DEFAULT ''",
          );
        }
        if (oldVersion < 7) {
          await db.execute(
            "ALTER TABLE surveys ADD COLUMN title TEXT DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE surveys ADD COLUMN folderId TEXT DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE surveys ADD COLUMN nestedSpeciesFieldCounts TEXT DEFAULT ''",
          );
          await _createVersionTable(db);
        }
        if (oldVersion < 8) {
          await db.execute(
            "ALTER TABLE surveys ADD COLUMN surveyMode TEXT DEFAULT 'point'",
          );
          await db.execute(
            "ALTER TABLE surveys ADD COLUMN transectTrack TEXT DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE surveys ADD COLUMN observationEvents TEXT DEFAULT ''",
          );
        }
      },
    );
  }

  static Future<void> _createVersionTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS survey_versions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        surveyId INTEGER NOT NULL,
        savedAt TEXT NOT NULL,
        summary TEXT DEFAULT '',
        snapshot TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_survey_versions_survey '
      'ON survey_versions(surveyId, savedAt DESC)',
    );
  }

  static Future<int> insertSurvey(SurveySession session) async {
    final database = await db;
    return database.insert('surveys', session.toMap());
  }

  static Future<void> updateSurvey(SurveySession session) async {
    final database = await db;
    await database.update(
      'surveys',
      session.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  static Future<List<SurveySession>> getAllSurveys() async {
    final database = await db;
    final maps = await database.query('surveys', orderBy: 'startTime DESC');
    return maps.map(SurveySession.fromMap).toList();
  }

  static Future<void> deleteSurvey(int id) async {
    final database = await db;
    await database.delete('surveys', where: 'id = ?', whereArgs: [id]);
    await database.delete(
      'survey_versions',
      where: 'surveyId = ?',
      whereArgs: [id],
    );
  }

  static Future<int> insertVersion(SurveyVersion version) async {
    final database = await db;
    final id = await database.insert('survey_versions', version.toMap());
    await _trimVersions(version.surveyId, keep: 20);
    return id;
  }

  static Future<List<SurveyVersion>> getVersions(int surveyId) async {
    final database = await db;
    final maps = await database.query(
      'survey_versions',
      where: 'surveyId = ?',
      whereArgs: [surveyId],
      orderBy: 'savedAt DESC',
    );
    return maps.map(SurveyVersion.fromMap).toList();
  }

  static Future<void> _trimVersions(int surveyId, {required int keep}) async {
    final database = await db;
    final old = await database.query(
      'survey_versions',
      columns: ['id'],
      where: 'surveyId = ?',
      whereArgs: [surveyId],
      orderBy: 'savedAt DESC',
      limit: 1000000,
      offset: keep,
    );
    if (old.isEmpty) return;
    final ids = old.map((m) => m['id'] as int).toList();
    await database.delete(
      'survey_versions',
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }
}
