import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/history_model.dart';
import '../models/preset_model.dart';

class DatabaseHelper {
  DatabaseHelper._internal();

  static final DatabaseHelper instance = DatabaseHelper._internal();

  factory DatabaseHelper() => instance;

  static const String _databaseName = 'sleep_timer_utility.db';
  static const int _databaseVersion = 1;

  static const String tablePresets = 'presets';
  static const String tableHistory = 'history';
  static const String tableSettings = 'settings';

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final String dbDir = await getDatabasesPath();
    final String path = join(dbDir, _databaseName);

    return openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tablePresets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        label TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableHistory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        preset_label TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL,
        executed_at TEXT NOT NULL,
        is_screen_locked INTEGER NOT NULL DEFAULT 1,
        is_audio_muted INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableSettings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    final String nowIso = DateTime.now().toIso8601String();
    final Batch batch = db.batch();

    // 4 data preset bawaan sesuai PRD
    final List<Map<String, dynamic>> defaultPresets = <Map<String, dynamic>>[
      <String, dynamic>{
        'label': 'Uji Coba (10 Detik)',
        'duration_seconds': 10,
        'created_at': nowIso,
      },
      <String, dynamic>{
        'label': 'Tidur Cepat (15 Menit)',
        'duration_seconds': 900,
        'created_at': nowIso,
      },
      <String, dynamic>{
        'label': 'Standar (30 Menit)',
        'duration_seconds': 1800,
        'created_at': nowIso,
      },
      <String, dynamic>{
        'label': 'Penuh (60 Menit)',
        'duration_seconds': 3600,
        'created_at': nowIso,
      },
    ];

    for (final Map<String, dynamic> preset in defaultPresets) {
      batch.insert(tablePresets, preset);
    }

    // Nilai awal pengaturan sesuai PRD
    batch.insert(
      tableSettings,
      <String, dynamic>{'key': 'pitch_black_mode', 'value': 'false'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    batch.insert(
      tableSettings,
      <String, dynamic>{'key': 'haptic_feedback', 'value': 'true'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await batch.commit(noResult: true);
  }

  // ===========================================================================
  // CRUD PRESETS
  // ===========================================================================

  Future<List<PresetModel>> getPresets() async {
    final Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tablePresets,
      orderBy: 'duration_seconds ASC, id ASC',
    );
    return maps.map(PresetModel.fromMap).toList();
  }

  Future<int> insertPreset(PresetModel preset) async {
    final Database db = await database;
    return db.insert(
      tablePresets,
      preset.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> deletePreset(int id) async {
    final Database db = await database;
    return db.delete(
      tablePresets,
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  // ===========================================================================
  // CRUD HISTORY & HABIT ANALYTICS
  // ===========================================================================

  Future<List<HistoryModel>> getHistory() async {
    final Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableHistory,
      orderBy: 'id DESC',
    );
    return maps.map(HistoryModel.fromMap).toList();
  }

  Future<int> insertHistory(HistoryModel history) async {
    final Database db = await database;
    return db.insert(
      tableHistory,
      history.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> clearHistory() async {
    final Database db = await database;
    return db.delete(tableHistory);
  }

  /// Menghitung ringkasan kebiasaan menggunakan query agregasi SQLite:
  /// - Total Sesi (`totalSessions`)
  /// - Total Sesi Terkunci Penuh (`successfulSessions`)
  /// - Total Waktu Penggunaan dalam detik (`totalDurationSeconds`)
  /// - Rata-rata Durasi dalam detik (`averageDurationSeconds`)
  Future<Map<String, int>> getHabitSummary() async {
    final Database db = await database;
    final List<Map<String, Object?>> result = await db.rawQuery('''
      SELECT 
        COUNT(*) AS total_sessions,
        COALESCE(SUM(CASE WHEN is_screen_locked = 1 THEN 1 ELSE 0 END), 0) AS successful_sessions,
        COALESCE(SUM(duration_seconds), 0) AS total_duration_seconds,
        COALESCE(AVG(duration_seconds), 0) AS average_duration_seconds
      FROM $tableHistory
    ''');

    if (result.isEmpty) {
      return const <String, int>{
        'totalSessions': 0,
        'successfulSessions': 0,
        'totalDurationSeconds': 0,
        'averageDurationSeconds': 0,
      };
    }

    final Map<String, Object?> row = result.first;
    final int totalSessions = (row['total_sessions'] as num?)?.toInt() ?? 0;
    final int successfulSessions =
        (row['successful_sessions'] as num?)?.toInt() ?? 0;
    final int totalDurationSeconds =
        (row['total_duration_seconds'] as num?)?.toInt() ?? 0;
    final int averageDurationSeconds =
        (row['average_duration_seconds'] as num?)?.round() ?? 0;

    return <String, int>{
      'totalSessions': totalSessions,
      'successfulSessions': successfulSessions,
      'totalDurationSeconds': totalDurationSeconds,
      'averageDurationSeconds': averageDurationSeconds,
    };
  }

  // ===========================================================================
  // CRUD SETTINGS
  // ===========================================================================

  Future<String?> getSetting(String key) async {
    final Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableSettings,
      where: 'key = ?',
      whereArgs: <Object>[key],
      limit: 1,
    );
    if (maps.isEmpty) {
      return null;
    }
    return maps.first['value'] as String?;
  }

  Future<int> updateSetting(String key, String value) async {
    final Database db = await database;
    return db.insert(
      tableSettings,
      <String, dynamic>{
        'key': key,
        'value': value,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
