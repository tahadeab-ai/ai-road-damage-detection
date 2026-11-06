import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/core/utils/temporal_filter.dart';
import 'package:road_guard_mobile/features/detection/domain/models/detection_result.dart';

void main() {
  group('TemporalFilter 10-Frame Grace & EMA Smoothing Tests', () {
    test('Sustains candidate track across 10 consecutive dropped frames and prunes on 11th', () {
      final filter = TemporalFilter(
        confirmationStreak: 3,
        maxGraceFrames: 10,
        persistenceMs: 10000,
      );

      final baseTime = DateTime(2026, 11, 6, 12, 0, 0);

      // Frame 1: Detection initializes track #1
      final det = DetectionResult(
        classId: 3,
        className: 'Pothole',
        confidence: 0.85,
        normalizedRect: const Rect.fromLTRB(0.40, 0.60, 0.60, 0.80),
      );

      final f1 = filter.processFrame([det], timestamp: baseTime);
      expect(f1.length, 1);
      expect(f1.first.streak, 1);
      expect(f1.first.lostFramesCount, 0);

      // Simulate 10 consecutive dropped frames (empty detections list)
      for (int i = 1; i <= 10; i++) {
        final droppedFrameTime = baseTime.add(Duration(milliseconds: i * 100));
        final fLost = filter.processFrame([], timestamp: droppedFrameTime);

        expect(fLost.length, 1, reason: 'Track must survive dropped frame #$i within 10-frame grace buffer');
        expect(fLost.first.lostFramesCount, i);
        expect(fLost.first.lifecycle, TrackingLifecycle.lost);
        expect(fLost.first.opacity, closeTo(1.0 - (i / 10.0), 0.25));
      }

      // 11th dropped frame exceeds 10 grace frames -> must be pruned
      final f11 = filter.processFrame([], timestamp: baseTime.add(const Duration(milliseconds: 1200)));
      expect(f11, isEmpty, reason: 'Track must be pruned when lostFramesCount > 10');
    });

    test('EMA coordinate smoothing blends consecutive frame positions with alpha=0.65', () {
      final filter = TemporalFilter(
        emaAlpha: 0.65,
        confirmationStreak: 3,
      );

      final t0 = DateTime(2026, 11, 6, 12, 0, 0);

      // Frame 1: Initial position at left=0.40, top=0.50
      final det1 = DetectionResult(
        classId: 0,
        className: 'Longitudinal Crack',
        confidence: 0.80,
        normalizedRect: const Rect.fromLTRB(0.40, 0.50, 0.60, 0.70),
      );
      final r1 = filter.processFrame([det1], timestamp: t0);
      expect(r1.first.smoothedRect.left, 0.40);

      // Frame 2: Shifted position at left=0.44 (e.g. car shifted slightly, IoU ~ 0.66)
      final det2 = DetectionResult(
        classId: 0,
        className: 'Longitudinal Crack',
        confidence: 0.82,
        normalizedRect: const Rect.fromLTRB(0.44, 0.50, 0.64, 0.70),
      );
      final r2 = filter.processFrame([det2], timestamp: t0.add(const Duration(milliseconds: 100)));

      // Expected EMA Left = 0.40 * (1 - 0.65) + 0.44 * 0.65 = 0.14 + 0.286 = 0.426
      expect(r2.first.smoothedRect.left, closeTo(0.426, 1e-4));
      expect(r2.first.streak, 2);
      expect(r2.first.isTracking, isTrue);
    });

    test('Single-log guarantee: markIncidentLogged allows logging exactly once per track', () {
      final filter = TemporalFilter(confirmationStreak: 1);
      final t0 = DateTime(2026, 11, 6, 12, 0, 0);

      final det = DetectionResult(
        classId: 3,
        className: 'Pothole',
        confidence: 0.90,
        normalizedRect: const Rect.fromLTRB(0.4, 0.6, 0.6, 0.8),
      );

      final tracks = filter.processFrame([det], timestamp: t0);
      final trackId = tracks.first.trackingId;

      // First call -> successfully logged
      final firstLog = filter.markIncidentLogged(trackId);
      expect(firstLog, isTrue);

      // Subsequent call in next frame -> rejected as duplicate
      final secondLog = filter.markIncidentLogged(trackId);
      expect(secondLog, isFalse);

      final thirdLog = filter.markIncidentLogged(trackId);
      expect(thirdLog, isFalse);
    });
  });
}
