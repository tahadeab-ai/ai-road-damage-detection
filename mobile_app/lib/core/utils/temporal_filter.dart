import 'dart:math';
import 'package:flutter/material.dart';
import '../../features/detection/domain/models/detection_result.dart';
import 'nms_utils.dart';

/// A temporally smoothed and tracked detection candidate across camera frames.
class TrackedDetection {
  final int trackingId;
  final int classId;
  final String className;
  double confidence;
  Rect smoothedRect; // [left, top, right, bottom] normalized
  int streak; // Consecutive frames detected
  DateTime lastSeen;
  double opacity;

  TrackedDetection({
    required this.trackingId,
    required this.classId,
    required this.className,
    required this.confidence,
    required this.smoothedRect,
    this.streak = 1,
    DateTime? lastSeen,
    this.opacity = 1.0,
  }) : lastSeen = lastSeen ?? DateTime.now();

  /// Confirmed if tracked across at least 3 consecutive frames (eliminates transient false positives).
  bool get isConfirmed => streak >= 3;

  /// Critical hazard: confirmed Pothole (D40) or Alligator Crack (D20).
  bool get isCritical => isConfirmed && (classId == 2 || classId == 3);

  DetectionResult toDetectionResult() {
    return DetectionResult(
      classId: classId,
      className: className,
      confidence: confidence,
      normalizedRect: smoothedRect,
    );
  }
}

/// Temporal Filter that associates detections across consecutive frames,
/// smooths jitter with Exponential Moving Average (EMA), and suppresses transient flickers.
class TemporalFilter {
  final double iouThreshold;
  final double emaAlpha; // Weight for new frame coordinates (0.0 to 1.0)
  final int persistenceMs; // Box lifetime decay when temporarily dropped
  final int confirmationStreak; // Frames required to confirm detection

  int _nextTrackingId = 1;
  final List<TrackedDetection> _trackedPool = [];

  TemporalFilter({
    this.iouThreshold = 0.35,
    this.emaAlpha = 0.60,
    this.persistenceMs = 350,
    this.confirmationStreak = 3,
  });

  List<TrackedDetection> get activeTracked => List.unmodifiable(_trackedPool);

  /// Updates tracked detections with raw detections from the latest frame.
  List<TrackedDetection> processFrame(
    List<DetectionResult> rawDetections, {
    DateTime? timestamp,
  }) {
    final now = timestamp ?? DateTime.now();
    final matchedIndices = <int>{};

    // 1. Associate incoming detections with existing tracked objects
    for (final raw in rawDetections) {
      int? bestMatchIdx;
      double bestIoU = 0.0;

      for (int i = 0; i < _trackedPool.length; i++) {
        if (matchedIndices.contains(i)) continue;
        final tracked = _trackedPool[i];

        // Must match class
        if (tracked.classId != raw.classId) continue;

        final iou = NmsUtils.calculateIoU(raw.normalizedRect, tracked.smoothedRect);
        if (iou > iouThreshold && iou > bestIoU) {
          bestIoU = iou;
          bestMatchIdx = i;
        }
      }

      if (bestMatchIdx != null) {
        // Update matched track with EMA coordinate smoothing
        matchedIndices.add(bestMatchIdx);
        final track = _trackedPool[bestMatchIdx];
        track.confidence = raw.confidence;
        track.lastSeen = now;
        track.streak += 1;
        track.opacity = 1.0;

        // Exponential Moving Average (EMA) smoothing on coordinates
        final newLeft = track.smoothedRect.left * (1.0 - emaAlpha) + raw.normalizedRect.left * emaAlpha;
        final newTop = track.smoothedRect.top * (1.0 - emaAlpha) + raw.normalizedRect.top * emaAlpha;
        final newRight = track.smoothedRect.right * (1.0 - emaAlpha) + raw.normalizedRect.right * emaAlpha;
        final newBottom = track.smoothedRect.bottom * (1.0 - emaAlpha) + raw.normalizedRect.bottom * emaAlpha;

        track.smoothedRect = Rect.fromLTRB(newLeft, newTop, newRight, newBottom);
      } else {
        // Spawn a new candidate track
        _trackedPool.add(
          TrackedDetection(
            trackingId: _nextTrackingId++,
            classId: raw.classId,
            className: raw.className,
            confidence: raw.confidence,
            smoothedRect: raw.normalizedRect,
            streak: 1,
            lastSeen: now,
            opacity: 1.0,
          ),
        );
      }
    }

    // 2. Decay opacity of unmatched tracks and prune expired ones
    _trackedPool.removeWhere((track) {
      final elapsedMs = now.difference(track.lastSeen).inMilliseconds;
      if (elapsedMs > persistenceMs) {
        return true; // Prune expired track
      }

      // If unmatched in this frame, decay opacity smoothly
      if (elapsedMs > 50) {
        final remainingRatio = 1.0 - (elapsedMs / persistenceMs);
        track.opacity = max(0.0, remainingRatio);
      }
      return false;
    });

    return _trackedPool;
  }

  /// Resets all active tracking memory.
  void reset() {
    _trackedPool.clear();
    _nextTrackingId = 1;
  }
}
