import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/features/detection/domain/models/road_hazard.dart';
import 'package:road_guard_mobile/features/history/data/repositories/hazard_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    // Initialize FFI for local SQLite execution in unit tests
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Atomic SQLite Persistence & Verified Snapshot Tests', () {
    late Database testDb;
    late HazardRepository repository;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('roadguard_sqlite_test_');

      testDb = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (Database db, int version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS hazards (
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
          await db.execute('CREATE INDEX IF NOT EXISTS idx_hazards_class_timestamp ON hazards (class_id, timestamp)');
        },
      );

      repository = HazardRepository();
      await repository.initialize(customDb: testDb);
    });

    tearDown(() async {
      await repository.dispose();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Persists hazard record atomically and verifies presence in SQLite table', () async {
      final snapshotFile = File('${tempDir.path}/pothole_001.jpg');
      await snapshotFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]); // Minimal JPEG magic bytes

      final hazard = RoadHazard(
        id: 'INC_001',
        defectClass: 'Pothole',
        classId: 3,
        confidence: 0.92,
        latitude: 37.7749,
        longitude: -122.4194,
        speedKmh: 42.5,
        timestamp: DateTime(2026, 11, 6, 14, 30, 0),
        address: 'Market St, San Francisco, CA',
        snapshotPath: snapshotFile.path,
      );

      final logged = await repository.logHazard(hazard);
      expect(logged, isTrue);

      // Verify persistent SQLite query
      final hazardsInDb = await repository.fetchAllHazardsFromDb();
      expect(hazardsInDb.length, 1);
      final persisted = hazardsInDb.first;

      expect(persisted.id, 'INC_001');
      expect(persisted.defectClass, 'Pothole');
      expect(persisted.classId, 3);
      expect(persisted.confidence, 0.92);
      expect(persisted.latitude, 37.7749);
      expect(persisted.longitude, -122.4194);
      expect(persisted.speedKmh, 42.5);
      expect(persisted.snapshotPath, snapshotFile.path);

      // Verify physical snapshot file on disk
      expect(File(persisted.snapshotPath!).existsSync(), isTrue);
      expect(File(persisted.snapshotPath!).lengthSync(), greaterThan(0));
    });

    test('Spatio-temporal deduplication rejects duplicate detection within 15 meters and 8 seconds', () async {
      final t0 = DateTime(2026, 11, 6, 14, 30, 0);

      final hazard1 = RoadHazard(
        id: 'INC_TRACK_001',
        defectClass: 'Pothole',
        classId: 3,
        confidence: 0.88,
        latitude: 37.7749,
        longitude: -122.4194,
        speedKmh: 35.0,
        timestamp: t0,
        address: 'Main Road',
      );

      final logged1 = await repository.logHazard(hazard1);
      expect(logged1, isTrue);

      // Frame 2: Identical class 2.0 seconds later, 5 meters away -> duplicate must be suppressed
      final hazardDuplicate = RoadHazard(
        id: 'INC_TRACK_001_DUP',
        defectClass: 'Pothole',
        classId: 3,
        confidence: 0.91,
        latitude: 37.77493, // ~3.3 meters away
        longitude: -122.4194,
        speedKmh: 35.0,
        timestamp: t0.add(const Duration(seconds: 2)),
        address: 'Main Road',
      );

      final logged2 = await repository.logHazard(hazardDuplicate);
      expect(logged2, isFalse, reason: 'Duplicate hazard within 15m and 8s must be suppressed');

      // Frame 3: Distinct class (Crack, classId 0) at same location -> allowed
      final hazardCrack = RoadHazard(
        id: 'INC_TRACK_002',
        defectClass: 'Longitudinal Crack',
        classId: 0,
        confidence: 0.85,
        latitude: 37.77493,
        longitude: -122.4194,
        speedKmh: 35.0,
        timestamp: t0.add(const Duration(seconds: 3)),
        address: 'Main Road',
      );

      final logged3 = await repository.logHazard(hazardCrack);
      expect(logged3, isTrue, reason: 'Different defect class at same location must be allowed');
    });

    test('Exports records correctly to GeoJSON and CSV formats', () async {
      final hazard = RoadHazard(
        id: 'INC_GEO_01',
        defectClass: 'Alligator Crack',
        classId: 2,
        confidence: 0.87,
        latitude: 24.7136,
        longitude: 46.6753,
        speedKmh: 50.0,
        timestamp: DateTime(2026, 11, 6, 10, 0, 0),
        address: 'King Fahd Rd, Riyadh',
      );

      await repository.logHazard(hazard);

      final geoJson = repository.exportToGeoJson();
      expect(geoJson, contains('"type": "FeatureCollection"'));
      expect(geoJson, contains('46.6753'));
      expect(geoJson, contains('24.7136'));
      expect(geoJson, contains('"class": "Alligator Crack"'));

      final csv = repository.exportToCsv();
      expect(csv, contains('id,defect_class,class_id,confidence,latitude,longitude,speed_kmh,timestamp,address'));
      expect(csv, contains('INC_GEO_01,"Alligator Crack",2,0.87,24.7136,46.6753,50.0'));
    });
  });
}
