import 'dart:math';
import 'package:flutter/material.dart';
import '../../features/detection/domain/models/detection_result.dart';
import 'nms_utils.dart';

/// Explicit 4-stage tracking state machine for road damage detection lifecycle.
enum TrackingLifecycle {
  candidate, // Streak < 2: initial provisional detection
  tracking,  // Streak == 2: actively associated across consecutive frames
  confirmed, // Streak >= 3: verified physical road defect (logged once)
  lost,      // Temporarily missed in current frame, sustained within grace period
}

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
  TrackingLifecycle lifecycle;
  bool hasBeenLogged; // Prevents duplicate incident creation

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
    this.lifecycle = TrackingLifecycle.candidate,
    this.hasBeenLogged = false,
  }) : lastSeen = lastSeen ?? DateTime.now();

  /// Formatted automotive Track ID (e.g., #001, #042)
  String get formattedTrackId => '#${trackingId.toString().padLeft(3, '0')}';

  /// Confirmed if tracked across at least 3 consecutive frames.
  bool get isConfirmed => lifecycle == TrackingLifecycle.confirmed || streak >= 3;

  /// High-confidence persistent target lock-on.
  bool get isLocked => isConfirmed;

  /// Provisional candidate before multi-frame confirmation.
  bool get isCandidate => lifecycle == TrackingLifecycle.candidate;

  /// Active tracking phase.
  bool get isTracking => lifecycle == TrackingLifecycle.tracking;

  /// Missed in recent frame, preserved by temporal buffer grace period.
  bool get isLost => lifecycle == TrackingLifecycle.lost;

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
/// manages the 4-stage tracking lifecycle, and prevents duplicate incident creation.
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
    this.persistenceMs = 450,
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

        // Must match defect class
        if (tracked.classId != raw.classId) continue;

        final iou = NmsUtils.calculateIoU(raw.normalizedRect, tracked.smoothedRect);
        final centroidDist = (raw.normalizedRect.center - tracked.smoothedRect.center).distance;

        // Dual association: strong bounding box IoU or tight spatial centroid proximity
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

        // Update tracking lifecycle state
        if (track.streak >= confirmationStreak) {
          track.lifecycle = TrackingLifecycle.confirmed;
        } else if (track.streak == 2) {
          track.lifecycle = TrackingLifecycle.tracking;
        } else {
          track.lifecycle = TrackingLifecycle.candidate;
        }

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
            lifecycle: TrackingLifecycle.candidate,
          ),
        );
      }
    }

    // 2. Extrapolate motion for unmatched tracks, transition to lost, decay opacity, and prune
    _trackedPool.removeWhere((track) {
      // If object exited the bottom or sides of the camera frame, prune cleanly
      if (track.smoothedRect.top > 1.05 || track.smoothedRect.bottom > 1.15) {
        return true;
      }

      final elapsedMs = now.difference(track.lastSeen).inMilliseconds;
      if (elapsedMs > persistenceMs) {
        return true; // Prune genuinely lost track
      }

      // If unmatched in this frame, mark as lost and apply downward motion extrapolation
      if (elapsedMs > 50) {
        track.lifecycle = TrackingLifecycle.lost;
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
