import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/core/utils/image_processor.dart';

void main() {
  group('Orientation & Preprocessing Tests', () {
    test('Calculates exact Android camera rotation angles', () {
      // Android formula: angle = (360 - sensorOrientation + deviceOrientationAngle) % 360
      const int sensor = 90; // Standard back camera sensor orientation on Android

      expect(ImageProcessor.calculateOrientationAngle(sensor, 0), 270);   // portraitUp
      expect(ImageProcessor.calculateOrientationAngle(sensor, 90), 0);    // landscapeLeft
      expect(ImageProcessor.calculateOrientationAngle(sensor, 180), 90);  // portraitDown
      expect(ImageProcessor.calculateOrientationAngle(sensor, 270), 180); // landscapeRight
    });

    test('Decodes and rotates synthetic BGRA8888 frame into normalized float buffer', () {
      const int w = 1280;
      const int h = 720;
      final bytes = Uint8List(w * h * 4);

      // Fill with test gradient
      for (int i = 0; i < bytes.length; i += 4) {
        bytes[i] = 50;   // B
        bytes[i + 1] = 100; // G
        bytes[i + 2] = 200; // R
        bytes[i + 3] = 255; // A
      }

      final payload = CameraFramePayload(
        planeBytes: [bytes],
        bytesPerRow: [w * 4],
        bytesPerPixel: [4],
        width: w,
        height: h,
        formatGroup: ImageFormatGroup.bgra8888,
        sensorOrientation: 90,
        deviceOrientationAngle: 0,
      );

      final buffer = ImageProcessor.decodeAndNormalizeFrame(payload);

      expect(buffer.length, 640 * 640 * 3);
      // Verify RGB channels normalized to [0, 1]
      expect(buffer[0], closeTo(200 / 255.0, 0.01)); // R
      expect(buffer[1], closeTo(100 / 255.0, 0.01)); // G
      expect(buffer[2], closeTo(50 / 255.0, 0.01));  // B
    });

    test('Decodes Android YUV420 semi-planar frame into normalized buffer without NaN or Inf', () {
      const int w = 640;
      const int h = 480;
      final yPlane = Uint8List(w * h)..fillRange(0, w * h, 128);
      final uPlane = Uint8List((w ~/ 2) * (h ~/ 2))..fillRange(0, (w ~/ 2) * (h ~/ 2), 128);
      final vPlane = Uint8List((w ~/ 2) * (h ~/ 2))..fillRange(0, (w ~/ 2) * (h ~/ 2), 128);

      final payload = CameraFramePayload(
        planeBytes: [yPlane, uPlane, vPlane],
        bytesPerRow: [w, w ~/ 2, w ~/ 2],
        bytesPerPixel: [1, 1, 1],
        width: w,
        height: h,
        formatGroup: ImageFormatGroup.yuv420,
        sensorOrientation: 90,
        deviceOrientationAngle: 90, // landscapeLeft -> angle 0
      );

      final buffer = ImageProcessor.decodeAndNormalizeFrame(payload);

      expect(buffer.length, 640 * 640 * 3);
      for (int i = 0; i < 50; i++) {
        expect(buffer[i].isNaN, isFalse);
        expect(buffer[i].isInfinite, isFalse);
        expect(buffer[i], inInclusiveRange(0.0, 1.0));
      }
    });
  });
}
