import 'dart:math';
import 'dart:typed_data';

/// Result object describing camera occlusion diagnostics.
class OcclusionResult {
  final bool isOccluded;
  final String reason;
  final double flatCellRatio;
  final double meanLuminance;
  final bool isSkinTone;

  const OcclusionResult({
    required this.isOccluded,
    required this.reason,
    required this.flatCellRatio,
    required this.meanLuminance,
    required this.isSkinTone,
  });

  static const OcclusionResult clear = OcclusionResult(
    isOccluded: false,
    reason: 'Clear viewport',
    flatCellRatio: 0.0,
    meanLuminance: 0.5,
    isSkinTone: false,
  );
}

/// Advanced multi-cell spatial texture and chrominance occlusion detector.
/// Uses a 32x32 spatial grid (1024 cells) to measure local variance per cell,
/// preventing false triggers in night driving while reliably catching fingers,
/// hands, pocket fabrics, and physical lens caps.
class CameraOcclusionDetector {
  static const int gridResolution = 32; // 32x32 grid = 1024 cells
  static const int inputWidth = 640;
  static const int inputHeight = 640;
  static const int cellWidth = inputWidth ~/ gridResolution;   // 20 px
  static const int cellHeight = inputHeight ~/ gridResolution; // 20 px

  // Local variance threshold under which a 20x20 cell is considered textureless/flat
  static const double cellFlatVarianceThreshold = 0.00015;

  // Threshold: If over 90% of all cells are completely flat, lens is physically occluded
  static const double flatRatioThreshold = 0.90;

  /// Analyzes a normalized Float32List RGB buffer [640 * 640 * 3] in [0.0, 1.0].
  static OcclusionResult checkOcclusion(Float32List rgbBuffer) {
    if (rgbBuffer.length < inputWidth * inputHeight * 3) {
      return OcclusionResult.clear;
    }

    int flatCells = 0;
    double totalLumSum = 0.0;
    double totalRed = 0.0;
    double totalGreen = 0.0;
    double totalBlue = 0.0;
    int sampledPixelCount = 0;

    // Subsample 4 pixels per cell (step by 5 within each 20x20 cell) to ensure sub-millisecond execution
    const int step = 5;
    const int samplesPerCell = (cellWidth ~/ step) * (cellHeight ~/ step); // 16 samples per cell

    for (int gy = 0; gy < gridResolution; gy++) {
      final int startY = gy * cellHeight;
      for (int gx = 0; gx < gridResolution; gx++) {
        final int startX = gx * cellWidth;

        double cellSum = 0.0;
        double cellSqSum = 0.0;

        for (int py = 0; py < cellHeight; py += step) {
          final int y = startY + py;
          final int rowOffset = y * inputWidth * 3;

          for (int px = 0; px < cellWidth; px += step) {
            final int x = startX + px;
            final int idx = rowOffset + (x * 3);

            final double r = rgbBuffer[idx];
            final double g = rgbBuffer[idx + 1];
            final double b = rgbBuffer[idx + 2];

            // ITU-R BT.601 perceptual luminance
            final double lum = 0.299 * r + 0.587 * g + 0.114 * b;

            cellSum += lum;
            cellSqSum += lum * lum;

            totalLumSum += lum;
            totalRed += r;
            totalGreen += g;
            totalBlue += b;
            sampledPixelCount++;
          }
        }

        final double cellMean = cellSum / samplesPerCell;
        final double cellVar = (cellSqSum / samplesPerCell) - (cellMean * cellMean);

        if (cellVar < cellFlatVarianceThreshold) {
          flatCells++;
        }
      }
    }

    final int totalCells = gridResolution * gridResolution;
    final double flatRatio = flatCells / totalCells;
    final double meanLum = sampledPixelCount > 0 ? (totalLumSum / sampledPixelCount) : 0.0;
    final double avgR = sampledPixelCount > 0 ? (totalRed / sampledPixelCount) : 0.0;
    final double avgG = sampledPixelCount > 0 ? (totalGreen / sampledPixelCount) : 0.0;
    final double avgB = sampledPixelCount > 0 ? (totalBlue / sampledPixelCount) : 0.0;

    // Secondary skin-tone signal: Finger covering lens illuminated by ambient light or torch
    // Skin shows dominant red with high absorption in blue/green
    final bool isSkinTone = (avgR > 0.15) && (avgR > avgG * 1.30) && (avgR > avgB * 1.60);

    // Rule 1: High flat ratio with uniform skin-tone glow (finger on lens)
    if (flatRatio > 0.88 && isSkinTone) {
      return OcclusionResult(
        isOccluded: true,
        reason: 'Lens covered by finger (uniform skin chrominance)',
        flatCellRatio: flatRatio,
        meanLuminance: meanLum,
        isSkinTone: true,
      );
    }

    // Rule 2: Near total flatness regardless of darkness (lens cap, palm, solid obstacle)
    if (flatRatio > flatRatioThreshold) {
      // In genuine night driving, street lamps, headlights, and car reflections preserve variance
      // Pitch black + flat cells = obstructed lens
      if (meanLum < 0.06 || flatRatio > 0.95) {
        return OcclusionResult(
          isOccluded: true,
          reason: 'Lens physically covered (texture variance collapsed)',
          flatCellRatio: flatRatio,
          meanLuminance: meanLum,
          isSkinTone: isSkinTone,
        );
      }
    }

    return OcclusionResult(
      isOccluded: false,
      reason: 'Clear viewport',
      flatCellRatio: flatRatio,
      meanLuminance: meanLum,
      isSkinTone: isSkinTone,
    );
  }
}
