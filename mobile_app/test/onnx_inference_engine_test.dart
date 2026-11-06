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
  });
}
