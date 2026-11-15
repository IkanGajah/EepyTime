import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/history_model.dart';
import '../models/preset_model.dart';

class DatabaseHelper {
  DatabaseHelper._internal();

  static final DatabaseHelper instance = DatabaseHelper._internal();

  factory DatabaseHelper() => instance;

  static const String _databaseName = 'eepy_time.db';
  static const int _databaseVersion = 2;

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
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      final List<Map<String, Object?>> cols =
          await db.rawQuery('PRAGMA table_info($tableHistory)');
      final Set<String> existingCols = cols
          .map((Map<String, Object?> row) => (row['name'] as String?) ?? '')
          .toSet();

      if (!existingCols.contains('session_key')) {
        await db.execute(
          'ALTER TABLE $tableHistory ADD COLUMN session_key TEXT',
        );
      }
      if (!existingCols.contains('woke_up_at')) {
        await db.execute(
          'ALTER TABLE $tableHistory ADD COLUMN woke_up_at TEXT',
        );
      }
      if (!existingCols.contains('sleep_duration_seconds')) {
        await db.execute(
          'ALTER TABLE $tableHistory ADD COLUMN sleep_duration_seconds INTEGER',
        );
      }
    }
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
        session_key TEXT,
        preset_label TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL,
        executed_at TEXT NOT NULL,
        woke_up_at TEXT,
        sleep_duration_seconds INTEGER,
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
    batch.insert(
      tableSettings,
      <String, dynamic>{'key': 'toast_notifications', 'value': 'true'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    batch.insert(
      tableSettings,
      <String, dynamic>{'key': 'onboarding_completed', 'value': 'false'},
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
    if (history.sessionKey != null && history.sessionKey!.isNotEmpty) {
      final List<Map<String, Object?>> existing = await db.query(
        tableHistory,
        columns: <String>['id'],
        where: 'session_key = ?',
        whereArgs: <Object>[history.sessionKey!],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final int existingId = (existing.first['id'] as num).toInt();
        await db.update(
          tableHistory,
          history.copyWith(id: existingId).toMap(),
          where: 'id = ?',
          whereArgs: <Object>[existingId],
        );
        return existingId;
      }
    }
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

  /// Menghitung ringkasan kebiasaan tidur berdasarkan waktu aktual antara
  /// layar terkunci (timer habis) hingga layar dibuka kembali:
  /// - Total Sesi (`totalSessions`)
  /// - Total Waktu Tidur dalam detik (`totalSleepSeconds`)
  /// - Rata-rata Durasi Tidur dalam detik (`averageSleepSeconds`)
  Future<Map<String, int>> getHabitSummary() async {
    final Database db = await database;
    final List<Map<String, Object?>> result = await db.rawQuery('''
      SELECT 
        COUNT(*) AS total_sessions,
        COALESCE(SUM(COALESCE(sleep_duration_seconds, 0)), 0) AS total_sleep_seconds,
        COALESCE(
          AVG(
            CASE 
              WHEN sleep_duration_seconds IS NOT NULL AND sleep_duration_seconds > 0 
              THEN sleep_duration_seconds 
            END
          ),
          0
        ) AS average_sleep_seconds
      FROM $tableHistory
    ''');

    if (result.isEmpty) {
      return const <String, int>{
        'totalSessions': 0,
        'totalSleepSeconds': 0,
        'averageSleepSeconds': 0,
      };
    }

    final Map<String, Object?> row = result.first;
    final int totalSessions = (row['total_sessions'] as num?)?.toInt() ?? 0;
    final int totalSleepSeconds =
        (row['total_sleep_seconds'] as num?)?.toInt() ?? 0;
    final int averageSleepSeconds =
        (row['average_sleep_seconds'] as num?)?.round() ?? 0;

    return <String, int>{
      'totalSessions': totalSessions,
      'totalSleepSeconds': totalSleepSeconds,
      'averageSleepSeconds': averageSleepSeconds,
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
