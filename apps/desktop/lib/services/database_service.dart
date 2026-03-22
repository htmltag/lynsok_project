import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseService {
  static Database? _database;

  static Future<Database> getInstance() async {
    if (_database != null) return _database!;

    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = join(appDir.path, 'lynsok_desktop.db');

    _database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: _onCreate,
    );

    return _database!;
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE indexes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        sourcePath TEXT NOT NULL,
        lynPath TEXT NOT NULL,
        indexPath TEXT NOT NULL,
        fileCount INTEGER DEFAULT 0,
        totalSize INTEGER DEFAULT 0,
        createdAt TEXT NOT NULL,
        lastIndexedAt TEXT,
        serverActive INTEGER DEFAULT 0,
        excludePatterns TEXT
      )
    ''');
  }

  static Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}