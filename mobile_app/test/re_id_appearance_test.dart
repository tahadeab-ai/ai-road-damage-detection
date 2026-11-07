import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/core/utils/appearance_feature_extractor.dart';
import 'package:road_guard_mobile/core/utils/temporal_filter.dart';
import 'package:road_guard_mobile/features/detection/domain/models/detection_result.dart';

void main() {
  group('Multi-Modal Re-ID & Appearance Descriptor Tests', () {
    test('Extracts valid 16-bin normalized Hue-Saturation histogram', () {
      final buffer = Float32List(640 * 640 * 3);
      // Fill central region with reddish-brown defect pixels
      for (int y = 200; y < 400; y++) {
        for (int x = 200; x < 400; x++) {
          final idx = (y * 640 + x) * 3;
          buffer[idx] = 0.8;     // R
          buffer[idx + 1] = 0.3; // G
          buffer[idx + 2] = 0.2; // B
        }
      }

      final hist = AppearanceFeatureExtractor.extractHsHistogram(
        rgbBuffer: buffer,
        normalizedRect: const Rect.fromLTWH(0.3, 0.3, 0.3, 0.3),
      );

      expect(hist.length, equals(16));
      final sum = hist.reduce((a, b) => a + b);
      expect(sum, closeTo(1.0, 1e-4));
      // Bins should have non-zero entries
      expect(hist.any((val) => val > 0.05), isTrue);
    });

    test('Bhattacharyya similarity returns 1.0 for identical histograms and low value for disjoint ones', () {
      final hist1 = List<double>.filled(16, 0.0);
      hist1[0] = 0.5;
      hist1[8] = 0.5;

      final hist2 = List<double>.from(hist1);
      final simIdentical = AppearanceFeatureExtractor.computeBhattacharyyaSimilarity(hist1, hist2);
      expect(simIdentical, closeTo(1.0, 1e-5));

      final histDisjoint = List<double>.filled(16, 0.0);
      histDisjoint[4] = 0.5;
      histDisjoint[12] = 0.5;
      final simDisjoint = AppearanceFeatureExtractor.computeBhattacharyyaSimilarity(hist1, histDisjoint);
      expect(simDisjoint, equals(0.0));
    });

    test('EMA histogram updates correctly blend previous and new distributions', () {
      final histPrev = List<double>.filled(16, 0.0);
      histPrev[0] = 1.0;

      final histNew = List<double>.filled(16, 0.0);
      histNew[1] = 1.0;

      // alpha = 0.2: updated = 0.8 * prev + 0.2 * new
      final updated = AppearanceFeatureExtractor.updateEma(histPrev, histNew, alpha: 0.2);
      expect(updated[0], closeTo(0.8, 1e-4));
      expect(updated[1], closeTo(0.2, 1e-4));
      final sum = updated.reduce((a, b) => a + b);
      expect(sum, closeTo(1.0, 1e-4));
    });

    test('TemporalFilter associates same defect with matching appearance and increments streak', () {
      final filter = TemporalFilter();
      final now = DateTime(2026, 11, 6, 12, 0, 0);

      // Create synthetic frame buffer with reddish pothole patch
      final buffer = Float32List(640 * 640 * 3);
      for (int i = 0; i < buffer.length; i += 3) {
        buffer[i] = 0.3;
        buffer[i + 1] = 0.3;
        buffer[i + 2] = 0.3;
      }
      // Pothole region
      for (int y = 300; y < 450; y++) {
        for (int x = 200; x < 350; x++) {
          final idx = (y * 640 + x) * 3;
          buffer[idx] = 0.7;
          buffer[idx + 1] = 0.2;
          buffer[idx + 2] = 0.1;
        }
      }

      // Frame 1: Initial detection
      const det1 = DetectionResult(
        classId: 3,
        className: 'Pothole',
        confidence: 0.88,
        normalizedRect: Rect.fromLTWH(0.35, 0.50, 0.20, 0.20),
      );
      final r1 = filter.processFrame([det1], timestamp: now, rgbBuffer: buffer);
      expect(r1.length, equals(1));
      final id1 = r1.first.trackingId;
      expect(r1.first.associationCount, equals(1));
      expect(r1.first.appearanceDescriptor, isNotNull);

      // Frame 2: Shifted slightly (matching appearance)
      const det2 = DetectionResult(
        classId: 3,
        className: 'Pothole',
        confidence: 0.90,
        normalizedRect: Rect.fromLTWH(0.36, 0.52, 0.20, 0.20),
      );
      final r2 = filter.processFrame(
        [det2],
        timestamp: now.add(const Duration(milliseconds: 100)),
        rgbBuffer: buffer,
      );
      expect(r2.length, equals(1));
      expect(r2.first.trackingId, equals(id1));
      expect(r2.first.associationCount, equals(2));
    });

    test('TemporalFilter rejects association when defect class or appearance diverges drastically', () {
      final filter = TemporalFilter();
      final now = DateTime(2026, 11, 6, 12, 0, 0);

      final bufferA = Float32List(640 * 640 * 3);
      // Red hue defect
      for (int i = 0; i < bufferA.length; i += 3) {
        bufferA[i] = 0.9;
        bufferA[i + 1] = 0.1;
        bufferA[i + 2] = 0.1;
      }

      // Frame 1
      const det1 = DetectionResult(
        classId: 3,
        className: 'Pothole',
        confidence: 0.85,
        normalizedRect: Rect.fromLTWH(0.4, 0.5, 0.2, 0.2),
      );
      filter.processFrame([det1], timestamp: now, rgbBuffer: bufferA);

      // Frame 2: Co-located detection with completely different class (classId: 0 instead of 3)
      const detDiffClass = DetectionResult(
        classId: 0,
        className: 'Longitudinal Crack',
        confidence: 0.80,
        normalizedRect: Rect.fromLTWH(0.4, 0.5, 0.2, 0.2),
      );
      final r2 = filter.processFrame(
        [detDiffClass],
        timestamp: now.add(const Duration(milliseconds: 100)),
        rgbBuffer: bufferA,
      );

      // Must NOT associate with the Pothole track; must create a new distinct track
      expect(r2.length, equals(2));
      expect(r2.map((t) => t.trackingId).toSet().length, equals(2));
    });
  });
}
