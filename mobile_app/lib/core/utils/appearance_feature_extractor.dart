import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// 16-Bin Hue-Saturation Color Histogram Descriptor for Multi-Modal Re-Identification.
/// Provides robust appearance tracking under vehicle motion and illumination variance.
class AppearanceFeatureExtractor {
  static const int numBins = 16;
  static const int hueBins = 8;
  static const int satBins = 8;
  static const double similarityThreshold = 0.75;
  static const double emaAlpha = 0.20; // 0.8 previous + 0.2 new

  /// Extracts a 16-bin Hue-Saturation color histogram from a normalized Float32 RGB buffer [640 * 640 * 3]
  /// restricted to the specified bounding box [normalizedRect].
  /// Returns a normalized 16-element float array where sum of bins equals 1.0.
  static List<double> extractHsHistogram({
    required Float32List rgbBuffer,
    required Rect normalizedRect,
    int imageWidth = 640,
    int imageHeight = 640,
  }) {
    final hist = List<double>.filled(numBins, 0.0);

    final int startX = (normalizedRect.left * imageWidth).clamp(0, imageWidth - 1).toInt();
    final int endX = (normalizedRect.right * imageWidth).clamp(0, imageWidth - 1).toInt();
    final int startY = (normalizedRect.top * imageHeight).clamp(0, imageHeight - 1).toInt();
    final int endY = (normalizedRect.bottom * imageHeight).clamp(0, imageHeight - 1).toInt();

    final int boxW = max(1, endX - startX);
    final int boxH = max(1, endY - startY);

    // Dynamic stride to sample roughly 100-250 points per candidate box for sub-millisecond execution
    final int stepX = max(1, boxW ~/ 16);
    final int stepY = max(1, boxH ~/ 16);

    int totalSamples = 0;

    for (int y = startY; y <= endY; y += stepY) {
      final int rowOffset = y * imageWidth * 3;
      for (int x = startX; x <= endX; x += stepX) {
        final int idx = rowOffset + (x * 3);
        if (idx + 2 >= rgbBuffer.length) continue;

        final double r = rgbBuffer[idx];
        final double g = rgbBuffer[idx + 1];
        final double b = rgbBuffer[idx + 2];

        final double maxC = max(r, max(g, b));
        final double minC = min(r, min(g, b));
        final double delta = maxC - minC;

        final double sat = maxC > 0.01 ? (delta / maxC) : 0.0;
        double hue = 0.0;
        if (delta > 0.01) {
          if (maxC == r) {
            hue = 60.0 * (((g - b) / delta) % 6);
          } else if (maxC == g) {
            hue = 60.0 * (((b - r) / delta) + 2);
          } else {
            hue = 60.0 * (((r - g) / delta) + 4);
          }
          if (hue < 0) hue += 360.0;
        }

        // Hue bins [0..7] (each bin is 45 degrees)
        final int hBin = ((hue / 360.0) * hueBins).floor().clamp(0, hueBins - 1);
        // Saturation bins [8..15] (each bin is 0.125 wide)
        final int sBin = hueBins + (sat * satBins).floor().clamp(0, satBins - 1);

        hist[hBin] += 0.5;
        hist[sBin] += 0.5;
        totalSamples++;
      }
    }

    if (totalSamples == 0) {
      // Uniform fallback
      return List<double>.filled(numBins, 1.0 / numBins);
    }

    // Normalize so sum equals 1.0
    final double sum = hist.reduce((a, b) => a + b);
    if (sum > 0.0) {
      for (int i = 0; i < numBins; i++) {
        hist[i] /= sum;
      }
    }

    return hist;
  }

  /// Calculates the Bhattacharyya coefficient similarity between two histograms.
  /// Returns a value in [0.0, 1.0], where 1.0 indicates identical color distribution.
  /// BC = sum(sqrt(p[i] * q[i]))
  static double computeBhattacharyyaSimilarity(List<double> hist1, List<double> hist2) {
    if (hist1.length != numBins || hist2.length != numBins) return 0.0;
    double bc = 0.0;
    for (int i = 0; i < numBins; i++) {
      bc += sqrt(max(0.0, hist1[i]) * max(0.0, hist2[i]));
    }
    return bc.clamp(0.0, 1.0);
  }

  /// Exponential Moving Average (EMA) smoothing for appearance descriptor:
  /// H_updated = (1 - alpha) * H_prev + alpha * H_new
  static List<double> updateEma(List<double> previousHist, List<double> newHist, {double alpha = emaAlpha}) {
    if (previousHist.length != numBins) return List<double>.from(newHist);
    if (newHist.length != numBins) return List<double>.from(previousHist);

    final updated = List<double>.filled(numBins, 0.0);
    for (int i = 0; i < numBins; i++) {
      updated[i] = ((1.0 - alpha) * previousHist[i]) + (alpha * newHist[i]);
    }

    // Renormalize
    final sum = updated.reduce((a, b) => a + b);
    if (sum > 0.0) {
      for (int i = 0; i < numBins; i++) {
        updated[i] /= sum;
      }
    }

    return updated;
  }
}
