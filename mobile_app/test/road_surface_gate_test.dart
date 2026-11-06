import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/core/utils/camera_occlusion_detector.dart';
import 'package:road_guard_mobile/core/utils/road_surface_gate.dart';

void main() {
  group('RoadSurfaceGate Tests', () {
    const int bufferSize = 640 * 640 * 3;

    test('Verifies legitimate asphalt road (achromatic neutral grey + gravel texture)', () {
      final gate = RoadSurfaceGate(historySize: 3);
      final buffer = Float32List(bufferSize);
      final rand = Random(42);

      // Asphalt texture: neutral grey (R ~= G ~= B) with high-frequency noise
      for (int i = 0; i < bufferSize; i += 3) {
        final double base = 0.28 + rand.nextDouble() * 0.12;
        buffer[i] = base;
        buffer[i + 1] = base + (rand.nextDouble() * 0.02 - 0.01);
        buffer[i + 2] = base + (rand.nextDouble() * 0.02 - 0.01);
      }

      RoadGateEvaluation eval = gate.evaluateSurface(buffer);
      // Run 3 frames to fill temporal history
      eval = gate.evaluateSurface(buffer);
      eval = gate.evaluateSurface(buffer);

      expect(eval.status, RoadSurfaceStatus.roadDetected);
      expect(eval.status.isTraversableRoad, isTrue);
      expect(eval.averageSaturation, lessThan(0.20));
    });

    test('Rejects colorful indoor carpet / Persian rug (high saturation)', () {
      final gate = RoadSurfaceGate(historySize: 3);
      final buffer = Float32List(bufferSize);
      final rand = Random(99);

      // Red/blue vibrant rug with fabric texture
      for (int i = 0; i < bufferSize; i += 3) {
        buffer[i] = 0.82 + rand.nextDouble() * 0.05;     // High vibrant red
        buffer[i + 1] = 0.15 + rand.nextDouble() * 0.05; // Low green
        buffer[i + 2] = 0.20 + rand.nextDouble() * 0.05; // Low blue
      }

      gate.evaluateSurface(buffer);
      gate.evaluateSurface(buffer);
      final eval = gate.evaluateSurface(buffer);

      expect(eval.status, RoadSurfaceStatus.nonRoad);
      expect(eval.status.isTraversableRoad, isFalse);
      expect(eval.rejectionReason, contains('High color saturation'));
    });

    test('Rejects parquet wood flooring (warm yellow-brown hue)', () {
      final gate = RoadSurfaceGate(historySize: 3);
      final buffer = Float32List(bufferSize);
      final rand = Random(77);

      // Warm oak wood color with grain texture: R~0.72, G~0.48, B~0.22
      for (int i = 0; i < bufferSize; i += 3) {
        buffer[i] = 0.70 + rand.nextDouble() * 0.04;
        buffer[i + 1] = 0.46 + rand.nextDouble() * 0.04;
        buffer[i + 2] = 0.20 + rand.nextDouble() * 0.04;
      }

      gate.evaluateSurface(buffer);
      gate.evaluateSurface(buffer);
      final eval = gate.evaluateSurface(buffer);

      expect(eval.status, RoadSurfaceStatus.nonRoad);
      expect(eval.rejectionReason, contains('Parquet/wood floor'));
    });

    test('Rejects featureless smooth painted wall / ceiling', () {
      final gate = RoadSurfaceGate(historySize: 3);
      final buffer = Float32List(bufferSize);

      // Uniform white/beige wall with zero edges (bright lum = 0.88)
      for (int i = 0; i < bufferSize; i += 3) {
        buffer[i] = 0.88;
        buffer[i + 1] = 0.88;
        buffer[i + 2] = 0.88;
      }

      gate.evaluateSurface(buffer);
      gate.evaluateSurface(buffer);
      final eval = gate.evaluateSurface(buffer);

      expect(eval.status, RoadSurfaceStatus.nonRoad);
      expect(eval.rejectionReason, contains('Featureless smooth surface'));
    });

    test('Emits cameraObstructed when lens is covered', () {
      final gate = RoadSurfaceGate(historySize: 3);
      final buffer = Float32List(bufferSize); // all black

      final eval = gate.evaluateSurface(buffer);

      expect(eval.status, RoadSurfaceStatus.cameraObstructed);
      expect(eval.status.isTraversableRoad, isFalse);
    });
  });
}
