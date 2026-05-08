import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/survey_session.dart';

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
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE surveys (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            startTime TEXT NOT NULL,
            endTime TEXT,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            tideHeight REAL,
            tideUnit TEXT,
            observations TEXT,
            speciesNames TEXT,
            customValues TEXT DEFAULT '',
            notes TEXT DEFAULT '',
            speciesNotes TEXT DEFAULT '',
            speciesFields TEXT DEFAULT '',
            speciesFieldCounts TEXT DEFAULT ''
          )
        ''');
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
      },
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
  }
}
