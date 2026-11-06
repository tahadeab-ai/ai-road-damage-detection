import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:road_guard_mobile/features/hazard_detection/hazard_tracker.dart';
import 'package:road_guard_mobile/features/hazard_detection/surface_filter.dart';
import 'package:road_guard_mobile/shared/models/hazard_event.dart';

class InferenceEngine {
  final HazardTracker tracker;
  final RoadSurfaceContextFilter surfaceFilter;
  bool isFilterEnabled;
  final double confidenceThreshold;
  final double iouThreshold;

  InferenceEngine({
    HazardTracker? tracker,
    RoadSurfaceContextFilter? surfaceFilter,
    this.isFilterEnabled = true,
    this.confidenceThreshold = 0.45,
    this.iouThreshold = 0.50,
  })  : tracker = tracker ?? HazardTracker(),
        surfaceFilter = surfaceFilter ?? RoadSurfaceContextFilter(enabled: isFilterEnabled);

  void setFilterEnabled(bool enabled) {
    isFilterEnabled = enabled;
  }

  /// Decodes raw anchor-free YOLO output tensor of shape [8, 8400]
  /// Channels:
  ///   0: xc (normalized 0..1)
  ///   1: yc (normalized 0..1)
  ///   2: w  (normalized 0..1)
  ///   3: h  (normalized 0..1)
  ///   4: D00_longitudinal_crack score
  ///   5: D10_transverse_crack score
  ///   6: D20_alligator_crack score
  ///   7: D40_pothole score
  List<Map<String, dynamic>> decodeRawTensor({
    required List<List<double>> tensor, // [8][8400]
    required double frameWidth,
    required double frameHeight,
  }) {
    if (tensor.length < 8) return [];
    final int anchorCount = tensor[0].length;

    final List<Map<String, dynamic>> candidateDetections = [];

    for (int a = 0; a < anchorCount; a++) {
      // Find maximum class score among the 4 classes (indices 4..7)
      double maxScore = 0.0;
      int bestClassId = 0;

      for (int c = 0; c < 4; c++) {
        final double score = tensor[4 + c][a];
        if (score > maxScore) {
          maxScore = score;
          bestClassId = c;
        }
      }

      if (maxScore >= confidenceThreshold) {
        final double xc = tensor[0][a];
        final double yc = tensor[1][a];
        final double w = tensor[2][a];
        final double h = tensor[3][a];

        // Convert normalized center-size to absolute pixel bounding box [x1, y1, x2, y2]
        final double x1 = max(0.0, (xc - w / 2.0) * frameWidth);
        final double y1 = max(0.0, (yc - h / 2.0) * frameHeight);
        final double x2 = min(frameWidth, (xc + w / 2.0) * frameWidth);
        final double y2 = min(frameHeight, (yc + h / 2.0) * frameHeight);

        candidateDetections.add({
          'class_id': bestClassId,
          'confidence': maxScore,
          'bbox': [x1, y1, x2, y2],
        });
      }
    }

    if (candidateDetections.isEmpty) return [];

    // Apply Non-Maximum Suppression (NMS)
    return applyNMS(candidateDetections, iouThreshold);
  }

  /// Vectorized-equivalent greedy NMS for bounding boxes
  List<Map<String, dynamic>> applyNMS(
    List<Map<String, dynamic>> detections,
    double iouThreshold,
  ) {
    detections.sort((a, b) => (b['confidence'] as double).compareTo(a['confidence'] as double));

    final List<Map<String, dynamic>> retained = [];
    final List<bool> suppressed = List<bool>.filled(detections.length, false);

    for (int i = 0; i < detections.length; i++) {
      if (suppressed[i]) continue;

      final current = detections[i];
      retained.add(current);

      final List<double> b1 = (current['bbox'] as List).cast<double>();

      for (int j = i + 1; j < detections.length; j++) {
        if (suppressed[j]) continue;

        final List<double> b2 = (detections[j]['bbox'] as List).cast<double>();
        final double iou = _computeIoU(b1, b2);

        if (iou >= iouThreshold) {
          suppressed[j] = true;
        }
      }
    }

    return retained;
  }

  static double _computeIoU(List<double> b1, List<double> b2) {
    final double x1 = max(b1[0], b2[0]);
    final double y1 = max(b1[1], b2[1]);
    final double x2 = min(b1[2], b2[2]);
    final double y2 = min(b1[3], b2[3]);

    final double inter = max(0.0, x2 - x1) * max(0.0, y2 - y1);
    final double area1 = (b1[2] - b1[0]) * (b1[3] - b1[1]);
    final double area2 = (b2[2] - b2[0]) * (b2[3] - b2[1]);
    final double union = area1 + area2 - inter;

    if (union <= 0.0) return 0.0;
    return inter / union;
  }

  /// Complete inference frame processing step
  /// 1. Filters raw detections using RoadSurfaceContextFilter
  /// 2. Updates HazardTracker with timestamp
  /// 3. Returns active HUD alert tracks and newly confirmed HazardEvent incidents
  Map<String, dynamic> processFrameDetections({
    required List<Map<String, dynamic>> rawDetections,
    required double frameWidth,
    required double frameHeight,
    double? timestamp,
    double? latitude,
    double? longitude,
    double speedKmh = 0.0,
  }) {
    // Step 1: Road Surface Context Filter (with debug toggle)
    List<Map<String, dynamic>> filtered = rawDetections;
    if (isFilterEnabled) {
      filtered = surfaceFilter.filterBatch(
        detections: rawDetections,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
      );
    }

    // Step 2: Spatio-temporal tracking
    final trackingResult = tracker.processFrame(
      detections: filtered,
      timestampSeconds: timestamp,
    );

    final List<Map<String, dynamic>> activeTracks = trackingResult['hud_alerts'] ?? [];
    final List<Map<String, dynamic>> newlyLogged = trackingResult['logged_incidents'] ?? [];

    // Step 3: Convert logged incidents into domain HazardEvent models
    final List<HazardEvent> events = [];
    final now = DateTime.now();

    for (final log in newlyLogged) {
      final int classId = log['class_id'] as int;
      final double conf = (log['confidence'] as num).toDouble();
      final List<double> bbox = (log['bbox'] as List).cast<double>();

      final event = HazardEvent(
        incidentId: 'inc_${now.millisecondsSinceEpoch}_${log['track_id']}',
        trackId: log['track_id'] as int,
        classId: classId,
        className: HazardEvent.classNames[classId] ?? 'unknown',
        confidence: conf,
        bbox: bbox,
        timestamp: now,
        latitude: latitude,
        longitude: longitude,
        speedKmh: speedKmh,
        severity: HazardEvent.severityForClass(classId, conf),
        isSynced: false,
      );
      events.add(event);
    }

    return {
      'activeTracks': activeTracks,
      'newIncidents': events,
    };
  }
}
