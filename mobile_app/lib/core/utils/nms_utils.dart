import 'dart:math';
import 'package:flutter/material.dart';
import '../../features/detection/domain/models/detection_result.dart';

/// Non-Maximum Suppression (NMS) and geometry math utilities for object detection.
class NmsUtils {
  /// Computes Intersection over Union (IoU) between two rectangles.
  static double calculateIoU(Rect a, Rect b) {
    final double intersectionLeft = max(a.left, b.left);
    final double intersectionTop = max(a.top, b.top);
    final double intersectionRight = min(a.right, b.right);
    final double intersectionBottom = min(a.bottom, b.bottom);

    final double intersectionWidth = max(0.0, intersectionRight - intersectionLeft);
    final double intersectionHeight = max(0.0, intersectionBottom - intersectionTop);
    final double intersectionArea = intersectionWidth * intersectionHeight;

    final double areaA = a.width * a.height;
    final double areaB = b.width * b.height;
    final double unionArea = areaA + areaB - intersectionArea;

    if (unionArea <= 0.0) return 0.0;
    return intersectionArea / unionArea;
  }

  /// Performs Non-Maximum Suppression on candidates per-class.
  /// Eliminates overlapping bounding boxes that exceed [iouThreshold].
  static List<DetectionResult> performNMS(
    List<DetectionResult> detections, {
    double iouThreshold = 0.45,
    double confThreshold = 0.35,
    int maxDetections = 50,
  }) {
    if (detections.isEmpty) return [];

    // Filter by confidence
    final filtered = detections.where((d) => d.confidence >= confThreshold).toList();

    // Group by class to prevent cross-class suppression
    final Map<int, List<DetectionResult>> classGroups = {};
    for (final d in filtered) {
      classGroups.putIfAbsent(d.classId, () => []).add(d);
    }

    final List<DetectionResult> finalDetections = [];

    for (final group in classGroups.values) {
      // Sort descending by confidence
      group.sort((a, b) => b.confidence.compareTo(a.confidence));

      final List<DetectionResult> selected = [];

      for (final candidate in group) {
        if (selected.length >= maxDetections) break;

        bool shouldKeep = true;
        for (final accepted in selected) {
          final iou = calculateIoU(candidate.normalizedRect, accepted.normalizedRect);
          if (iou > iouThreshold) {
            shouldKeep = false;
            break;
          }
        }

        if (shouldKeep) {
          selected.add(candidate);
        }
      }

      finalDetections.addAll(selected);
    }

    // Sort all selected detections by confidence descending
    finalDetections.sort((a, b) => b.confidence.compareTo(a.confidence));
    return finalDetections.take(maxDetections).toList();
  }
}
