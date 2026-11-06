import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/features/detection/data/datasources/onnx_inference_engine.dart';

void main() {
  group('OnnxInferenceEngine Tests', () {
    test('Enforces strict 4-class authoritative RDD2022 taxonomy', () {
      expect(OnnxInferenceEngine.authoritativeLabels.length, 4);
      expect(OnnxInferenceEngine.authoritativeLabels[0], 'Longitudinal Crack');
      expect(OnnxInferenceEngine.authoritativeLabels[1], 'Transverse Crack');
      expect(OnnxInferenceEngine.authoritativeLabels[2], 'Alligator Crack');
      expect(OnnxInferenceEngine.authoritativeLabels[3], 'Pothole');
    });

    test('Transposes HWC [640, 640, 3] to NCHW [3, 640, 640] with correct channel ordering', () {
      const int plane = 640 * 640;
      final hwc = Float32List(3 * plane);

      // Set distinct test values in R, G, B channels
      for (int i = 0; i < plane; i++) {
        final idx = i * 3;
        hwc[idx] = 0.25;     // R
        hwc[idx + 1] = 0.50; // G
        hwc[idx + 2] = 0.75; // B
      }

      final chw = OnnxInferenceEngine.hwcToChw(hwc);
      expect(chw.length, 3 * plane);

      // Verify Channel 0 (R)
      expect(chw[0], 0.25);
      expect(chw[plane - 1], 0.25);

      // Verify Channel 1 (G)
      expect(chw[plane], 0.50);
      expect(chw[2 * plane - 1], 0.50);

      // Verify Channel 2 (B)
      expect(chw[2 * plane], 0.75);
      expect(chw[3 * plane - 1], 0.75);
    });

    test('Zero fabrication contract: Uninitialized engine returns empty detections', () async {
      final engine = OnnxInferenceEngine();
      expect(engine.isInitialized, isFalse);
      expect(engine.isModelLoaded, isFalse);

      final dummyBuffer = Float32List(640 * 640 * 3);
      final detections = await engine.runInference(dummyBuffer);

      expect(detections, isEmpty, reason: 'Must return empty list when model is uninitialized (no mock fallback)');
    });

    test('Decodes raw pixel-space [0, 640] YOLO tensor into normalized [0, 1] bounding boxes', () {
      // 8 rows x 2 predictions
      final outputMatrix = List.generate(8, (_) => List.filled(2, 0.0));

      // Candidate 0: Pothole (Class 3) at center [320, 480], w=128, h=64 in 640x640 pixel space
      outputMatrix[0][0] = 320.0; // cx
      outputMatrix[1][0] = 480.0; // cy (480 / 640 = 0.75, below horizon 0.35)
      outputMatrix[2][0] = 128.0; // w
      outputMatrix[3][0] = 64.0;  // h
      outputMatrix[4][0] = 0.05;  // cls 0 (D00)
      outputMatrix[5][0] = 0.02;  // cls 1 (D10)
      outputMatrix[6][0] = 0.03;  // cls 2 (D20)
      outputMatrix[7][0] = 0.88;  // cls 3 (D40 Pothole)

      // Candidate 1: Crack above horizon at [320, 100] (cy = 100 / 640 = 0.156 < 0.35) -> should be filtered
      outputMatrix[0][1] = 320.0;
      outputMatrix[1][1] = 100.0;
      outputMatrix[2][1] = 80.0;
      outputMatrix[3][1] = 80.0;
      outputMatrix[4][1] = 0.90; // cls 0

      final results = OnnxInferenceEngine.decodeYoloOutput(
        outputMatrix,
        confThreshold: 0.50,
        iouThreshold: 0.35,
        roadRoiTop: 0.35,
      );

      expect(results.length, 1);
      final pothole = results.first;
      expect(pothole.classId, 3);
      expect(pothole.className, 'Pothole');
      expect(pothole.confidence, closeTo(0.88, 1e-4));

      // Normalized coordinates: cx=0.5, cy=0.75, w=0.2, h=0.1
      // left = 0.5 - 0.1 = 0.4, right = 0.5 + 0.1 = 0.6
      // top = 0.75 - 0.05 = 0.7, bottom = 0.75 + 0.05 = 0.8
      expect(pothole.normalizedRect.left, closeTo(0.40, 1e-3));
      expect(pothole.normalizedRect.right, closeTo(0.60, 1e-3));
      expect(pothole.normalizedRect.top, closeTo(0.70, 1e-3));
      expect(pothole.normalizedRect.bottom, closeTo(0.80, 1e-3));
    });
  });
}
