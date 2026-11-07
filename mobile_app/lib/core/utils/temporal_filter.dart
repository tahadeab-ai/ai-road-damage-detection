import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../features/detection/domain/models/detection_result.dart';
import 'appearance_feature_extractor.dart';
import 'ego_motion_estimator.dart';
import 'inverse_perspective_mapping.dart';
import 'nms_utils.dart';

/// 4-stage tracking state machine for road damage detection lifecycle.
enum TrackingLifecycle {
  candidate, // Initial provisional detection awaiting temporal confirmation
  tracking,  // Actively associated across recent timestamps
  confirmed, // Confirmed defect across temporal confirmation window
  lost,      // Temporarily unassociated, sustained within wall-clock grace period
}

/// A temporally smoothed, locked, and tracked road defect candidate.
///
/// Lifecycle transitions and grace periods are governed strictly by wall-clock
/// milliseconds ([lastSeen], [firstSeen]), ensuring frame-rate invariance across
/// variable FPS regimes (e.g. 2 FPS, 15 FPS, 60 FPS).
class TrackedDetection {
  final int trackingId;
  final int classId;
  final String className;
  double confidence;
  Rect smoothedRect; // [left, top, right, bottom] normalized
  int associationCount; // Number of times successfully matched
  DateTime firstSeen;
  DateTime lastSeen; // Timestamp of most recent positive detection association
  double opacity;
  double velocityDy; // Normalized downward velocity per second
  TrackingLifecycle lifecycle;
  bool hasBeenLogged; // Prevents duplicate incident creation

  // Road-Plane Metric Coordinates & Appearance Descriptor
  Offset? roadCoordsMeters; // (X_m, Y_m) ground plane location relative to vehicle
  List<double>? appearanceDescriptor; // 16-bin Hue-Saturation color histogram

  TrackedDetection({
    required this.trackingId,
    required this.classId,
    required this.className,
    required this.confidence,
    required this.smoothedRect,
    this.associationCount = 1,
    DateTime? firstSeen,
    DateTime? lastSeen,
    this.opacity = 1.0,
    this.velocityDy = 0.0,
    this.lifecycle = TrackingLifecycle.candidate,
    this.hasBeenLogged = false,
    this.roadCoordsMeters,
    this.appearanceDescriptor,
  })  : firstSeen = firstSeen ?? DateTime.now(),
        lastSeen = lastSeen ?? DateTime.now();

  /// Formatted automotive Track ID (e.g., #001, #042)
  String get formattedTrackId => '#${trackingId.toString().padLeft(3, '0')}';

  /// Confirmed if lifecycle status is confirmed.
  bool get isConfirmed => lifecycle == TrackingLifecycle.confirmed;

  /// High-confidence persistent target lock-on.
  bool get isLocked => isConfirmed;

  /// Provisional candidate before multi-frame confirmation.
  bool get isCandidate => lifecycle == TrackingLifecycle.candidate;

  /// Active tracking phase.
  bool get isTracking => lifecycle == TrackingLifecycle.tracking;

  /// Missed in recent detection cycle, preserved by temporal buffer grace period.
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

/// Pure time-based Temporal Filter that associates detections across timestamps,
/// smooths jitter with Exponential Moving Average (EMA), integrates Inverse Perspective
/// Mapping (IPM), predicts vehicle ego-motion via 2D SE(2) transformations, manages
/// multi-modal Re-ID via 16-bin H-S histograms, and enforces a strict millisecond lifecycle:
///
/// - CONFIRMED -> LOST: after > 800 ms of no association
/// - LOST -> REMOVED: after > 3000 ms of no association
class TemporalFilter {
  final double iouThreshold;
  final double emaAlpha; // Weight for new frame coordinates (0.0 to 1.0)
  final int confirmationWindowMs; // Wall-clock time window required to confirm track (default 150ms)
  final int lostGraceThresholdMs; // Wall-clock timeout to transition CONFIRMED -> LOST (default 800ms)
  final int removalGraceThresholdMs; // Wall-clock timeout to transition LOST -> REMOVED (default 3000ms)

  final InversePerspectiveMapping ipm;
  final EgoMotionEstimator egoMotion;

  int _nextTrackingId = 1;
  final List<TrackedDetection> _trackedPool = [];
  DateTime? _lastFrameTimestamp;

  TemporalFilter({
    this.iouThreshold = 0.35,
    this.emaAlpha = 0.65,
    this.confirmationWindowMs = 150,
    this.lostGraceThresholdMs = 800,
    this.removalGraceThresholdMs = 3000,
    InversePerspectiveMapping? ipm,
    EgoMotionEstimator? egoMotion,
  })  : ipm = ipm ?? InversePerspectiveMapping(),
        egoMotion = egoMotion ?? EgoMotionEstimator();

  List<TrackedDetection> get activeTracked => List.unmodifiable(_trackedPool);

  /// Marks a confirmed tracked detection as officially logged.
  /// Returns `true` if this is the first time the defect is logged, `false` if already logged.
  bool markIncidentLogged(int trackingId) {
    for (final track in _trackedPool) {
      if (track.trackingId == trackingId) {
        if (!track.hasBeenLogged) {
          track.hasBeenLogged = true;
          return true;
        }
        return false;
      }
    }
    return false;
  }

  /// Updates tracked detections with raw detections from the latest observation timestamp.
  /// Integrates vehicle ego-motion prediction, road-plane spatial gating, and appearance Re-ID.
  List<TrackedDetection> processFrame(
    List<DetectionResult> rawDetections, {
    DateTime? timestamp,
    Float32List? rgbBuffer,
    double speedMps = 0.0,
    double gyroY = 0.0,
    double gyroZ = 0.0,
    double accelY = 0.0,
    bool isGpsDegraded = false,
  }) {
    final now = timestamp ?? DateTime.now();
    final double dtSec = _lastFrameTimestamp != null
        ? (now.difference(_lastFrameTimestamp!).inMicroseconds / 1000000.0).clamp(0.001, 1.0)
        : 0.033;
    _lastFrameTimestamp = now;

    // 1. Predict active tracks forward using 2D SE(2) vehicle ego-motion
    final bool isPitchDive = egoMotion.detectPitchDive(accelYMps2: accelY);
    final double worldYawRate = egoMotion.computeWorldYawRate(
      gyroYRadPerSec: gyroY,
      gyroZRadPerSec: gyroZ,
    );

    if (speedMps > 0.1 && !isGpsDegraded) {
      for (final track in _trackedPool) {
        if (track.roadCoordsMeters != null) {
          final predictedRoad = egoMotion.predictTargetPosition(
            currentRoadPointMeters: track.roadCoordsMeters!,
            dtSec: dtSec,
            speedMps: speedMps,
            yawRateRadPerSec: worldYawRate,
            isPitchDiveActive: isPitchDive,
          );
          track.roadCoordsMeters = predictedRoad;

          // Re-project metric position back to viewport for smooth bounding box translation
          final reprojectedOffset = ipm.roadPlaneToImage(predictedRoad.dx, predictedRoad.dy);
          if (reprojectedOffset != null) {
            final w = track.smoothedRect.width;
            final h = track.smoothedRect.height;
            final newLeft = (reprojectedOffset.dx - w / 2.0).clamp(0.0, 1.0 - w);
            final newTop = (reprojectedOffset.dy - h).clamp(0.0, 1.0 - h);
            track.smoothedRect = Rect.fromLTWH(newLeft, newTop, w, h);
          }
        }
      }
    }

    final matchedIndices = <int>{};

    // 2. Associate incoming detections with existing tracks
    for (final raw in rawDetections) {
      final double rawBottomU = (raw.normalizedRect.left + raw.normalizedRect.right) / 2.0;
      final double rawBottomV = raw.normalizedRect.bottom;
      final Offset? rawRoadCoords = ipm.imageToRoadPlane(rawBottomU, rawBottomV);

      List<double>? rawAppearance;
      if (rgbBuffer != null) {
        rawAppearance = AppearanceFeatureExtractor.extractHsHistogram(
          rgbBuffer: rgbBuffer,
          normalizedRect: raw.normalizedRect,
        );
      }

      int? bestMatchIdx;
      double bestScore = 0.0;

      for (int i = 0; i < _trackedPool.length; i++) {
        if (matchedIndices.contains(i)) continue;
        final tracked = _trackedPool[i];

        if (tracked.classId != raw.classId) continue;

        // Metric road-plane distance association
        bool isMetricMatch = false;
        if (rawRoadCoords != null && tracked.roadCoordsMeters != null) {
          final double dGate = isPitchDive
              ? 1.80
              : ipm.calculateAssociationGate(tracked.roadCoordsMeters!.dy);
          final double roadDistance = (rawRoadCoords - tracked.roadCoordsMeters!).distance;
          isMetricMatch = roadDistance <= dGate;
        }

        // Viewport pixel IoU & Centroid Distance association
        final iou = NmsUtils.calculateIoU(raw.normalizedRect, tracked.smoothedRect);
        final centroidDist = (raw.normalizedRect.center - tracked.smoothedRect.center).distance;
        final isPixelMatch = (iou > iouThreshold) || (iou > 0.12 && centroidDist < 0.22);

        if (!isMetricMatch && !isPixelMatch) continue;

        // Multi-modal Re-ID appearance check
        if (rawAppearance != null && tracked.appearanceDescriptor != null) {
          final appearanceSimilarity = AppearanceFeatureExtractor.computeBhattacharyyaSimilarity(
            tracked.appearanceDescriptor!,
            rawAppearance,
          );
          if (appearanceSimilarity < 0.65) continue;
        }

        final score = iou + (1.0 - centroidDist.clamp(0.0, 1.0)) + (isMetricMatch ? 1.0 : 0.0);
        if (score > bestScore) {
          bestScore = score;
          bestMatchIdx = i;
        }
      }

      if (bestMatchIdx != null) {
        matchedIndices.add(bestMatchIdx);
        final track = _trackedPool[bestMatchIdx];
        track.confidence = raw.confidence;
        track.lastSeen = now;
        track.associationCount += 1;
        track.opacity = 1.0;

        // Time-based lifecycle update:
        // Confirmed when associated at least twice spanning >= confirmationWindowMs or association count >= 2
        final lifespanMs = now.difference(track.firstSeen).inMilliseconds;
        if (track.associationCount >= 2 && lifespanMs >= confirmationWindowMs) {
          track.lifecycle = TrackingLifecycle.confirmed;
        } else if (track.associationCount >= 2) {
          track.lifecycle = TrackingLifecycle.tracking;
        } else {
          track.lifecycle = TrackingLifecycle.candidate;
        }

        // Estimate downward normalized velocity per second
        if (dtSec > 0.0) {
          final currentDy = (raw.normalizedRect.center.dy - track.smoothedRect.center.dy) / dtSec;
          track.velocityDy = track.velocityDy * 0.7 + currentDy * 0.3;
        }

        // EMA coordinate smoothing
        final newLeft = track.smoothedRect.left * (1.0 - emaAlpha) + raw.normalizedRect.left * emaAlpha;
        final newTop = track.smoothedRect.top * (1.0 - emaAlpha) + raw.normalizedRect.top * emaAlpha;
        final newRight = track.smoothedRect.right * (1.0 - emaAlpha) + raw.normalizedRect.right * emaAlpha;
        final newBottom = track.smoothedRect.bottom * (1.0 - emaAlpha) + raw.normalizedRect.bottom * emaAlpha;
        track.smoothedRect = Rect.fromLTRB(newLeft, newTop, newRight, newBottom);

        if (rawRoadCoords != null) {
          if (track.roadCoordsMeters != null) {
            final smX = track.roadCoordsMeters!.dx * 0.7 + rawRoadCoords.dx * 0.3;
            final smY = track.roadCoordsMeters!.dy * 0.7 + rawRoadCoords.dy * 0.3;
            track.roadCoordsMeters = Offset(smX, smY);
          } else {
            track.roadCoordsMeters = rawRoadCoords;
          }
        }

        if (rawAppearance != null) {
          if (track.appearanceDescriptor != null) {
            track.appearanceDescriptor = AppearanceFeatureExtractor.updateEma(
              track.appearanceDescriptor!,
              rawAppearance,
            );
          } else {
            track.appearanceDescriptor = rawAppearance;
          }
        }
      } else {
        // Spawn a new candidate track
        final newTrack = TrackedDetection(
          trackingId: _nextTrackingId++,
          classId: raw.classId,
          className: raw.className,
          confidence: raw.confidence,
          smoothedRect: raw.normalizedRect,
          associationCount: 1,
          firstSeen: now,
          lastSeen: now,
          opacity: 1.0,
          lifecycle: TrackingLifecycle.candidate,
          roadCoordsMeters: rawRoadCoords,
          appearanceDescriptor: rawAppearance,
        );
        _trackedPool.add(newTrack);
        matchedIndices.add(_trackedPool.length - 1);
      }
    }

    // 3. Time-based lifecycle transitions for unassociated tracks:
    // CONFIRMED / TRACKING -> LOST after unassociatedMs > lostGraceThresholdMs (800 ms)
    for (int i = 0; i < _trackedPool.length; i++) {
      if (!matchedIndices.contains(i)) {
        final track = _trackedPool[i];
        final unassociatedMs = now.difference(track.lastSeen).inMilliseconds;

        if (unassociatedMs > lostGraceThresholdMs) {
          track.lifecycle = TrackingLifecycle.lost;
        }

        if (track.isConfirmed && track.velocityDy > 0.0) {
          final stepDy = (track.velocityDy * dtSec).clamp(0.0, 0.05);
          track.smoothedRect = track.smoothedRect.translate(0, stepDy);
        }

        final remainingGraceRatio = 1.0 - (unassociatedMs / removalGraceThresholdMs);
        track.opacity = max(0.20, remainingGraceRatio.clamp(0.0, 1.0));
      }
    }

    // 4. Time-based track pruning:
    // Evict tracks when:
    // a. Out of viewport / passed under front bumper
    // b. Unassociated for > removalGraceThresholdMs (3000 ms)
    // c. Unconfirmed candidate unassociated for > lostGraceThresholdMs (800 ms)
    _trackedPool.removeWhere((track) {
      if (track.smoothedRect.top > 1.05 || track.smoothedRect.bottom > 1.15) {
        return true;
      }
      if (track.roadCoordsMeters != null && track.roadCoordsMeters!.dy < 0.20) {
        return true; // Passed under front bumper
      }

      final unassociatedMs = now.difference(track.lastSeen).inMilliseconds;
      if (unassociatedMs > removalGraceThresholdMs) {
        return true; // LOST -> REMOVED after > 3000 ms
      }
      if (track.isCandidate && unassociatedMs > lostGraceThresholdMs) {
        return true; // Unconfirmed candidate dropped after grace timeout
      }

      return false;
    });

    return List.unmodifiable(_trackedPool);
  }

  /// Clears all active tracks and resets tracking ID counter.
  void reset() {
    _trackedPool.clear();
    _nextTrackingId = 1;
    _lastFrameTimestamp = null;
  }
}
