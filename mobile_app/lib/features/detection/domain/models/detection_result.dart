import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Represents a single bounding box detection produced by the on-device YOLO model.
class DetectionResult extends Equatable {
  final int classId;
  final String className;
  final double confidence;
  
  /// Normalized coordinates [0.0 - 1.0]: [xMin, yMin, xMax, yMax]
  final Rect normalizedRect;

  const DetectionResult({
    required this.classId,
    required this.className,
    required this.confidence,
    required this.normalizedRect,
  });

  /// Translates normalized coordinates into absolute canvas pixel coordinates.
  Rect toPixelRect(Size canvasSize) {
    return Rect.fromLTRB(
      normalizedRect.left * canvasSize.width,
      normalizedRect.top * canvasSize.height,
      normalizedRect.right * canvasSize.width,
      normalizedRect.bottom * canvasSize.height,
    );
  }

  /// Whether this defect poses a critical vehicular hazard.
  bool get isCritical => (classId == 3 || classId == 2) && confidence >= 0.65;

  Map<String, dynamic> toJson() {
    return {
      'class': className,
      'class_id': classId,
      'confidence': double.parse(confidence.toStringAsFixed(4)),
      'bbox_normalized': [
        normalizedRect.left,
        normalizedRect.top,
        normalizedRect.right,
        normalizedRect.bottom,
      ],
    };
  }

  factory DetectionResult.fromJson(Map<String, dynamic> json) {
    final bbox = (json['bbox_normalized'] as List).map((e) => (e as num).toDouble()).toList();
    return DetectionResult(
      classId: json['class_id'] as int,
      className: json['class'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      normalizedRect: Rect.fromLTRB(bbox[0], bbox[1], bbox[2], bbox[3]),
    );
  }

  @override
  List<Object?> get props => [classId, className, confidence, normalizedRect];
}
