import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/features/detection/domain/models/road_hazard.dart';
import 'package:road_guard_mobile/features/history/data/repositories/hazard_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Atomic File+DB Ordering & Repository-Level Spatio-Temporal Deduplication Tests', () {
    late HazardRepository repository;
    late Database db;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('roadguard_atomic_test_');

      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (Database db, int version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS hazards (
              id TEXT PRIMARY KEY,
              defect_class TEXT NOT NULL,
              class_id INTEGER NOT NULL,
              confidence REAL NOT NULL,
              latitude REAL,
              longitude REAL,
              speed_kmh REAL NOT NULL,
              timestamp TEXT NOT NULL,
              address TEXT,
              snapshot_path TEXT,
              road_x_meters REAL,
              road_y_meters REAL
            )
          ''');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_hazards_class_timestamp ON hazards (class_id, timestamp)');
        },
      );

      repository = HazardRepository();
      await repository.initialize(customDb: db);
    });

    tearDown(() async {
      await repository.dispose();
      await db.close();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('Two separate track IDs at the same physical location within 8s produce exactly one row', () async {
      final now = DateTime.now();

      // Hazard from Track #001
      final hazardTrack1 = RoadHazard(
        id: 'track_001_pothole_1',
        defectClass: 'Pothole',
        classId: 3,
        confidence: 0.91,
        latitude: 37.7749,
        longitude: -122.4194,
        speedKmh: 25.0,
        timestamp: now,
        address: 'Market St, San Francisco',
        snapshotPath: null,
      );

      final logged1 = await repository.persistHazardAtomically(hazard: hazardTrack1);
      expect(logged1, isTrue);

      // Hazard from a DIFFERENT Track #002 at virtually the same location (5m away) within 2 seconds
      final hazardTrack2 = RoadHazard(
        id: 'track_002_pothole_reid_failed',
        defectClass: 'Pothole',
        classId: 3, // Same defect class
        confidence: 0.89,
        latitude: 37.77493, // ~3.3m north
        longitude: -122.4194,
        speedKmh: 25.0,
        timestamp: now.add(const Duration(seconds: 2)), // 2 seconds later (< 8.0s)
        address: 'Market St, San Francisco',
        snapshotPath: null,
      );

      final logged2 = await repository.persistHazardAtomically(hazard: hazardTrack2);
      expect(logged2, isFalse, reason: 'Must reject duplicate detection at same location within 8s regardless of track_id');

      // Verify database contains EXACTLY one row
      final allRows = await repository.fetchAllHazardsFromDb();
      expect(allRows.length, equals(1));
      expect(allRows.first.id, equals('track_001_pothole_1'));
    });

    test('Atomic file+DB ordering: successful sequence renames temp and commits DB row', () async {
      final tempFile = File('${tempDir.path}/temp_snap_1.jpg');
      tempFile.writeAsBytesSync([1, 2, 3, 4, 5]); // Valid non-empty file
      final finalPath = '${tempDir.path}/final_snap_1.jpg';

      final hazard = RoadHazard(
        id: 'test_atomic_success',
        defectClass: 'Pothole',
        classId: 3,
        confidence: 0.95,
        latitude: 37.7749,
        longitude: -122.4194,
        speedKmh: 20.0,
        timestamp: DateTime.now(),
        address: 'Test Street',
        snapshotPath: finalPath,
      );

      final success = await repository.persistHazardAtomically(
        hazard: hazard,
        tempSnapshotPath: tempFile.path,
        finalSnapshotPath: finalPath,
      );

      expect(success, isTrue);
      expect(tempFile.existsSync(), isFalse, reason: 'Temp file should be renamed');
      expect(File(finalPath).existsSync(), isTrue, reason: 'Final file should exist');

      final rows = await repository.fetchAllHazardsFromDb();
      expect(rows.length, equals(1));
      expect(rows.first.snapshotPath, equals(finalPath));
    });

    test('Atomic file+DB ordering: Forced COMMIT failure asserts rollback with no orphaned file and no DB row', () async {
      final tempFile = File('${tempDir.path}/temp_snap_fail.jpg');
      tempFile.writeAsBytesSync([10, 20, 30, 40]);
      final finalPath = '${tempDir.path}/final_snap_fail.jpg';

      // Insert an existing row with id 'duplicate_primary_key'
      await db.execute('''
        INSERT INTO hazards (id, defect_class, class_id, confidence, latitude, longitude, speed_kmh, timestamp, address)
        VALUES ('duplicate_primary_key', 'Pothole', 3, 0.9, 0, 0, 10, '2026-01-01T00:00:00.000', 'Init');
      ''');

      // Attempt to insert with identical primary key to force PRIMARY KEY constraint violation during INSERT
      final failingHazard = RoadHazard(
        id: 'duplicate_primary_key',
        defectClass: 'Pothole',
        classId: 3,
        confidence: 0.95,
        latitude: 37.7749,
        longitude: -122.4194,
        speedKmh: 20.0,
        timestamp: DateTime.now().add(const Duration(hours: 1)),
        address: 'Test Street',
        snapshotPath: finalPath,
      );

      await expectLater(
        repository.persistHazardAtomically(
          hazard: failingHazard,
          tempSnapshotPath: tempFile.path,
          finalSnapshotPath: finalPath,
        ),
        throwsA(isA<Exception>()),
      );

      // Verify cleanup: final file must NOT be orphaned on disk, and temp file is cleaned up
      expect(File(finalPath).existsSync(), isFalse, reason: 'Final file must be deleted upon transaction failure');
      expect(tempFile.existsSync(), isFalse);

      // Verify DB row was not overwritten
      final rows = await repository.fetchAllHazardsFromDb();
      expect(rows.length, equals(1));
      expect(rows.first.id, equals('duplicate_primary_key'));
      expect(rows.first.address, equals('Init'));
    });
  });
}
