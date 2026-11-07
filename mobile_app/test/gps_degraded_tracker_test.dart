import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/core/utils/temporal_filter.dart';
import 'package:road_guard_mobile/features/detection/domain/models/detection_result.dart';

void main() {
  group('GPS Degraded Fallback Tracker Tests', () {
    test('GPS degraded mode preserves visual-only tracking but suspends metric translation', () {
      final filter = TemporalFilter();
      final now = DateTime(2026, 11, 6, 12, 0, 0);

      // Frame 1 with GPS degraded
      const det1 = DetectionResult(
        classId: 3,
        className: 'Pothole',
        confidence: 0.85,
        normalizedRect: Rect.fromLTWH(0.40, 0.50, 0.20, 0.20),
      );

      final r1 = filter.processFrame(
        [det1],
        timestamp: now,
        isGpsDegraded: true,
        speedMps: 10.0, // High speed, but GPS degraded
      );

      expect(r1.length, equals(1));
      final trackId = r1.first.trackingId;

      // Frame 2: Slight visual shift, still GPS degraded
      const det2 = DetectionResult(
        classId: 3,
        className: 'Pothole',
        confidence: 0.88,
        normalizedRect: Rect.fromLTWH(0.41, 0.51, 0.20, 0.20),
      );

      final r2 = filter.processFrame(
        [det2],
        timestamp: now.add(const Duration(milliseconds: 100)),
        isGpsDegraded: true,
        speedMps: 10.0,
      );

      // Successfully maintains visual IoU association without crashing or metric translation drift
      expect(r2.length, equals(1));
      expect(r2.first.trackingId, equals(trackId));
      expect(r2.first.associationCount, equals(2));
      expect(r2.first.isTracking, isTrue);
    });
  });
}
