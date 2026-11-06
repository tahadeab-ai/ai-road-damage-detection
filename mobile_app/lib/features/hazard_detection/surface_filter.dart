class RoadSurfaceContextFilter {
  final bool enabled;
  final double minHorizonRatio;
  final double highConfidenceBypass;

  RoadSurfaceContextFilter({
    this.enabled = true,
    this.minHorizonRatio = 0.30,
    this.highConfidenceBypass = 0.65,
  });

  bool filterDetection({
    required Map<String, dynamic> detection,
    required double frameWidth,
    required double frameHeight,
  }) {
    // Debug Toggle Bypass: If disabled, allow all candidate detections through
    if (!enabled) {
      return true;
    }

    final double conf = (detection['confidence'] as num).toDouble();
    final List<double> bbox = (detection['bbox'] as List).cast<double>();

    // Rule 1: High-Confidence Safety Bypass
    // Genuine high-confidence hazard detections are NEVER suppressed.
    if (conf >= highConfidenceBypass) {
      return true;
    }

    final double y2 = bbox[3];
    final double normalizedY2 = y2 > 1.0 ? (y2 / frameHeight) : y2;

    // Rule 2: Geometric Perspective Horizon Sanity Check
    // Rejects artifacts occurring entirely above the road perspective horizon (sky, trees, glare).
    if (normalizedY2 < minHorizonRatio) {
      return false;
    }

    return true;
  }

  List<Map<String, dynamic>> filterBatch({
    required List<Map<String, dynamic>> detections,
    required double frameWidth,
    required double frameHeight,
  }) {
    return detections.where((det) {
      return filterDetection(
        detection: det,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
      );
    }).toList();
  }
}
