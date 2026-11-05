import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/features/detection/domain/models/detection_result.dart';
import 'package:road_guard_mobile/features/detection/domain/models/road_hazard.dart';

void main() {
  group('RoadHazard & DetectionResult Serialization Tests', () {
    test('DetectionResult correctly converts to and from JSON', () {
      const original = DetectionResult(
        classId: 3,
        className: 'Pothole',
        confidence: 0.8842,
        normalizedRect: Rect.fromLTRB(0.1, 0.2, 0.4, 0.5),
      );

      final jsonMap = original.toJson();
      expect(jsonMap['class'], equals('Pothole'));
      expect(jsonMap['class_id'], equals(3));
      expect(jsonMap['confidence'], equals(0.8842));

      final deserialized = DetectionResult.fromJson(jsonMap);
      expect(deserialized.classId, equals(original.classId));
      expect(deserialized.className, equals(original.className));
      expect(deserialized.confidence, equals(original.confidence));
      expect(deserialized.normalizedRect, equals(original.normalizedRect));
    });

    test('RoadHazard produces valid GeoJSON Point feature representation', () {
      final hazard = RoadHazard(
        id: 'hz_101',
        defectClass: 'Pothole',
        classId: 3,
        confidence: 0.92,
        latitude: 35.6895,
        longitude: 139.6917,
        speedKmh: 42.5,
        timestamp: DateTime.parse('2026-11-05T12:00:00Z'),
        address: 'Shinjuku Avenue, Tokyo',
      );

      final geoJson = hazard.toGeoJsonFeature();

      expect(geoJson['type'], equals('Feature'));
      expect(geoJson['geometry']['type'], equals('Point'));
      // GeoJSON spec specifies [longitude, latitude]
      expect(geoJson['geometry']['coordinates'], equals([139.6917, 35.6895]));
      expect(geoJson['properties']['class'], equals('Pothole'));
      expect(geoJson['properties']['speed_kmh'], equals(42.5));
    });

    test('RoadHazard correctly formats CSV row with standard header', () {
      final header = RoadHazard.csvHeader();
      expect(header, contains('latitude,longitude,speed_kmh'));

      final hazard = RoadHazard(
        id: 'hz_102',
        defectClass: 'Alligator Crack',
        classId: 2,
        confidence: 0.78,
        latitude: 28.6139,
        longitude: 77.2090,
        speedKmh: 35.0,
        timestamp: DateTime.parse('2026-11-05T12:30:00Z'),
        address: 'Connaught Place, New Delhi',
      );

      final row = hazard.toCsvRow();
      expect(row, contains('hz_102,"Alligator Crack",2,0.78,28.6139,77.209,35.0'));
    });
  });
}
