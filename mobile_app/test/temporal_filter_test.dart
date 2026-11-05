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
        persistenceMs: 350,
        confirmationStreak: 3,
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
      expect(tracks.first.streak, equals(1));
      expect(tracks.first.isConfirmed, isFalse);
      expect(tracks.first.opacity, equals(1.0));
    });

    test('Consecutive frame detections confirm hazard after 3 frames', () {
      final now = DateTime.now();

      // Frame 1
      filter.processFrame([
        const DetectionResult(
          classId: 3,
          className: 'Pothole',
          confidence: 0.80,
          normalizedRect: Rect.fromLTWH(0.2, 0.4, 0.3, 0.2),
        ),
      ], timestamp: now);

      expect(filter.activeTracked.first.isConfirmed, isFalse);

      // Frame 2
      filter.processFrame([
        const DetectionResult(
          classId: 3,
          className: 'Pothole',
          confidence: 0.82,
          normalizedRect: Rect.fromLTWH(0.21, 0.41, 0.3, 0.2),
        ),
      ], timestamp: now.add(const Duration(milliseconds: 33)));

      expect(filter.activeTracked.first.streak, equals(2));
      expect(filter.activeTracked.first.isConfirmed, isFalse);

      // Frame 3 (Confirmation Gate)
      filter.processFrame([
        const DetectionResult(
          classId: 3,
          className: 'Pothole',
          confidence: 0.85,
          normalizedRect: Rect.fromLTWH(0.20, 0.40, 0.3, 0.2),
        ),
      ], timestamp: now.add(const Duration(milliseconds: 66)));

      expect(filter.activeTracked.first.streak, equals(3));
      expect(filter.activeTracked.first.isConfirmed, isTrue);
      expect(filter.activeTracked.first.isCritical, isTrue);
    });

    test('EMA smoothing blends coordinates between consecutive frames', () {
      final now = DateTime.now();

      // Frame 1: left = 0.20
      filter.processFrame([
        const DetectionResult(
          classId: 1,
          className: 'Transverse Crack',
          confidence: 0.75,
          normalizedRect: Rect.fromLTWH(0.20, 0.50, 0.40, 0.10),
        ),
      ], timestamp: now);

      // Frame 2: left = 0.30, with emaAlpha = 0.50 -> expected left = 0.20 * 0.5 + 0.30 * 0.5 = 0.25
      filter.processFrame([
        const DetectionResult(
          classId: 1,
          className: 'Transverse Crack',
          confidence: 0.78,
          normalizedRect: Rect.fromLTWH(0.30, 0.50, 0.40, 0.10),
        ),
      ], timestamp: now.add(const Duration(milliseconds: 33)));

      final track = filter.activeTracked.first;
      expect(track.smoothedRect.left, closeTo(0.25, 0.001));
    });

    test('Persistence buffer preserves tracks with decaying opacity on dropped frame', () {
      final now = DateTime.now();

      // Frame 1
      filter.processFrame([
        const DetectionResult(
          classId: 2,
          className: 'Alligator Crack',
          confidence: 0.70,
          normalizedRect: Rect.fromLTWH(0.3, 0.5, 0.2, 0.2),
        ),
      ], timestamp: now);

      // Frame 2: Dropped frame (empty detections) at +150ms
      final tracks = filter.processFrame([], timestamp: now.add(const Duration(milliseconds: 150)));
      expect(tracks.length, equals(1));
      expect(tracks.first.opacity, lessThan(1.0));
      expect(tracks.first.opacity, greaterThan(0.0));

      // Frame 3: Expired after persistenceMs (e.g. +400ms)
      final expiredTracks = filter.processFrame([], timestamp: now.add(const Duration(milliseconds: 400)));
      expect(expiredTracks, isEmpty);
    });
  });
}
