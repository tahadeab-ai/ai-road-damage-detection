import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/core/utils/camera_occlusion_detector.dart';

void main() {
  group('CameraOcclusionDetector Tests', () {
    const int bufferSize = 640 * 640 * 3;

    test('Detects completely covered dark lens (flat black)', () {
      final buffer = Float32List(bufferSize); // all 0.0
      final result = CameraOcclusionDetector.checkOcclusion(buffer);

      expect(result.isOccluded, isTrue);
      expect(result.flatCellRatio, greaterThanOrEqualTo(0.95));
    });

    test('Detects finger covering lens (uniform reddish skin chrominance + flat texture)', () {
      final buffer = Float32List(bufferSize);
      final rand = Random(42);

      // Fill with uniform skin-like color: high Red, lower Green/Blue with tiny noise
      for (int i = 0; i < bufferSize; i += 3) {
        buffer[i] = 0.55 + rand.nextDouble() * 0.01;     // R
        buffer[i + 1] = 0.25 + rand.nextDouble() * 0.01; // G
        buffer[i + 2] = 0.15 + rand.nextDouble() * 0.01; // B
      }

      final result = CameraOcclusionDetector.checkOcclusion(buffer);
      expect(result.isOccluded, isTrue);
      expect(result.isSkinTone, isTrue);
      expect(result.flatCellRatio, greaterThan(0.88));
    });

    test('Allows real textured road scene with edges and asphalt contrast', () {
      final buffer = Float32List(bufferSize);
      final rand = Random(123);

      // Simulate road texture: noisy grey asphalt with high spatial variance across cells
      for (int y = 0; y < 640; y++) {
        for (int x = 0; x < 640; x++) {
          final int idx = (y * 640 + x) * 3;
          // Road aggregate noise
          final double base = 0.30 + rand.nextDouble() * 0.25;
          // Add high-contrast lane markings every 100 pixels
          final double lane = (x % 160 < 20 && y > 300) ? 0.85 : base;

          buffer[idx] = lane;
          buffer[idx + 1] = lane;
          buffer[idx + 2] = lane;
        }
      }

      final result = CameraOcclusionDetector.checkOcclusion(buffer);
      expect(result.isOccluded, isFalse);
      expect(result.flatCellRatio, lessThan(0.50));
    });

    test('Allows night driving scene with localized headlights/streetlights', () {
      final buffer = Float32List(bufferSize); // mostly dark road

      // Add bright streetlight / headlight beam in 15% of cells
      for (int y = 250; y < 450; y++) {
        for (int x = 200; x < 440; x++) {
          final int idx = (y * 640 + x) * 3;
          final double light = 0.70 + (x % 20) * 0.01;
          buffer[idx] = light;
          buffer[idx + 1] = light;
          buffer[idx + 2] = light * 0.8;
        }
      }

      final result = CameraOcclusionDetector.checkOcclusion(buffer);
      expect(result.isOccluded, isFalse);
    });
  });
}
