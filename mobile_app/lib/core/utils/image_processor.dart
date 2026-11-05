import 'dart:typed_data';
import 'package:camera/camera.dart';

/// Preprocessing utilities for decoding camera frames into normalized model input tensors.
class ImageProcessor {
  static const int inputWidth = 640;
  static const int inputHeight = 640;
  static const int channels = 3;

  /// Converts a CameraImage (YUV420 or BGRA8888) into a normalized Float32List [1, 640, 640, 3].
  static Float32List cameraImageToFloat32Array(CameraImage image) {
    final Float32List float32Buffer = Float32List(inputWidth * inputHeight * channels);
    
    final int srcWidth = image.width;
    final int srcHeight = image.height;

    // Check if BGRA8888 (iOS)
    if (image.format.group == ImageFormatGroup.bgra8888) {
      final Plane plane = image.planes[0];
      final Uint8List bytes = plane.bytes;

      for (int y = 0; y < inputHeight; y++) {
        final int srcY = (y * srcHeight) ~/ inputHeight;
        final int rowOffset = srcY * plane.bytesPerRow;

        for (int x = 0; x < inputWidth; x++) {
          final int srcX = (x * srcWidth) ~/ inputWidth;
          final int pixelIndex = rowOffset + (srcX * 4);

          final int b = bytes[pixelIndex];
          final int g = bytes[pixelIndex + 1];
          final int r = bytes[pixelIndex + 2];

          final int destIndex = (y * inputWidth + x) * 3;
          float32Buffer[destIndex] = r / 255.0;
          float32Buffer[destIndex + 1] = g / 255.0;
          float32Buffer[destIndex + 2] = b / 255.0;
        }
      }
    } else {
      // Android YUV420 (semi-planar YUV_420_888 or NV21)
      final Plane yPlane = image.planes[0];
      final Plane uPlane = image.planes[1];
      final Plane vPlane = image.planes[2];

      final Uint8List yBytes = yPlane.bytes;
      final Uint8List uBytes = uPlane.bytes;
      final Uint8List vBytes = vPlane.bytes;

      final int yRowStride = yPlane.bytesPerRow;
      final int uvRowStride = uPlane.bytesPerRow;
      final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

      for (int y = 0; y < inputHeight; y++) {
        final int srcY = (y * srcHeight) ~/ inputHeight;
        final int uvY = srcY >> 1;

        for (int x = 0; x < inputWidth; x++) {
          final int srcX = (x * srcWidth) ~/ inputWidth;
          final int uvX = srcX >> 1;

          final int yIndex = srcY * yRowStride + srcX;
          final int uvIndex = uvY * uvRowStride + (uvX * uvPixelStride);

          final int yVal = yBytes[yIndex];
          final int uVal = uvIndex < uBytes.length ? uBytes[uvIndex] : 128;
          final int vVal = uvIndex < vBytes.length ? vBytes[uvIndex] : 128;

          // Standard YUV to RGB color space matrix conversion
          final int c = yVal - 16;
          final int d = uVal - 128;
          final int e = vVal - 128;

          final int r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255);
          final int g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
          final int b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255);

          final int destIndex = (y * inputWidth + x) * 3;
          float32Buffer[destIndex] = r / 255.0;
          float32Buffer[destIndex + 1] = g / 255.0;
          float32Buffer[destIndex + 2] = b / 255.0;
        }
      }
    }

    return float32Buffer;
  }
}
