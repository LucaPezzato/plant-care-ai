import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/plant_models.dart';

class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase instance = LocalDatabase._();

  static const _dbName = 'plant_care_ai.db';
  static const _dbVersion = 1;
  static const _uuid = Uuid();

  Database? _db;
  void Function()? onDataMutated;

  Future<String> get databaseFilePath async {
    final dbPath = await getDatabasesPath();
    return p.join(dbPath, _dbName);
  }

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    final fullPath = await databaseFilePath;
    _db = await openDatabase(
      fullPath,
      version: _dbVersion,
      onOpen: (db) async {
        for (final ddl in const [
          'ALTER TABLE app_settings ADD COLUMN auto_backup_enabled INTEGER NOT NULL DEFAULT 1',
          'ALTER TABLE app_settings ADD COLUMN last_cloud_backup_at TEXT',
          'ALTER TABLE app_settings ADD COLUMN active_garden_id TEXT',
          'ALTER TABLE app_settings ADD COLUMN active_garden_name TEXT',
          'ALTER TABLE app_settings ADD COLUMN active_garden_invite_code TEXT',
          'ALTER TABLE watering_logs ADD COLUMN watered_by TEXT',
        ]) {
          try {
            await db.execute(ddl);
          } catch (_) {}
        }
      },
      onCreate: _onCreate,
    );
    return _db!;
  }

  Future<File> prepareDatabaseFileForBackup() async {
    final db = await database;
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    return File(await databaseFilePath);
  }

  Future<void> restoreDatabaseFromBytes(List<int> bytes) async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
    final fullPath = await databaseFilePath;
    final file = File(fullPath);
    await file.writeAsBytes(bytes, flush: true);
    // Clean up stale WAL/SHM files if present
    for (final suffix in ['-wal', '-shm']) {
      final f = File('$fullPath$suffix');
      if (f.existsSync()) {
        await f.delete();
      }
    }
    await database;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE plants (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        species TEXT NOT NULL DEFAULT '',
        location TEXT NOT NULL DEFAULT 'Casa',
        light_level TEXT NOT NULL DEFAULT 'indirect',
        watering_interval_days INTEGER NOT NULL DEFAULT 7,
        photo_check_interval_days INTEGER NOT NULL DEFAULT 14,
        last_watered_at TEXT,
        last_photo_check_at TEXT,
        cover_photo_path TEXT,
        notes TEXT,
        last_health_score REAL,
        last_health_status TEXT NOT NULL DEFAULT 'unknown',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE watering_logs (
        id TEXT PRIMARY KEY,
        plant_id TEXT NOT NULL,
        watered_at TEXT NOT NULL,
        notes TEXT,
        watered_by TEXT,
        FOREIGN KEY (plant_id) REFERENCES plants (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE health_checks (
        id TEXT PRIMARY KEY,
        plant_id TEXT NOT NULL,
        checked_at TEXT NOT NULL,
        photo_path TEXT NOT NULL,
        health_score REAL NOT NULL,
        status TEXT NOT NULL,
        headline TEXT NOT NULL,
        diagnosis TEXT NOT NULL,
        issues_json TEXT NOT NULL DEFAULT '[]',
        care_actions_json TEXT NOT NULL DEFAULT '[]',
        trend TEXT NOT NULL DEFAULT 'firstCheck',
        suggested_watering_days INTEGER,
        user_notes TEXT,
        FOREIGN KEY (plant_id) REFERENCES plants (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        preferred_ai_provider TEXT NOT NULL DEFAULT 'gemini',
        preferred_ai_model TEXT NOT NULL DEFAULT 'gemini-2.5-flash',
        custom_base_url TEXT NOT NULL DEFAULT 'https://openrouter.ai/api/v1',
        custom_model_name TEXT NOT NULL DEFAULT 'google/gemini-2.5-flash',
        watering_reminder_enabled INTEGER NOT NULL DEFAULT 1,
        photo_reminder_enabled INTEGER NOT NULL DEFAULT 1,
        reminder_hour INTEGER NOT NULL DEFAULT 9,
        reminder_minute INTEGER NOT NULL DEFAULT 0,
        theme_mode_index INTEGER NOT NULL DEFAULT 0,
        auto_backup_enabled INTEGER NOT NULL DEFAULT 1,
        last_cloud_backup_at TEXT,
        active_garden_id TEXT,
        active_garden_name TEXT,
        active_garden_invite_code TEXT
      )
    ''');

    await db.insert('app_settings', const AppSettings().toMap());
  }

  // ── Plants ────────────────────────────────────────────────────────────────

  Future<List<Plant>> getAllPlants() async {
    final db = await database;
    final rows = await db.query('plants', orderBy: 'created_at DESC');
    final plants = rows.map(Plant.fromMap).toList();
    // Sort most urgent watering first, then name
    plants.sort((a, b) {
      final cmp = a.daysUntilWatering.compareTo(b.daysUntilWatering);
      if (cmp != 0) return cmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return plants;
  }

  Future<Plant?> getPlant(String id) async {
    final db = await database;
    final rows = await db.query('plants', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Plant.fromMap(rows.first);
  }

  Future<void> upsertPlant(Plant plant) async {
    final db = await database;
    await db.insert(
      'plants',
      plant.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    onDataMutated?.call();
  }

  Future<void> deletePlant(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('watering_logs', where: 'plant_id = ?', whereArgs: [id]);
      await txn.delete('health_checks', where: 'plant_id = ?', whereArgs: [id]);
      await txn.delete('plants', where: 'id = ?', whereArgs: [id]);
    });
    onDataMutated?.call();
  }

  // ── Watering Logs ─────────────────────────────────────────────────────────

  Future<void> upsertPlantFromSync(Plant plant) async {
    final db = await database;
    final existing = await getPlant(plant.id);
    // Preserve local cover photo path if remote has none
    final merged = plant.copyWith(
      coverPhotoPath: (plant.coverPhotoPath != null &&
              plant.coverPhotoPath!.isNotEmpty)
          ? plant.coverPhotoPath
          : existing?.coverPhotoPath,
    );
    await db.insert(
      'plants',
      merged.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertWateringLogFromSync(WateringLog log) async {
    final db = await database;
    await db.insert(
      'watering_logs',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<WateringLog> logWatering(
    String plantId, {
    DateTime? at,
    String? notes,
    String? wateredBy,
  }) async {
    final db = await database;
    final when = at ?? DateTime.now();
    final log = WateringLog(
      id: _uuid.v4(),
      plantId: plantId,
      wateredAt: when,
      notes: notes,
      wateredBy: wateredBy,
    );

    await db.transaction((txn) async {
      await txn.insert('watering_logs', log.toMap());
      await txn.update(
        'plants',
        {'last_watered_at': when.toIso8601String()},
        where: 'id = ?',
        whereArgs: [plantId],
      );
    });
    onDataMutated?.call();
    return log;
  }

  Future<List<WateringLog>> getWateringLogsForPlant(
    String plantId, {
    int limit = 30,
  }) async {
    final db = await database;
    final rows = await db.query(
      'watering_logs',
      where: 'plant_id = ?',
      whereArgs: [plantId],
      orderBy: 'watered_at DESC',
      limit: limit,
    );
    return rows.map(WateringLog.fromMap).toList();
  }

  Future<List<WateringLog>> getWateringLogsInRange(
    DateTime start,
    DateTime end,
  ) async {
    final db = await database;
    final rows = await db.query(
      'watering_logs',
      where: 'watered_at >= ? AND watered_at <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'watered_at DESC',
    );
    return rows.map(WateringLog.fromMap).toList();
  }

  Future<void> deleteWateringLog(WateringLog log) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('watering_logs', where: 'id = ?', whereArgs: [log.id]);
      final latest = await txn.query(
        'watering_logs',
        where: 'plant_id = ?',
        whereArgs: [log.plantId],
        orderBy: 'watered_at DESC',
        limit: 1,
      );
      await txn.update(
        'plants',
        {
          'last_watered_at':
              latest.isNotEmpty ? latest.first['watered_at'] : null,
        },
        where: 'id = ?',
        whereArgs: [log.plantId],
      );
    });
  }

  // ── Health Checks ─────────────────────────────────────────────────────────

  Future<void> saveHealthCheck(HealthCheckEntry entry) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'health_checks',
        entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final plantRows = await txn.query(
        'plants',
        columns: ['cover_photo_path'],
        where: 'id = ?',
        whereArgs: [entry.plantId],
      );
      final currentCover = plantRows.isNotEmpty
          ? plantRows.first['cover_photo_path'] as String?
          : null;

      await txn.update(
        'plants',
        {
          'last_photo_check_at': entry.checkedAt.toIso8601String(),
          'last_health_score': entry.healthScore,
          'last_health_status': entry.status.name,
          if (currentCover == null || currentCover.isEmpty)
            'cover_photo_path': entry.photoPath,
        },
        where: 'id = ?',
        whereArgs: [entry.plantId],
      );
    });
    onDataMutated?.call();
  }

  Future<List<HealthCheckEntry>> getHealthChecksForPlant(
    String plantId, {
    int limit = 50,
  }) async {
    final db = await database;
    final rows = await db.query(
      'health_checks',
      where: 'plant_id = ?',
      whereArgs: [plantId],
      orderBy: 'checked_at DESC',
      limit: limit,
    );
    return rows.map(HealthCheckEntry.fromMap).toList();
  }

  Future<List<HealthCheckEntry>> getHealthChecksInRange(
    DateTime start,
    DateTime end,
  ) async {
    final db = await database;
    final rows = await db.query(
      'health_checks',
      where: 'checked_at >= ? AND checked_at <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'checked_at DESC',
    );
    return rows.map(HealthCheckEntry.fromMap).toList();
  }

  Future<void> deleteHealthCheck(HealthCheckEntry entry) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('health_checks', where: 'id = ?', whereArgs: [entry.id]);
      final latest = await txn.query(
        'health_checks',
        where: 'plant_id = ?',
        whereArgs: [entry.plantId],
        orderBy: 'checked_at DESC',
        limit: 1,
      );
      if (latest.isNotEmpty) {
        final top = HealthCheckEntry.fromMap(latest.first);
        await txn.update(
          'plants',
          {
            'last_photo_check_at': top.checkedAt.toIso8601String(),
            'last_health_score': top.healthScore,
            'last_health_status': top.status.name,
          },
          where: 'id = ?',
          whereArgs: [entry.plantId],
        );
      } else {
        await txn.update(
          'plants',
          {
            'last_photo_check_at': null,
            'last_health_score': null,
            'last_health_status': HealthStatus.unknown.name,
          },
          where: 'id = ?',
          whereArgs: [entry.plantId],
        );
      }
    });
  }

  // ── Settings & Stats ──────────────────────────────────────────────────────

  Future<AppSettings> getAppSettings() async {
    final db = await database;
    final rows = await db.query('app_settings', where: 'id = 1');
    if (rows.isEmpty) {
      const defaults = AppSettings();
      await db.insert('app_settings', defaults.toMap());
      return defaults;
    }
    return AppSettings.fromMap(rows.first);
  }

  Future<void> saveAppSettings(AppSettings settings) async {
    final db = await database;
    await db.insert(
      'app_settings',
      settings.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    onDataMutated?.call();
  }

  Future<GardenStats> getGardenStats() async {
    final plants = await getAllPlants();
    final db = await database;
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
    final monthWaterings = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM watering_logs WHERE watered_at >= ?',
            [monthStart],
          ),
        ) ??
        0;
    final totalChecks = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM health_checks'),
        ) ??
        0;

    final scored =
        plants.where((pl) => pl.lastHealthScore != null).toList();
    final avgHealth = scored.isEmpty
        ? null
        : scored.fold<double>(0, (s, pl) => s + pl.lastHealthScore!) /
            scored.length;

    return GardenStats(
      totalPlants: plants.length,
      overdueWaterings: plants.where((pl) => pl.needsWaterSoon).length,
      duePhotoChecks: plants.where((pl) => pl.isPhotoCheckDue).length,
      averageHealthScore: avgHealth,
      wateringsThisMonth: monthWaterings,
      totalHealthChecks: totalChecks,
    );
  }
}
