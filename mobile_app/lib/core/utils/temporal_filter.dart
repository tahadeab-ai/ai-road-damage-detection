import 'dart:math';
import 'package:flutter/material.dart';
import '../../features/detection/domain/models/detection_result.dart';
import 'nms_utils.dart';

/// A temporally smoothed, locked, and tracked detection candidate across camera frames.
class TrackedDetection {
  final int trackingId;
  final int classId;
  final String className;
  double confidence;
  Rect smoothedRect; // [left, top, right, bottom] normalized
  int streak; // Consecutive frames detected
  DateTime lastSeen;
  double opacity;
  double velocityDy; // Downward motion velocity per frame in normalized space

  TrackedDetection({
    required this.trackingId,
    required this.classId,
    required this.className,
    required this.confidence,
    required this.smoothedRect,
    this.streak = 1,
    DateTime? lastSeen,
    this.opacity = 1.0,
    this.velocityDy = 0.0,
  }) : lastSeen = lastSeen ?? DateTime.now();

  /// Confirmed if tracked across at least 3 consecutive frames (eliminates transient false positives).
  bool get isConfirmed => streak >= 3;

  /// High-confidence persistent target lock-on.
  bool get isLocked => isConfirmed;

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
/// smooths jitter with Exponential Moving Average (EMA), extrapolates downward road motion,
/// and maintains persistent spatial locks on verified road defects.
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

    // 1. Associate incoming detections with existing tracked objects using IoU & Centroid Distance
    for (final raw in rawDetections) {
      int? bestMatchIdx;
      double bestScore = 0.0;

      for (int i = 0; i < _trackedPool.length; i++) {
        if (matchedIndices.contains(i)) continue;
        final tracked = _trackedPool[i];

        // Must match class
        if (tracked.classId != raw.classId) continue;

        final iou = NmsUtils.calculateIoU(raw.normalizedRect, tracked.smoothedRect);
        final centroidDist = (raw.normalizedRect.center - tracked.smoothedRect.center).distance;

        // Dual association: strong IoU or tight spatial centroid proximity
        final isMatch = (iou > iouThreshold) || (iou > 0.12 && centroidDist < 0.22);

        if (isMatch) {
          final score = iou + (1.0 - centroidDist.clamp(0.0, 1.0));
          if (score > bestScore) {
            bestScore = score;
            bestMatchIdx = i;
          }
        }
      }

      if (bestMatchIdx != null) {
        // Update matched track with EMA coordinate smoothing and velocity estimation
        matchedIndices.add(bestMatchIdx);
        final track = _trackedPool[bestMatchIdx];
        track.confidence = raw.confidence;
        track.lastSeen = now;
        track.streak += 1;
        track.opacity = 1.0;

        // Estimate downward trajectory velocity
        final currentDy = raw.normalizedRect.center.dy - track.smoothedRect.center.dy;
        track.velocityDy = track.velocityDy * 0.7 + currentDy * 0.3;

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

    // 2. Extrapolate motion for unmatched confirmed tracks, decay opacity, and prune out-of-frame tracks
    _trackedPool.removeWhere((track) {
      // If object exited the bottom or sides of the camera frame, prune immediately
      if (track.smoothedRect.top > 1.05 || track.smoothedRect.bottom > 1.15) {
        return true;
      }

      final elapsedMs = now.difference(track.lastSeen).inMilliseconds;
      if (elapsedMs > persistenceMs) {
        return true; // Prune expired track
      }

      // If unmatched in this frame, apply smooth downward perspective motion extrapolation
      if (elapsedMs > 50) {
        if (track.isConfirmed && track.velocityDy > 0.0) {
          final stepDy = (track.velocityDy * 0.5).clamp(0.0, 0.02);
          track.smoothedRect = track.smoothedRect.translate(0, stepDy);
        }
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
