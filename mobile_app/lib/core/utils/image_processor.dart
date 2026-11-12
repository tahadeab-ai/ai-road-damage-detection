import 'dart:typed_data';
import 'package:camera/camera.dart';

/// Preprocessing utilities for decoding camera frames into normalized model input tensors.
class ImageProcessor {
  static const int inputWidth = 640;
  static const int inputHeight = 640;
  static const int channels = 3;

  /// Converts a CameraImage (YUV420 or BGRA8888) into a normalized Float32List [1, 640, 640, 3].
  /// Fully hardened against Samsung semi-planar UV buffer bounds and single/multi-plane quirks.
  static Float32List cameraImageToFloat32Array(CameraImage image) {
    final Float32List float32Buffer = Float32List(inputWidth * inputHeight * channels);
    
    final int srcWidth = image.width;
    final int srcHeight = image.height;
    if (srcWidth <= 0 || srcHeight <= 0 || image.planes.isEmpty) {
      return float32Buffer;
    }

    try {
      // 1. Check if BGRA8888 (iOS)
      if (image.format.group == ImageFormatGroup.bgra8888) {
        final Plane plane = image.planes[0];
        final Uint8List bytes = plane.bytes;
        final int bytesLen = bytes.length;
        final int bytesPerRow = plane.bytesPerRow;

        for (int y = 0; y < inputHeight; y++) {
          final int srcY = (y * srcHeight) ~/ inputHeight;
          final int rowOffset = srcY * bytesPerRow;

          for (int x = 0; x < inputWidth; x++) {
            final int srcX = (x * srcWidth) ~/ inputWidth;
            final int pixelIndex = rowOffset + (srcX * 4);

            if (pixelIndex + 2 < bytesLen) {
              final int b = bytes[pixelIndex];
              final int g = bytes[pixelIndex + 1];
              final int r = bytes[pixelIndex + 2];

              final int destIndex = (y * inputWidth + x) * 3;
              float32Buffer[destIndex] = r / 255.0;
              float32Buffer[destIndex + 1] = g / 255.0;
              float32Buffer[destIndex + 2] = b / 255.0;
            }
          }
        }
        return float32Buffer;
      }

      // 2. Android YUV420 (semi-planar YUV_420_888, NV21, or multi-planar)
      final Plane yPlane = image.planes[0];
      final Uint8List yBytes = yPlane.bytes;
      final int yLen = yBytes.length;
      final int yRowStride = yPlane.bytesPerRow;

      if (yLen == 0) return float32Buffer;

      // Handle 3-plane YUV_420_888 (Standard Android)
      if (image.planes.length >= 3) {
        final Plane uPlane = image.planes[1];
        final Plane vPlane = image.planes[2];

        final Uint8List uBytes = uPlane.bytes;
        final Uint8List vBytes = vPlane.bytes;
        final int uLen = uBytes.length;
        final int vLen = vBytes.length;

        final int uvRowStride = uPlane.bytesPerRow;
        final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

        for (int y = 0; y < inputHeight; y++) {
          final int srcY = (y * srcHeight) ~/ inputHeight;
          final int uvY = srcY >> 1;

          for (int x = 0; x < inputWidth; x++) {
            final int srcX = (x * srcWidth) ~/ inputWidth;
            final int uvX = srcX >> 1;

            final int yIndex = (srcY * yRowStride + srcX).clamp(0, yLen - 1);
            final int uvIndex = uvY * uvRowStride + (uvX * uvPixelStride);

            final int safeUIndex = uvIndex.clamp(0, uLen - 1);
            final int safeVIndex = uvIndex.clamp(0, vLen - 1);

            final int yVal = yBytes[yIndex];
            final int uVal = (uLen > 0 && uvIndex < uLen && uvIndex >= 0) ? uBytes[safeUIndex] : 128;
            final int vVal = (vLen > 0 && uvIndex < vLen && uvIndex >= 0) ? vBytes[safeVIndex] : 128;

            // ITU-R BT.601 color conversion
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
      } else if (image.planes.length == 2) {
        // Semi-planar NV12 / NV21 (Y in plane 0, interleaved UV in plane 1)
        final Plane uvPlane = image.planes[1];
        final Uint8List uvBytes = uvPlane.bytes;
        final int uvLen = uvBytes.length;
        final int uvRowStride = uvPlane.bytesPerRow;

        for (int y = 0; y < inputHeight; y++) {
          final int srcY = (y * srcHeight) ~/ inputHeight;
          final int uvY = srcY >> 1;

          for (int x = 0; x < inputWidth; x++) {
            final int srcX = (x * srcWidth) ~/ inputWidth;
            final int uvX = srcX >> 1;

            final int yIndex = (srcY * yRowStride + srcX).clamp(0, yLen - 1);
            final int uvIndex = (uvY * uvRowStride + uvX * 2).clamp(0, uvLen > 1 ? uvLen - 2 : 0);

            final int yVal = yBytes[yIndex];
            final int uVal = uvLen > 1 ? uvBytes[uvIndex] : 128;
            final int vVal = uvLen > 1 ? uvBytes[uvIndex + 1] : 128;

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
      } else {
        // Single plane NV21 fallback
        final int uvStart = srcWidth * srcHeight;
        for (int y = 0; y < inputHeight; y++) {
          final int srcY = (y * srcHeight) ~/ inputHeight;
          final int uvY = srcY >> 1;

          for (int x = 0; x < inputWidth; x++) {
            final int srcX = (x * srcWidth) ~/ inputWidth;
            final int uvX = srcX >> 1;

            final int yIndex = (srcY * yRowStride + srcX).clamp(0, yLen - 1);
            final int uvIndex = (uvStart + uvY * srcWidth + (uvX & ~1)).clamp(0, yLen > 1 ? yLen - 2 : 0);

            final int yVal = yBytes[yIndex];
            final int vVal = yLen > 1 ? yBytes[uvIndex] : 128;
            final int uVal = yLen > 1 ? yBytes[uvIndex + 1] : 128;

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
    } catch (_) {
      // Fallback: return zeroed buffer rather than throwing RangeError
    }

    return float32Buffer;
  }
}
