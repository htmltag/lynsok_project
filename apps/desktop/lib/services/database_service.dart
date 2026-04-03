import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseService {
  static Database? _database;
  static const int _dbVersion = 3;

  static Future<Database> getInstance() async {
    if (_database != null) return _database!;

    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = join(appDir.path, 'lynsok_desktop.db');

    _database = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        await _ensureSchema(db);
      },
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
        excludePatterns TEXT,
        httpServerPid INTEGER,
        mcpServerPid INTEGER,
        httpPort INTEGER,
        mcpPort INTEGER
      )
    ''');
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _addColumnIfMissing(db, 'indexes', 'httpServerPid', 'INTEGER');
      await _addColumnIfMissing(db, 'indexes', 'mcpServerPid', 'INTEGER');
    }
    if (oldVersion < 3) {
      await _addColumnIfMissing(db, 'indexes', 'httpPort', 'INTEGER');
      await _addColumnIfMissing(db, 'indexes', 'mcpPort', 'INTEGER');
    }
  }

  static Future<void> _ensureSchema(Database db) async {
    // Defensive check to self-heal partially migrated local DBs.
    await _addColumnIfMissing(db, 'indexes', 'httpServerPid', 'INTEGER');
    await _addColumnIfMissing(db, 'indexes', 'mcpServerPid', 'INTEGER');
    await _addColumnIfMissing(db, 'indexes', 'httpPort', 'INTEGER');
    await _addColumnIfMissing(db, 'indexes', 'mcpPort', 'INTEGER');
  }

  static Future<void> _addColumnIfMissing(
    Database db,
    String tableName,
    String columnName,
    String columnType,
  ) async {
    final result = await db.rawQuery('PRAGMA table_info($tableName)');
    final hasColumn = result.any((row) => row['name'] == columnName);
    if (!hasColumn) {
      await db.execute(
        'ALTER TABLE $tableName ADD COLUMN $columnName $columnType',
      );
    }
  }

  static Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
