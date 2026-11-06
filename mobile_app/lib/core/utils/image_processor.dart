import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Serializable payload for decoding raw camera frames across Dart Isolates.
class CameraFramePayload {
  final List<Uint8List> planeBytes;
  final List<int> bytesPerRow;
  final List<int?> bytesPerPixel;
  final int width;
  final int height;
  final ImageFormatGroup formatGroup;
  final int sensorOrientation;
  final int deviceOrientationAngle;

  const CameraFramePayload({
    required this.planeBytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
    required this.width,
    required this.height,
    required this.formatGroup,
    required this.sensorOrientation,
    required this.deviceOrientationAngle,
  });

  factory CameraFramePayload.fromCameraImage(
    CameraImage image, {
    int sensorOrientation = 90,
    int deviceOrientationAngle = 0,
  }) {
    return CameraFramePayload(
      planeBytes: image.planes.map((p) => p.bytes).toList(),
      bytesPerRow: image.planes.map((p) => p.bytesPerRow).toList(),
      bytesPerPixel: image.planes.map((p) => p.bytesPerPixel).toList(),
      width: image.width,
      height: image.height,
      formatGroup: image.format.group,
      sensorOrientation: sensorOrientation,
      deviceOrientationAngle: deviceOrientationAngle,
    );
  }
}

/// High-performance orientation-aware preprocessing utilities for Edge AI inference.
/// Respects Android camera sensor orientation and device orientation, applies
/// vectorized lookup table rotation, and offloads YUV420 decoding to background Dart Isolates.
class ImageProcessor {
  static const int inputWidth = 640;
  static const int inputHeight = 640;
  static const int channels = 3;
  static const double normScale = 1.0 / 255.0; // Pre-calculated normalization constant

  /// Computes the exact rotation angle using the official Android camera sensor formula:
  /// angle = (360 - sensorOrientation + deviceOrientationAngle) % 360
  static int calculateOrientationAngle(int sensorOrientation, int deviceOrientationAngle) {
    return (360 - sensorOrientation + deviceOrientationAngle) % 360;
  }

  /// Offloads frame preprocessing to a background Dart Isolate to eliminate main thread UI stutter.
  static Future<Float32List> preprocessInIsolate(
    CameraImage image, {
    int sensorOrientation = 90,
    int deviceOrientationAngle = 0,
  }) async {
    final payload = CameraFramePayload.fromCameraImage(
      image,
      sensorOrientation: sensorOrientation,
      deviceOrientationAngle: deviceOrientationAngle,
    );
    return compute(decodeAndNormalizeFrame, payload);
  }

  /// Synchronous fallback or direct invocation method.
  static Float32List cameraImageToFloat32Array(
    CameraImage image, {
    int sensorOrientation = 90,
    int deviceOrientationAngle = 0,
  }) {
    final payload = CameraFramePayload.fromCameraImage(
      image,
      sensorOrientation: sensorOrientation,
      deviceOrientationAngle: deviceOrientationAngle,
    );
    return decodeAndNormalizeFrame(payload);
  }

  /// Top-level or static function executable inside a separate Dart Isolate via [compute].
  /// Utilizes precomputed 1D coordinate lookup tables to eliminate 400k+ inner loop divisions.
  static Float32List decodeAndNormalizeFrame(CameraFramePayload payload) {
    final Float32List float32Buffer = Float32List(inputWidth * inputHeight * channels);
    final int srcWidth = payload.width;
    final int srcHeight = payload.height;

    // Determine target rotation angle
    final int angle = calculateOrientationAngle(
      payload.sensorOrientation,
      payload.deviceOrientationAngle,
    );

    // Precompute 1D coordinate mapping arrays to ensure sub-20ms execution
    final Int32List lutCols = Int32List(inputWidth);
    final Int32List lutRows = Int32List(inputHeight);

    final int maxSrcX = srcWidth - 1;
    final int maxSrcY = srcHeight - 1;

    switch (angle) {
      case 90:
        // outX maps to srcY inverted, outY maps to srcX
        for (int i = 0; i < inputWidth; i++) {
          lutCols[i] = ((inputWidth - 1 - i) * maxSrcY) ~/ (inputWidth - 1);
        }
        for (int i = 0; i < inputHeight; i++) {
          lutRows[i] = (i * maxSrcX) ~/ (inputHeight - 1);
        }
        break;
      case 180:
        // outX maps to srcX inverted, outY maps to srcY inverted
        for (int i = 0; i < inputWidth; i++) {
          lutCols[i] = ((inputWidth - 1 - i) * maxSrcX) ~/ (inputWidth - 1);
        }
        for (int i = 0; i < inputHeight; i++) {
          lutRows[i] = ((inputHeight - 1 - i) * maxSrcY) ~/ (inputHeight - 1);
        }
        break;
      case 270:
        // outX maps to srcY, outY maps to srcX inverted
        for (int i = 0; i < inputWidth; i++) {
          lutCols[i] = (i * maxSrcY) ~/ (inputWidth - 1);
        }
        for (int i = 0; i < inputHeight; i++) {
          lutRows[i] = ((inputHeight - 1 - i) * maxSrcX) ~/ (inputHeight - 1);
        }
        break;
      case 0:
      default:
        // Standard unrotated mapping
        for (int i = 0; i < inputWidth; i++) {
          lutCols[i] = (i * maxSrcX) ~/ (inputWidth - 1);
        }
        for (int i = 0; i < inputHeight; i++) {
          lutRows[i] = (i * maxSrcY) ~/ (inputHeight - 1);
        }
        break;
    }

    // 1. Process iOS BGRA8888
    if (payload.formatGroup == ImageFormatGroup.bgra8888) {
      final Uint8List bytes = payload.planeBytes[0];
      final int bytesPerRow = payload.bytesPerRow[0];

      int destIndex = 0;
      for (int y = 0; y < inputHeight; y++) {
        final int baseSrc = lutRows[y];
        for (int x = 0; x < inputWidth; x++) {
          int srcX, srcY;
          if (angle == 90 || angle == 270) {
            srcX = baseSrc;
            srcY = lutCols[x];
          } else {
            srcX = lutCols[x];
            srcY = baseSrc;
          }

          final int pixelIndex = srcY * bytesPerRow + (srcX * 4);
          final int b = bytes[pixelIndex];
          final int g = bytes[pixelIndex + 1];
          final int r = bytes[pixelIndex + 2];

          float32Buffer[destIndex++] = r * normScale;
          float32Buffer[destIndex++] = g * normScale;
          float32Buffer[destIndex++] = b * normScale;
        }
      }
    } else {
      // 2. Process Android YUV420 (semi-planar YUV_420_888 / NV21)
      final Uint8List yBytes = payload.planeBytes[0];
      final Uint8List uBytes = payload.planeBytes[1];
      final Uint8List vBytes = payload.planeBytes[2];

      final int yRowStride = payload.bytesPerRow[0];
      final int uvRowStride = payload.bytesPerRow[1];
      final int uvPixelStride = payload.bytesPerPixel[1] ?? 1;

      int destIndex = 0;
      for (int y = 0; y < inputHeight; y++) {
        final int baseSrc = lutRows[y];
        for (int x = 0; x < inputWidth; x++) {
          int srcX, srcY;
          if (angle == 90 || angle == 270) {
            srcX = baseSrc;
            srcY = lutCols[x];
          } else {
            srcX = lutCols[x];
            srcY = baseSrc;
          }

          final int uvX = srcX >> 1;
          final int uvY = srcY >> 1;

          final int yIndex = srcY * yRowStride + srcX;
          final int uvIndex = uvY * uvRowStride + (uvX * uvPixelStride);

          final int yVal = yBytes[yIndex];
          final int uVal = uvIndex < uBytes.length ? uBytes[uvIndex] : 128;
          final int vVal = uvIndex < vBytes.length ? vBytes[uvIndex] : 128;

          // Optimized integer YUV to RGB color conversion
          final int c = yVal - 16;
          final int d = uVal - 128;
          final int e = vVal - 128;

          final int r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255);
          final int g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
          final int b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255);

          float32Buffer[destIndex++] = r * normScale;
          float32Buffer[destIndex++] = g * normScale;
          float32Buffer[destIndex++] = b * normScale;
        }
      }
    }

    return float32Buffer;
  }
}
