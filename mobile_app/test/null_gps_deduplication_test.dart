import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:road_guard_mobile/features/detection/domain/models/road_hazard.dart';
import 'package:road_guard_mobile/features/history/data/repositories/hazard_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Nullable GPS & Road-Plane Deduplication in HazardRepository', () {
    late Database db;
    late HazardRepository repository;

    setUp(() async {
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (Database d, int v) async {
          await d.execute('''
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
        },
      );

      repository = HazardRepository();
      await repository.initialize(customDb: db);
    });

    tearDown(() async {
      await db.close();
    });

    test('Two detections of same class at nearly same road-plane pos with GPS NULL produce 1 row; different position produces 2 rows', () async {
      final t0 = DateTime(2026, 11, 7, 10, 0, 0);

      // 1. Initial detection at road position (0.5m, 10.0m) with GPS NULL
      final h1 = RoadHazard(
        id: 'hazard_null_gps_001',
        defectClass: 'Pothole',
        classId: 3,
        confidence: 0.85,
        latitude: null, // Explicit SQL NULL
        longitude: null, // Explicit SQL NULL
        speedKmh: 0.0,
        timestamp: t0,
        address: 'Offline Road Segment A',
        roadXMeters: 0.5,
        roadYMeters: 10.0,
      );

      final success1 = await repository.persistHazardAtomically(hazard: h1);
      expect(success1, isTrue);

      var rows = await db.query('hazards');
      expect(rows.length, equals(1));
      expect(rows.first['latitude'], isNull, reason: 'Latitude must be strictly SQL NULL, not 0.0');
      expect(rows.first['longitude'], isNull, reason: 'Longitude must be strictly SQL NULL, not 0.0');
      expect(rows.first['road_x_meters'], equals(0.5));
      expect(rows.first['road_y_meters'], equals(10.0));

      // 2. Duplicate detection: same classId (3), GPS NULL, nearby road position (0.8m, 11.2m -> dist ~1.23m <= 15m), within 2.5s (<= 8s)
      final h2Duplicate = RoadHazard(
        id: 'hazard_null_gps_002',
        defectClass: 'Pothole',
        classId: 3,
        confidence: 0.88,
        latitude: null,
        longitude: null,
        speedKmh: 0.0,
        timestamp: t0.add(const Duration(milliseconds: 2500)),
        address: 'Offline Road Segment A',
        roadXMeters: 0.8,
        roadYMeters: 11.2,
      );

      final success2 = await repository.persistHazardAtomically(hazard: h2Duplicate);
      expect(success2, isFalse, reason: 'Deduplication must reject duplicate defect at nearby road-plane location within 8s');

      rows = await db.query('hazards');
      expect(rows.length, equals(1), reason: 'Database must still contain exactly 1 row after duplicate rejection');

      // 3. Distinct detection: same classId (3), GPS NULL, distant road position (0.5m, 32.0m -> dist = 22m > 15m), within 4.0s (<= 8s)
      final h3Distinct = RoadHazard(
        id: 'hazard_null_gps_003',
        defectClass: 'Pothole',
        classId: 3,
        confidence: 0.82,
        latitude: null,
        longitude: null,
        speedKmh: 0.0,
        timestamp: t0.add(const Duration(milliseconds: 4000)),
        address: 'Offline Road Segment A',
        roadXMeters: 0.5,
        roadYMeters: 32.0,
      );

      final success3 = await repository.persistHazardAtomically(hazard: h3Distinct);
      expect(success3, isTrue, reason: 'Independent defect beyond 15m road distance must be persisted');

      rows = await db.query('hazards');
      expect(rows.length, equals(2), reason: 'Two distinct physical positions must produce exactly 2 rows');
      expect(rows[1]['id'], equals('hazard_null_gps_003'));
      expect(rows[1]['latitude'], isNull);
      expect(rows[1]['longitude'], isNull);
      expect(rows[1]['road_x_meters'], equals(0.5));
      expect(rows[1]['road_y_meters'], equals(32.0));
    });
  });
}
