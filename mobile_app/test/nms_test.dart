import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/core/utils/nms_utils.dart';
import 'package:road_guard_mobile/features/detection/domain/models/detection_result.dart';

void main() {
  group('NmsUtils Unit Tests', () {
    test('calculateIoU returns 1.0 for identical rectangles', () {
      const rectA = Rect.fromLTWH(0.2, 0.2, 0.4, 0.4);
      const rectB = Rect.fromLTWH(0.2, 0.2, 0.4, 0.4);

      final iou = NmsUtils.calculateIoU(rectA, rectB);
      expect(iou, closeTo(1.0, 0.0001));
    });

    test('calculateIoU returns 0.0 for completely disjoint rectangles', () {
      const rectA = Rect.fromLTWH(0.0, 0.0, 0.2, 0.2);
      const rectB = Rect.fromLTWH(0.5, 0.5, 0.2, 0.2);

      final iou = NmsUtils.calculateIoU(rectA, rectB);
      expect(iou, equals(0.0));
    });

    test('calculateIoU computes correct ratio for 50% overlapping boxes', () {
      // Box A: [0, 0, 2, 2] -> Area = 4
      // Box B: [1, 0, 2, 2] -> Area = 4
      // Intersection: [1, 0, 1, 2] -> Area = 2
      // Union: 4 + 4 - 2 = 6 -> IoU = 2/6 = 0.3333
      const rectA = Rect.fromLTWH(0.0, 0.0, 2.0, 2.0);
      const rectB = Rect.fromLTWH(1.0, 0.0, 2.0, 2.0);

      final iou = NmsUtils.calculateIoU(rectA, rectB);
      expect(iou, closeTo(2.0 / 6.0, 0.001));
    });

    test('performNMS suppresses highly overlapping same-class boxes', () {
      final detections = [
        const DetectionResult(
          classId: 3,
          className: 'Pothole',
          confidence: 0.90,
          normalizedRect: Rect.fromLTWH(0.30, 0.50, 0.20, 0.20),
        ),
        // Duplicate box slightly shifted with lower confidence
        const DetectionResult(
          classId: 3,
          className: 'Pothole',
          confidence: 0.75,
          normalizedRect: Rect.fromLTWH(0.31, 0.51, 0.20, 0.20),
        ),
        // Distinct non-overlapping pothole
        const DetectionResult(
          classId: 3,
          className: 'Pothole',
          confidence: 0.85,
          normalizedRect: Rect.fromLTWH(0.70, 0.60, 0.15, 0.15),
        ),
      ];

      final suppressed = NmsUtils.performNMS(detections, iouThreshold: 0.45);

      expect(suppressed.length, equals(2));
      expect(suppressed.first.confidence, equals(0.90));
      expect(suppressed.last.confidence, equals(0.85));
    });

    test('performNMS preserves co-located boxes of different classes', () {
      final detections = [
        const DetectionResult(
          classId: 3,
          className: 'Pothole',
          confidence: 0.90,
          normalizedRect: Rect.fromLTWH(0.30, 0.50, 0.20, 0.20),
        ),
        const DetectionResult(
          classId: 2,
          className: 'Alligator Crack',
          confidence: 0.80,
          normalizedRect: Rect.fromLTWH(0.30, 0.50, 0.20, 0.20),
        ),
      ];

      final suppressed = NmsUtils.performNMS(detections, iouThreshold: 0.45);

      // Both classes must be preserved
      expect(suppressed.length, equals(2));
    });
  });
}
