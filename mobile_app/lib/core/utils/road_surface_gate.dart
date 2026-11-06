import 'dart:math';
import 'dart:typed_data';
import 'camera_occlusion_detector.dart';

/// Explicit status of the physical surface facing the camera.
enum RoadSurfaceStatus {
  checking,
  roadDetected,
  nonRoad,
  cameraObstructed,
}

extension RoadSurfaceStatusX on RoadSurfaceStatus {
  String get labelEn {
    switch (this) {
      case RoadSurfaceStatus.checking:
        return 'Checking Surface...';
      case RoadSurfaceStatus.roadDetected:
        return 'Road Surface Verified';
      case RoadSurfaceStatus.nonRoad:
        return 'Non-Road Surface (Floor / Wall / Carpet)';
      case RoadSurfaceStatus.cameraObstructed:
        return 'Camera Obstructed';
    }
  }

  String get labelAr {
    switch (this) {
      case RoadSurfaceStatus.checking:
        return 'جارٍ فحص المسار...';
      case RoadSurfaceStatus.roadDetected:
        return 'طريق معتمد';
      case RoadSurfaceStatus.nonRoad:
        return 'سطح غير طرقي (أرضية / جدار / سجاد)';
      case RoadSurfaceStatus.cameraObstructed:
        return 'الكاميرا محجوبة';
    }
  }

  bool get isTraversableRoad => this == RoadSurfaceStatus.roadDetected;
}

/// Diagnostic evaluation details for road traversability.
class RoadGateEvaluation {
  final RoadSurfaceStatus status;
  final double roadLikelihood;
  final double averageSaturation;
  final double chromaDeviation;
  final double edgeDensity;
  final String rejectionReason;

  const RoadGateEvaluation({
    required this.status,
    required this.roadLikelihood,
    required this.averageSaturation,
    required this.chromaDeviation,
    required this.edgeDensity,
    required this.rejectionReason,
  });
}

/// Multi-color-space (HSL, YCbCr, Sobel edge variance) surface gatekeeper.
/// Rejects carpets, rugs, parquet wood, ceramic tiles, walls, ceilings, and indoor objects.
class RoadSurfaceGate {
  static const int inputWidth = 640;
  static const int inputHeight = 640;

  // Road Region of Interest: Lower 60% of frame (excluding top 35% horizon/sky/ceiling)
  static const int roiStartY = 224; // 35% of 640
  static const int roiEndY = 608;   // 95% of 640
  static const int roiStartX = 64;  // 10% of 640
  static const int roiEndX = 576;   // 90% of 640

  // Rolling temporal buffer for state stability
  final int historySize;
  final List<double> _confidenceHistory = [];
  RoadSurfaceStatus _currentStatus = RoadSurfaceStatus.checking;

  RoadSurfaceGate({this.historySize = 5});

  RoadSurfaceStatus get currentStatus => _currentStatus;

  /// Resets temporal state
  void reset() {
    _confidenceHistory.clear();
    _currentStatus = RoadSurfaceStatus.checking;
  }

  /// Evaluates normalized Float32List RGB buffer [640 * 640 * 3]
  RoadGateEvaluation evaluateSurface(
    Float32List rgbBuffer, {
    OcclusionResult? occlusion,
  }) {
    // 1. If camera is obstructed by finger or lens cap, prioritize Camera Obstructed
    final occ = occlusion ?? CameraOcclusionDetector.checkOcclusion(rgbBuffer);
    if (occ.isOccluded) {
      _currentStatus = RoadSurfaceStatus.cameraObstructed;
      return RoadGateEvaluation(
        status: RoadSurfaceStatus.cameraObstructed,
        roadLikelihood: 0.0,
        averageSaturation: 0.0,
        chromaDeviation: 0.0,
        edgeDensity: 0.0,
        rejectionReason: occ.reason,
      );
    }

    // 2. Sample pixels inside Road ROI
    int sampledCount = 0;
    double totalSat = 0.0;
    double totalChromaDev = 0.0;
    double totalEdgeContrast = 0.0;
    int highSaturationCount = 0;
    int warmWoodCount = 0;

    // Sample every 16th pixel inside Road ROI for deterministic, sub-millisecond throughput
    const int stepY = 16;
    const int stepX = 16;

    for (int y = roiStartY; y < roiEndY; y += stepY) {
      final int rowOffset = y * inputWidth * 3;
      final int nextRowOffset = (y + 1 < inputHeight ? (y + 1) : y) * inputWidth * 3;

      for (int x = roiStartX; x < roiEndX; x += stepX) {
        final int idx = rowOffset + (x * 3);
        final int rightIdx = rowOffset + ((x + 1 < inputWidth ? (x + 1) : x) * 3);
        final int downIdx = nextRowOffset + (x * 3);

        final double r = rgbBuffer[idx];
        final double g = rgbBuffer[idx + 1];
        final double b = rgbBuffer[idx + 2];

        // --- HSL Color-space Analysis ---
        final double maxC = max(r, max(g, b));
        final double minC = min(r, min(g, b));
        final double delta = maxC - minC;

        final double sat = maxC > 0.02 ? (delta / maxC) : 0.0;
        totalSat += sat;

        if (sat > 0.32) {
          highSaturationCount++;
        }

        // Detect warm wood / parquet floor / carpet hues (Hue 15° - 50° with saturation)
        if (delta > 0.05 && r > g && g > b) {
          final double hue = 60.0 * (((g - b) / delta) % 6);
          if (hue >= 15.0 && hue <= 55.0 && sat > 0.28) {
            warmWoodCount++;
          }
        }

        // --- YCbCr Color-space Chroma Deviation ---
        // Normalized YCbCr centered at 0.5
        final double cb = -0.168736 * r - 0.331264 * g + 0.500000 * b + 0.5;
        final double cr =  0.500000 * r - 0.418688 * g - 0.081312 * b + 0.5;
        final double chromaDev = sqrt((cb - 0.5) * (cb - 0.5) + (cr - 0.5) * (cr - 0.5));
        totalChromaDev += chromaDev;

        // --- High-Frequency Texture (Gradient Magnitude) ---
        final double rRight = rgbBuffer[rightIdx];
        final double rDown = rgbBuffer[downIdx];
        final double gradX = (r - rRight).abs();
        final double gradY = (r - rDown).abs();
        totalEdgeContrast += (gradX + gradY);

        sampledCount++;
      }
    }

    if (sampledCount == 0) {
      _currentStatus = RoadSurfaceStatus.checking;
      return const RoadGateEvaluation(
        status: RoadSurfaceStatus.checking,
        roadLikelihood: 0.5,
        averageSaturation: 0.0,
        chromaDeviation: 0.0,
        edgeDensity: 0.0,
        rejectionReason: 'Insufficient samples in ROI',
      );
    }

    final double avgSat = totalSat / sampledCount;
    final double avgChromaDev = totalChromaDev / sampledCount;
    final double avgEdge = totalEdgeContrast / sampledCount;
    final double highSatRatio = highSaturationCount / sampledCount;
    final double warmWoodRatio = warmWoodCount / sampledCount;

    // --- Deterministic Rejection Rules ---
    String rejection = '';

    // Rule A: Wood parquet or laminated floor (warm brown/yellow hue signature)
    if (warmWoodRatio > 0.20) {
      rejection = 'Parquet/wood floor signature detected';
    }
    // Rule B: Colorful carpet or rug (over 28% of road area has vibrant saturation)
    else if (highSatRatio > 0.28 || avgSat > 0.34) {
      rejection = 'High color saturation (carpet/rug/furnishing)';
    }
    // Rule C: Strong non-achromatic chroma deviation (indoor tiles or colored flooring)
    else if (avgChromaDev > 0.16) {
      rejection = 'Non-achromatic chroma deviation (indoor tile/floor)';
    }
    // Rule D: Completely smooth painted wall or ceiling (zero aggregate edge variance)
    else if (avgEdge < 0.005 && avgSat < 0.08) {
      rejection = 'Featureless smooth surface (wall/ceiling/table)';
    }

    final bool isRoadCandidate = rejection.isEmpty;

    // Calculate instantaneous road likelihood [0.0, 1.0]
    double roadProb = 1.0;
    if (!isRoadCandidate) {
      roadProb = max(0.0, 1.0 - (highSatRatio * 1.5 + avgChromaDev * 2.0));
      if (rejection.contains('Featureless')) roadProb = 0.05;
    } else {
      // Natural asphalt has low saturation (< 0.20), low chroma deviation, and moderate gravel texture
      final double satScore = (1.0 - (avgSat / 0.25)).clamp(0.0, 1.0);
      final double chromaScore = (1.0 - (avgChromaDev / 0.12)).clamp(0.0, 1.0);
      roadProb = (satScore * 0.5 + chromaScore * 0.5).clamp(0.55, 0.99);
    }

    // Temporal Filter: Update rolling history
    _confidenceHistory.add(roadProb);
    if (_confidenceHistory.length > historySize) {
      _confidenceHistory.removeAt(0);
    }

    final double meanConfidence = _confidenceHistory.reduce((a, b) => a + b) / _confidenceHistory.length;

    if (meanConfidence >= 0.55) {
      _currentStatus = RoadSurfaceStatus.roadDetected;
    } else {
      _currentStatus = RoadSurfaceStatus.nonRoad;
    }

    return RoadGateEvaluation(
      status: _currentStatus,
      roadLikelihood: meanConfidence,
      averageSaturation: avgSat,
      chromaDeviation: avgChromaDev,
      edgeDensity: avgEdge,
      rejectionReason: rejection.isEmpty ? 'Verified asphalt/concrete road surface' : rejection,
    );
  }
}
