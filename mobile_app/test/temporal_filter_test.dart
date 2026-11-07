import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/core/utils/temporal_filter.dart';
import 'package:road_guard_mobile/features/detection/domain/models/detection_result.dart';

void main() {
  group('TemporalFilter Unit Tests', () {
    late TemporalFilter filter;

    setUp(() {
      filter = TemporalFilter(
        iouThreshold: 0.35,
        emaAlpha: 0.50,
        confirmationWindowMs: 150,
        lostGraceThresholdMs: 800,
        removalGraceThresholdMs: 3000,
      );
    });

    test('Single frame detection initializes new candidate track', () {
      final initialDetections = [
        const DetectionResult(
          classId: 3,
          className: 'Pothole',
          confidence: 0.85,
          normalizedRect: Rect.fromLTWH(0.2, 0.4, 0.3, 0.2),
        ),
      ];

      final tracks = filter.processFrame(initialDetections);
      expect(tracks.length, equals(1));
      expect(tracks.first.trackingId, equals(1));
      expect(tracks.first.classId, equals(3));
      expect(tracks.first.associationCount, equals(1));
      expect(tracks.first.isConfirmed, isFalse);
      expect(tracks.first.opacity, equals(1.0));
    });

    test('Temporal detections confirm hazard across confirmation window (>= 150ms)', () {
      final now = DateTime(2026, 11, 7, 12, 0, 0);

      // Observation 1: t = 0ms
      filter.processFrame([
        const DetectionResult(
          classId: 3,
          className: 'Pothole',
          confidence: 0.80,
          normalizedRect: Rect.fromLTWH(0.2, 0.4, 0.3, 0.2),
        ),
      ], timestamp: now);

      expect(filter.activeTracked.first.isConfirmed, isFalse);

      // Observation 2: t = 100ms (< 150ms confirmation window)
      filter.processFrame([
        const DetectionResult(
          classId: 3,
          className: 'Pothole',
          confidence: 0.82,
          normalizedRect: Rect.fromLTWH(0.21, 0.41, 0.3, 0.2),
        ),
      ], timestamp: now.add(const Duration(milliseconds: 100)));

      expect(filter.activeTracked.first.associationCount, equals(2));
      expect(filter.activeTracked.first.isConfirmed, isFalse);

      // Observation 3: t = 200ms (>= 150ms confirmation window reached)
      filter.processFrame([
        const DetectionResult(
          classId: 3,
          className: 'Pothole',
          confidence: 0.86,
          normalizedRect: Rect.fromLTWH(0.22, 0.42, 0.3, 0.2),
        ),
      ], timestamp: now.add(const Duration(milliseconds: 200)));

      expect(filter.activeTracked.first.associationCount, equals(3));
      expect(filter.activeTracked.first.isConfirmed, isTrue);
      expect(filter.activeTracked.first.isCritical, isTrue); // D40 is critical
    });

    test('EMA smoothing smoothly interpolates bounding box coordinates', () {
      final now = DateTime(2026, 11, 7, 12, 0, 0);

      filter.processFrame([
        const DetectionResult(
          classId: 3,
          className: 'Pothole',
          confidence: 0.80,
          normalizedRect: Rect.fromLTRB(0.20, 0.40, 0.40, 0.60),
        ),
      ], timestamp: now);

      // Second observation shifted right to (0.30, 0.40, 0.50, 0.60)
      filter.processFrame([
        const DetectionResult(
          classId: 3,
          className: 'Pothole',
          confidence: 0.85,
          normalizedRect: Rect.fromLTRB(0.30, 0.40, 0.50, 0.60),
        ),
      ], timestamp: now.add(const Duration(milliseconds: 100)));

      // With emaAlpha = 0.50, new left = 0.20*0.5 + 0.30*0.5 = 0.25
      final smoothed = filter.activeTracked.first.smoothedRect;
      expect(smoothed.left, closeTo(0.25, 0.01));
      expect(smoothed.right, closeTo(0.45, 0.01));
    });

    test('markIncidentLogged returns true on first call and false on duplicates', () {
      final now = DateTime(2026, 11, 7, 12, 0, 0);

      filter.processFrame([
        const DetectionResult(
          classId: 3,
          className: 'Pothole',
          confidence: 0.85,
          normalizedRect: Rect.fromLTWH(0.2, 0.4, 0.3, 0.2),
        ),
      ], timestamp: now);

      expect(filter.markIncidentLogged(1), isTrue);
      expect(filter.markIncidentLogged(1), isFalse);
    });
  });
}
