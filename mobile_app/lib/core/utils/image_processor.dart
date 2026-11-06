import 'dart:typed_data';
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
/// correct affine rotation, and offloads YUV420 decoding to background Dart Isolates.
class ImageProcessor {
  static const int inputWidth = 640;
  static const int inputHeight = 640;
  static const int channels = 3;
  static const double normScale = 1.0 / 255.0; // Cached normalization constant

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
  static Float32List decodeAndNormalizeFrame(CameraFramePayload payload) {
    final Float32List float32Buffer = Float32List(inputWidth * inputHeight * channels);
    final int srcWidth = payload.width;
    final int srcHeight = payload.height;

    // Determine target rotation angle
    final int angle = calculateOrientationAngle(
      payload.sensorOrientation,
      payload.deviceOrientationAngle,
    );

    // 1. Process iOS BGRA8888
    if (payload.formatGroup == ImageFormatGroup.bgra8888) {
      final Uint8List bytes = payload.planeBytes[0];
      final int bytesPerRow = payload.bytesPerRow[0];

      for (int y = 0; y < inputHeight; y++) {
        for (int x = 0; x < inputWidth; x++) {
          final (srcX, srcY) = _mapCoordinates(x, y, srcWidth, srcHeight, angle);
          final int pixelIndex = srcY * bytesPerRow + (srcX * 4);

          final int b = bytes[pixelIndex];
          final int g = bytes[pixelIndex + 1];
          final int r = bytes[pixelIndex + 2];

          final int destIndex = (y * inputWidth + x) * channels;
          float32Buffer[destIndex] = r * normScale;
          float32Buffer[destIndex + 1] = g * normScale;
          float32Buffer[destIndex + 2] = b * normScale;
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

      for (int y = 0; y < inputHeight; y++) {
        for (int x = 0; x < inputWidth; x++) {
          final (srcX, srcY) = _mapCoordinates(x, y, srcWidth, srcHeight, angle);
          final int uvX = srcX >> 1;
          final int uvY = srcY >> 1;

          final int yIndex = srcY * yRowStride + srcX;
          final int uvIndex = uvY * uvRowStride + (uvX * uvPixelStride);

          final int yVal = yBytes[yIndex];
          final int uVal = uvIndex < uBytes.length ? uBytes[uvIndex] : 128;
          final int vVal = uvIndex < vBytes.length ? vBytes[uvIndex] : 128;

          // Standard YUV to RGB color-space integer matrix conversion
          final int c = yVal - 16;
          final int d = uVal - 128;
          final int e = vVal - 128;

          final int r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255);
          final int g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
          final int b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255);

          final int destIndex = (y * inputWidth + x) * channels;
          float32Buffer[destIndex] = r * normScale;
          float32Buffer[destIndex + 1] = g * normScale;
          float32Buffer[destIndex + 2] = b * normScale;
        }
      }
    }

    return float32Buffer;
  }

  /// Maps target normalized output coordinates (x, y) to source sensor coordinates based on rotation angle.
  static (int, int) _mapCoordinates(
    int outX,
    int outY,
    int srcWidth,
    int srcHeight,
    int angle,
  ) {
    int srcX;
    int srcY;

    switch (angle) {
      case 90:
        // Rotate 90 degrees clockwise
        srcX = (outY * (srcWidth - 1)) ~/ (inputHeight - 1);
        srcY = ((inputWidth - 1 - outX) * (srcHeight - 1)) ~/ (inputWidth - 1);
        break;
      case 180:
        // Rotate 180 degrees
        srcX = ((inputWidth - 1 - outX) * (srcWidth - 1)) ~/ (inputWidth - 1);
        srcY = ((inputHeight - 1 - outY) * (srcHeight - 1)) ~/ (inputHeight - 1);
        break;
      case 270:
        // Rotate 270 degrees clockwise (90 degrees counter-clockwise)
        srcX = ((inputHeight - 1 - outY) * (srcWidth - 1)) ~/ (inputHeight - 1);
        srcY = (outX * (srcHeight - 1)) ~/ (inputWidth - 1);
        break;
      case 0:
      default:
        // Unrotated orientation
        srcX = (outX * (srcWidth - 1)) ~/ (inputWidth - 1);
        srcY = (outY * (srcHeight - 1)) ~/ (inputHeight - 1);
        break;
    }

    return (srcX.clamp(0, srcWidth - 1), srcY.clamp(0, srcHeight - 1));
  }
}
