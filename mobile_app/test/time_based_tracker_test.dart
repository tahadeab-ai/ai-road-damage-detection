import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/core/utils/temporal_filter.dart';
import 'package:road_guard_mobile/features/detection/domain/models/detection_result.dart';

void main() {
  group('Time-Based Tracker Invariance across Variable FPS', () {
    const double testBoxLeft = 0.40;
    const double testBoxTop = 0.50;
    const double testBoxRight = 0.60;
    const double testBoxBottom = 0.70;

    final baseDetection = DetectionResult(
      classId: 3, // D40 Pothole
      className: 'Pothole',
      confidence: 0.85,
      normalizedRect: const Rect.fromLTRB(testBoxLeft, testBoxTop, testBoxRight, testBoxBottom),
    );

    /// Simulates a tracking timeline from t=0ms to t=4500ms at given FPS.
    ///
    /// Detections are present from t=0ms to t=500ms (confirming the track).
    /// After t=500ms, detections cease.
    /// Evaluates track state at:
    /// - t ~ 1000ms (500ms unassociated): must be CONFIRMED (unassociated <= 800ms)
    /// - t ~ 1500ms (1000ms unassociated): must be LOST (unassociated > 800ms)
    /// - t ~ 3000ms (2500ms unassociated): must still be retained (unassociated <= 3000ms)
    /// - t ~ 4000ms (3500ms unassociated): must be REMOVED (unassociated > 3000ms)
    void runFpsSimulation(double fps) {
      final tracker = TemporalFilter(
        iouThreshold: 0.35,
        confirmationWindowMs: 150,
        lostGraceThresholdMs: 800,
        removalGraceThresholdMs: 3000,
      );

      final startTime = DateTime(2026, 11, 7, 12, 0, 0);
      final int stepMs = (1000.0 / fps).round();

      TrackingLifecycle? stateAt1000ms;
      TrackingLifecycle? stateAt1500ms;
      bool? presentAt3000ms;
      bool? presentAt4000ms;

      for (int currentMs = 0; currentMs <= 4500; currentMs += stepMs) {
        final currentTimestamp = startTime.add(Duration(milliseconds: currentMs));

        // Provide detections during confirmation phase (t <= 500ms)
        final detections = currentMs <= 500 ? [baseDetection] : <DetectionResult>[];

        final activeTracks = tracker.processFrame(
          detections,
          timestamp: currentTimestamp,
        );

        // Checkpoint at t ~ 1000ms (500ms after last association at t=500ms)
        if (stateAt1000ms == null && currentMs >= 1000 && currentMs <= 1100) {
          final t = activeTracks.where((t) => t.trackingId == 1).firstOrNull;
          stateAt1000ms = t?.lifecycle;
        }

        // Checkpoint at t ~ 1500ms (1000ms after last association at t=500ms)
        if (stateAt1500ms == null && currentMs >= 1500 && currentMs <= 1700) {
          final t = activeTracks.where((t) => t.trackingId == 1).firstOrNull;
          stateAt1500ms = t?.lifecycle;
        }

        // Checkpoint at t ~ 3000ms (2500ms after last association at t=500ms)
        if (presentAt3000ms == null && currentMs >= 3000 && currentMs <= 3200) {
          presentAt3000ms = activeTracks.any((t) => t.trackingId == 1);
        }

        // Checkpoint at t ~ 4000ms (3500ms after last association at t=500ms)
        if (presentAt4000ms == null && currentMs >= 4000) {
          presentAt4000ms = activeTracks.any((t) => t.trackingId == 1);
        }
      }

      expect(stateAt1000ms, equals(TrackingLifecycle.confirmed),
          reason: 'At $fps FPS, track should remain CONFIRMED when unassociated for 500ms (<= 800ms)');
      expect(stateAt1500ms, equals(TrackingLifecycle.lost),
          reason: 'At $fps FPS, track should transition to LOST when unassociated for 1000ms (> 800ms)');
      expect(presentAt3000ms, isTrue,
          reason: 'At $fps FPS, track should remain in pool when unassociated for 2500ms (<= 3000ms)');
      expect(presentAt4000ms, isFalse,
          reason: 'At $fps FPS, track should be REMOVED when unassociated for 3500ms (> 3000ms)');
    }

    test('Simulated 2 FPS maintains identical wall-clock track lifetime', () {
      runFpsSimulation(2.0);
    });

    test('Simulated 15 FPS maintains identical wall-clock track lifetime', () {
      runFpsSimulation(15.0);
    });

    test('Simulated 60 FPS maintains identical wall-clock track lifetime', () {
      runFpsSimulation(60.0);
    });
  });
}
