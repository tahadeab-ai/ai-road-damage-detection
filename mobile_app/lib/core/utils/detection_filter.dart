import 'package:flutter/material.dart';
import '../../features/detection/domain/models/detection_result.dart';

/// Rejection reason code for discarded candidate bounding boxes.
enum FilterRejectionReason {
  none,
  invalidTaxonomyClass,
  borderArtifact,
  minimumAreaViolation,
  aspectRatioViolation,
  belowTrackingFloor,
  belowLoggingFloor,
}

/// Result of evaluating a candidate bounding box against automotive safety filters.
class FilterEvaluation {
  final bool isValidForTracking;
  final bool isValidForLogging;
  final FilterRejectionReason reason;

  const FilterEvaluation({
    required this.isValidForTracking,
    required this.isValidForLogging,
    required this.reason,
  });

  static const valid = FilterEvaluation(
    isValidForTracking: true,
    isValidForLogging: true,
    reason: FilterRejectionReason.none,
  );

  static const trackingOnly = FilterEvaluation(
    isValidForTracking: true,
    isValidForLogging: false,
    reason: FilterRejectionReason.belowLoggingFloor,
  );

  static FilterEvaluation rejected(FilterRejectionReason reason) => FilterEvaluation(
        isValidForTracking: false,
        isValidForLogging: false,
        reason: reason,
      );
}

/// Explicit rule-based geometric and statistical detection filter for RoadGuard AI V1.2.
///
/// Prevents border edge artifacts, sub-resolution noise, extreme aspect ratio distortions,
/// out-of-taxonomy classifications (e.g. speed breakers), and low-confidence hallucinations
/// from contaminating the tracking and persistence layers.
class DetectionFilter {
  static const double borderThreshold = 0.02; // 2% boundary margin
  static const double minDimensionThreshold = 0.02; // Minimum 2% width / height
  static const double highConfidenceBypass = 0.90; // Override threshold for exceptional detections
  static const double trackingConfidenceFloor = 0.35; // Minimum confidence to admit into tracker
  static const double loggingConfidenceFloor = 0.50; // Minimum confidence to persist to SQLite

  /// Valid RDD2022 taxonomy classes: D00 (0), D10 (1), D20 (2), D40 (3).
  static const Set<int> allowedTaxonomyClasses = {0, 1, 2, 3};

  /// Evaluates normalized box coordinates [rect], [classId], and [confidence].
  static FilterEvaluation evaluate({
    required Rect rect,
    required int classId,
    required double confidence,
  }) {
    // 1. Class taxonomy filtering: reject non-RDD classes (e.g. Speed Breaker = 4)
    if (!allowedTaxonomyClasses.contains(classId)) {
      return FilterEvaluation.rejected(FilterRejectionReason.invalidTaxonomyClass);
    }

    // 2. Class confidence floor: absolute rejection below tracking floor
    if (confidence < trackingConfidenceFloor) {
      return FilterEvaluation.rejected(FilterRejectionReason.belowTrackingFloor);
    }

    final bool isHighConfidence = confidence >= highConfidenceBypass;

    // 3. Border rejection: drop boxes touching or within 2% of the image boundary unless conf > 0.90
    if (!isHighConfidence) {
      if (rect.left < borderThreshold ||
          rect.top < borderThreshold ||
          rect.right > (1.0 - borderThreshold) ||
          rect.bottom > (1.0 - borderThreshold)) {
        return FilterEvaluation.rejected(FilterRejectionReason.borderArtifact);
      }
    }

    // 4. Minimum area rejection: drop boxes with width < 0.02 or height < 0.02 unless conf > 0.90
    if (!isHighConfidence) {
      if (rect.width < minDimensionThreshold || rect.height < minDimensionThreshold) {
        return FilterEvaluation.rejected(FilterRejectionReason.minimumAreaViolation);
      }
    }

    // 5. Aspect-ratio sanity: For D40 (pothole, classId == 3), reject aspect ratio > 4:1 or < 1:4 unless conf > 0.90
    if (classId == 3 && !isHighConfidence) {
      if (rect.height <= 0.0 || rect.width <= 0.0) {
        return FilterEvaluation.rejected(FilterRejectionReason.aspectRatioViolation);
      }
      final double aspectRatio = rect.width / rect.height;
      if (aspectRatio > 4.0 || aspectRatio < 0.25) {
        return FilterEvaluation.rejected(FilterRejectionReason.aspectRatioViolation);
      }
    }

    // 6. Check logging confidence floor
    final bool passesLogging = confidence >= loggingConfidenceFloor;

    return FilterEvaluation(
      isValidForTracking: true,
      isValidForLogging: passesLogging,
      reason: passesLogging ? FilterRejectionReason.none : FilterRejectionReason.belowLoggingFloor,
    );
  }

  /// Filters a list of raw [DetectionResult] candidates for tracking admission.
  static List<DetectionResult> filterForTracking(List<DetectionResult> detections) {
    return detections.where((d) {
      final eval = evaluate(
        rect: d.normalizedRect,
        classId: d.classId,
        confidence: d.confidence,
      );
      return eval.isValidForTracking;
    }).toList();
  }

  /// Filters a list of [DetectionResult] candidates for database persistence admission.
  static List<DetectionResult> filterForLogging(List<DetectionResult> detections) {
    return detections.where((d) {
      final eval = evaluate(
        rect: d.normalizedRect,
        classId: d.classId,
        confidence: d.confidence,
      );
      return eval.isValidForLogging;
    }).toList();
  }
}
