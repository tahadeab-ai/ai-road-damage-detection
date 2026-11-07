import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/core/utils/yuv_converter.dart';

void main() {
  group('Zero-Allocation YUV_420_888 Converter Tests', () {
    const int srcW = 32;
    const int srcH = 24;
    const int dstSize = 16;

    late Uint8List yPlane;
    late Uint8List uPlane;
    late Uint8List vPlane;

    setUp(() {
      // Y plane: grayscale gradient
      yPlane = Uint8List(srcW * srcH);
      for (int i = 0; i < yPlane.length; i++) {
        yPlane[i] = (i % 256);
      }

      // U and V planes: 4:2:0 subsampled chroma (neutral 128)
      uPlane = Uint8List((srcW ~/ 2) * (srcH ~/ 2))..fillRange(0, (srcW ~/ 2) * (srcH ~/ 2), 128);
      vPlane = Uint8List((srcW ~/ 2) * (srcH ~/ 2))..fillRange(0, (srcW ~/ 2) * (srcH ~/ 2), 128);
    });

    test('yuv420ToInt8 produces exact buffer dimensions and respects INT8 quantization bounds', () {
      final int8Output = YuvConverter.yuv420ToInt8(
        yPlane: yPlane,
        uPlane: uPlane,
        vPlane: vPlane,
        srcWidth: srcW,
        srcHeight: srcH,
        uvRowStride: srcW ~/ 2,
        uvPixelStride: 1,
        yRowStride: srcW,
        dstSize: dstSize,
        inputScale: 0.003921568859368563, // 1.0 / 255.0
        inputZeroPoint: -128,
        sensorOrientation: 90,
      );

      expect(int8Output.length, equals(dstSize * dstSize * 3));

      // Verify that every single byte is clamped within valid INT8 range [-128, 127]
      for (int i = 0; i < int8Output.length; i++) {
        final val = int8Output[i];
        expect(val >= -128 && val <= 127, isTrue, reason: 'Value at index $i ($val) exceeds INT8 bounds');
      }
    });

    test('yuv420ToFloat32Hwc produces normalized [0.0, 1.0] outputs', () {
      final floatOutput = YuvConverter.yuv420ToFloat32Hwc(
        yPlane: yPlane,
        uPlane: uPlane,
        vPlane: vPlane,
        srcWidth: srcW,
        srcHeight: srcH,
        uvRowStride: srcW ~/ 2,
        uvPixelStride: 1,
        yRowStride: srcW,
        dstSize: dstSize,
        sensorOrientation: 90,
      );

      expect(floatOutput.length, equals(dstSize * dstSize * 3));

      for (int i = 0; i < floatOutput.length; i++) {
        final val = floatOutput[i];
        expect(val >= 0.0 && val <= 1.0, isTrue, reason: 'Float value at index $i ($val) exceeds [0, 1] range');
      }
    });

    test('Sensor orientations (0, 90, 180, 270) execute without buffer overflow or crash', () {
      for (final orientation in [0, 90, 180, 270]) {
        final out = YuvConverter.yuv420ToInt8(
          yPlane: yPlane,
          uPlane: uPlane,
          vPlane: vPlane,
          srcWidth: srcW,
          srcHeight: srcH,
          uvRowStride: srcW ~/ 2,
          uvPixelStride: 1,
          yRowStride: srcW,
          dstSize: dstSize,
          inputScale: 0.003921568859368563,
          inputZeroPoint: -128,
          sensorOrientation: orientation,
        );
        expect(out.length, equals(dstSize * dstSize * 3));
      }
    });
  });
}
