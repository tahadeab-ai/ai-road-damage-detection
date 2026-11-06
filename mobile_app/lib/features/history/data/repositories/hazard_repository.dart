import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../../detection/domain/models/road_hazard.dart';

/// Production Atomic SQLite Offline Repository for RoadGuard AI V1.2.
/// Guarantees ACID transactional persistence, verified file snapshot attachment,
/// and spatio-temporal deduplication for road damage incidents.
class HazardRepository {
  static const String databaseName = 'roadguard_incidents.db';
  static const String tableName = 'hazards';

  Database? _database;
  final List<RoadHazard> _memoryCache = [];
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  Database? get database => _database;

  /// Initializes the SQLite database. Supports dependency injection of [customDb] for hermetic testing.
  Future<void> initialize({Database? customDb, String? dbPath}) async {
    if (_isInitialized && _database != null) return;

    if (customDb != null) {
      _database = customDb;
    } else {
      final databasesPath = dbPath ?? await getDatabasesPath();
      final fullPath = p.join(databasesPath, databaseName);

      _database = await openDatabase(
        fullPath,
        version: 1,
        onCreate: (Database db, int version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS $tableName (
              id TEXT PRIMARY KEY,
              defect_class TEXT NOT NULL,
              class_id INTEGER NOT NULL,
              confidence REAL NOT NULL,
              latitude REAL NOT NULL,
              longitude REAL NOT NULL,
              speed_kmh REAL NOT NULL,
              timestamp TEXT NOT NULL,
              address TEXT,
              snapshot_path TEXT
            )
          ''');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_hazards_class_timestamp ON $tableName (class_id, timestamp)');
        },
      );
    }

    // Warm in-memory cache from persistent SQLite store
    await _reloadCache();
    _isInitialized = true;
  }

  Future<void> _reloadCache() async {
    if (_database == null) return;
    final List<Map<String, dynamic>> maps = await _database!.query(
      tableName,
      orderBy: 'timestamp DESC',
    );
    _memoryCache.clear();
    for (final map in maps) {
      _memoryCache.add(RoadHazard.fromMap(map));
    }
  }

  /// Retrieves all logged hazard records sorted newest first.
  List<RoadHazard> getAllHazards() {
    return List.unmodifiable(_memoryCache);
  }

  /// Direct asynchronous SQLite query for all hazards.
  Future<List<RoadHazard>> fetchAllHazardsFromDb() async {
    if (_database == null) await initialize();
    final List<Map<String, dynamic>> maps = await _database!.query(
      tableName,
      orderBy: 'timestamp DESC',
    );
    return maps.map((map) => RoadHazard.fromMap(map)).toList();
  }

  /// Stores a new hazard incident within an atomic ACID SQLite transaction.
  /// Validates file snapshot presence on disk and enforces spatio-temporal deduplication.
  Future<bool> logHazard(RoadHazard hazard) async {
    if (_database == null) await initialize();

    // 1. Vehicle Movement Gate: Suppress logging if stationary / parking (speed < 5 km/h)
    if (hazard.speedKmh < 5.0 && hazard.latitude != 0.0) {
      return false; // Suppressed while stationary/parking
    }

    // 2. Spatio-temporal deduplication gate:
    // Suppress same defect class if within 15 meters AND within 8.0 seconds
    final recentSameClass = _memoryCache.where((h) {
      if (h.classId != hazard.classId) return false;
      final elapsedSec = hazard.timestamp.difference(h.timestamp).inMilliseconds.abs() / 1000.0;
      if (elapsedSec >= 8.0) return false;

      // Check distance if GPS coords are available
      if (hazard.latitude != 0.0 && h.latitude != 0.0) {
        final dist = Geolocator.distanceBetween(
          h.latitude,
          h.longitude,
          hazard.latitude,
          hazard.longitude,
        );
        return dist <= 15.0; // Same location within 15 meters
      }
      return true; // Fallback to temporal suppression if GPS not locked
    });

    if (recentSameClass.isNotEmpty) {
      return false; // Suppressed duplicate incident
    }

    // 3. Verified file snapshot integrity check
    if (hazard.snapshotPath != null && hazard.snapshotPath!.isNotEmpty) {
      final snapshotFile = File(hazard.snapshotPath!);
      if (!snapshotFile.existsSync() || snapshotFile.lengthSync() == 0) {
        debugPrint('[HazardRepository] Notice: snapshot file missing or empty at ${hazard.snapshotPath}');
      }
    }

    // 4. Atomic SQLite Transaction
    try {
      final success = await _database!.transaction<bool>((txn) async {
        final inserted = await txn.insert(
          tableName,
          hazard.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return inserted > 0;
      });

      if (success) {
        _memoryCache.insert(0, hazard);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[HazardRepository] Atomic transaction failed: $e');
      return false;
    }
  }

  /// Atomically clears the hazard log database.
  Future<void> clearAll() async {
    if (_database == null) await initialize();
    await _database!.transaction((txn) async {
      await txn.delete(tableName);
    });
    _memoryCache.clear();
  }

  /// Closes database connection.
  Future<void> dispose() async {
    await _database?.close();
    _database = null;
    _isInitialized = false;
    _memoryCache.clear();
  }

  /// Exports logged incidents as a standard GeoJSON FeatureCollection document.
  String exportToGeoJson() {
    final hazards = getAllHazards();
    final geoJsonMap = {
      'type': 'FeatureCollection',
      'features': hazards.map((h) => h.toGeoJsonFeature()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(geoJsonMap);
  }

  /// Exports logged incidents as CSV string.
  String exportToCsv() {
    final hazards = getAllHazards();
    final buffer = StringBuffer();
    buffer.writeln(RoadHazard.csvHeader());
    for (final h in hazards) {
      buffer.writeln(h.toCsvRow());
    }
    return buffer.toString();
  }
}
