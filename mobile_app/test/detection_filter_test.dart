import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/core/utils/detection_filter.dart';
import 'package:road_guard_mobile/features/detection/domain/models/detection_result.dart';

void main() {
  group('Explicit Detection Filters for RoadGuard AI V1.2', () {
    test('1. Border artifact rejection drops edge-hugging candidate boxes', () {
      // Exact edge artifact recorded previously on device: left=0.873, top=0.886, right=1.000, bottom=0.993
      const artifactRect = Rect.fromLTRB(0.873, 0.886, 1.000, 0.993);
      final eval = DetectionFilter.evaluate(
        rect: artifactRect,
        classId: 3, // D40 Pothole
        confidence: 0.777,
      );

      expect(eval.isValidForTracking, isFalse);
      expect(eval.isValidForLogging, isFalse);
      expect(eval.reason, equals(FilterRejectionReason.borderArtifact));
    });

    test('2. Border candidate with exceptionally high confidence (>0.90) bypasses border filter', () {
      const nearEdgeRect = Rect.fromLTRB(0.01, 0.50, 0.20, 0.70);
      final eval = DetectionFilter.evaluate(
        rect: nearEdgeRect,
        classId: 0, // D00 Longitudinal Crack
        confidence: 0.94,
      );

      expect(eval.isValidForTracking, isTrue);
      expect(eval.isValidForLogging, isTrue);
      expect(eval.reason, equals(FilterRejectionReason.none));
    });

    test('3. Minimum area violation rejects tiny sub-resolution noise', () {
      // Box width = 0.01 (< 0.02 threshold)
      const tinyRect = Rect.fromLTWH(0.50, 0.50, 0.01, 0.10);
      final eval = DetectionFilter.evaluate(
        rect: tinyRect,
        classId: 1, // D10 Transverse Crack
        confidence: 0.75,
      );

      expect(eval.isValidForTracking, isFalse);
      expect(eval.reason, equals(FilterRejectionReason.minimumAreaViolation));
    });

    test('4. Aspect ratio sanity rejects distorted D40 pothole geometries', () {
      // Needle-thin horizontal box: width=0.40, height=0.04 (ratio 10:1 > 4:1)
      const wideBox = Rect.fromLTWH(0.30, 0.50, 0.40, 0.04);
      final evalWide = DetectionFilter.evaluate(
        rect: wideBox,
        classId: 3, // D40 Pothole
        confidence: 0.70,
      );
      expect(evalWide.isValidForTracking, isFalse);
      expect(evalWide.reason, equals(FilterRejectionReason.aspectRatioViolation));

      // Extremely tall needle box: width=0.03, height=0.30 (ratio 1:10 < 1:4)
      const tallBox = Rect.fromLTWH(0.40, 0.30, 0.03, 0.30);
      final evalTall = DetectionFilter.evaluate(
        rect: tallBox,
        classId: 3, // D40 Pothole
        confidence: 0.70,
      );
      expect(evalTall.isValidForTracking, isFalse);
      expect(evalTall.reason, equals(FilterRejectionReason.aspectRatioViolation));

      // Normal aspect ratio pothole (e.g. 0.20 x 0.15 = 1.33:1) passes
      const normalPothole = Rect.fromLTWH(0.40, 0.50, 0.20, 0.15);
      final evalNormal = DetectionFilter.evaluate(
        rect: normalPothole,
        classId: 3,
        confidence: 0.70,
      );
      expect(evalNormal.isValidForTracking, isTrue);
      expect(evalNormal.isValidForLogging, isTrue);
    });

    test('5. Non-D40 cracks (D00, D10) allow elongated aspect ratios', () {
      // Long crack: width=0.03, height=0.45 (ratio 1:15)
      const longCrack = Rect.fromLTWH(0.40, 0.30, 0.03, 0.45);
      final eval = DetectionFilter.evaluate(
        rect: longCrack,
        classId: 0, // D00 Longitudinal Crack
        confidence: 0.75,
      );
      expect(eval.isValidForTracking, isTrue);
    });

    test('6. Class confidence floors separate tracking (0.35) and logging (0.50)', () {
      const validRect = Rect.fromLTWH(0.30, 0.40, 0.20, 0.20);

      // Below tracking floor (< 0.35)
      final evalSub35 = DetectionFilter.evaluate(
        rect: validRect,
        classId: 2, // D20 Alligator Crack
        confidence: 0.32,
      );
      expect(evalSub35.isValidForTracking, isFalse);
      expect(evalSub35.reason, equals(FilterRejectionReason.belowTrackingFloor));

      // Valid for tracking, rejected for logging (0.35 <= conf < 0.50)
      final evalMid = DetectionFilter.evaluate(
        rect: validRect,
        classId: 2,
        confidence: 0.42,
      );
      expect(evalMid.isValidForTracking, isTrue);
      expect(evalMid.isValidForLogging, isFalse);
      expect(evalMid.reason, equals(FilterRejectionReason.belowLoggingFloor));

      // Valid for both tracking and logging (conf >= 0.50)
      final evalHigh = DetectionFilter.evaluate(
        rect: validRect,
        classId: 2,
        confidence: 0.65,
      );
      expect(evalHigh.isValidForTracking, isTrue);
      expect(evalHigh.isValidForLogging, isTrue);
    });

    test('7. Out-of-taxonomy classes (e.g. Speed Breaker = 4) are strictly rejected', () {
      const validRect = Rect.fromLTWH(0.30, 0.40, 0.30, 0.20);
      final eval = DetectionFilter.evaluate(
        rect: validRect,
        classId: 4, // Class 4 (Speed Breaker in 5-class model)
        confidence: 0.88,
      );
      expect(eval.isValidForTracking, isFalse);
      expect(eval.isValidForLogging, isFalse);
      expect(eval.reason, equals(FilterRejectionReason.invalidTaxonomyClass));
    });

    test('8. filterForTracking and filterForLogging apply correctly to batches', () {
      final list = [
        // 0: Valid pothole (conf 0.70)
        DetectionResult(
          classId: 3,
          className: 'Pothole',
          confidence: 0.70,
          normalizedRect: const Rect.fromLTWH(0.30, 0.40, 0.20, 0.15),
        ),
        // 1: Tracking only (conf 0.40)
        DetectionResult(
          classId: 0,
          className: 'Longitudinal Crack',
          confidence: 0.40,
          normalizedRect: const Rect.fromLTWH(0.30, 0.40, 0.20, 0.15),
        ),
        // 2: Border artifact (left = 0.005)
        DetectionResult(
          classId: 1,
          className: 'Transverse Crack',
          confidence: 0.70,
          normalizedRect: const Rect.fromLTWH(0.005, 0.40, 0.20, 0.15),
        ),
        // 3: Speed breaker (class 4)
        DetectionResult(
          classId: 4,
          className: 'Speed Breaker',
          confidence: 0.85,
          normalizedRect: const Rect.fromLTWH(0.30, 0.40, 0.20, 0.15),
        ),
      ];

      final trackingBatch = DetectionFilter.filterForTracking(list);
      expect(trackingBatch.length, equals(2)); // index 0 and 1
      expect(trackingBatch.map((d) => d.classId), containsAll([3, 0]));

      final loggingBatch = DetectionFilter.filterForLogging(list);
      expect(loggingBatch.length, equals(1)); // only index 0 (conf >= 0.50)
      expect(loggingBatch.first.classId, equals(3));
    });
  });
}
