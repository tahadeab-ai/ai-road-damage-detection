import 'dart:typed_data';

/// High-performance zero-allocation YUV_420_888 to Quantized INT8 / Float32 conversion utility.
///
/// Implements 16-bit fixed-point bilinear interpolation, in-place camera sensor rotation
/// (0, 90, 180, 270 degrees), integer bit-shift color space conversion, and direct buffer
/// quantization. Eliminates intermediate bitmap / image object allocations.
class YuvConverter {
  /// Converts YUV420 planes directly to an [Int8List] buffer of shape [dstSize, dstSize, 3].
  ///
  /// Applies subpixel bilinear interpolation, in-place sensor rotation,
  /// integer YUV-to-RGB conversion, and clamps to [-128, 127] based on [inputScale] and [inputZeroPoint].
  static Int8List yuv420ToInt8({
    required Uint8List yPlane,
    required Uint8List uPlane,
    required Uint8List vPlane,
    required int srcWidth,
    required int srcHeight,
    required int uvRowStride,
    required int uvPixelStride,
    required int yRowStride,
    required int dstSize,
    required double inputScale,
    required int inputZeroPoint,
    int sensorOrientation = 90,
  }) {
    final out = Int8List(dstSize * dstSize * 3);
    int outIdx = 0;

    final double invScale255 = 1.0 / (255.0 * (inputScale > 0.0 ? inputScale : 1.0 / 255.0));

    final bool swapAxes = sensorOrientation == 90 || sensorOrientation == 270;
    final int portWidth = swapAxes ? srcHeight : srcWidth;
    final int portHeight = swapAxes ? srcWidth : srcHeight;

    for (int dy = 0; dy < dstSize; dy++) {
      final int portyFp = (dy * portHeight * 65536) ~/ dstSize;
      final int py0 = portyFp >> 16;
      final int py1 = (py0 + 1 < portHeight) ? py0 + 1 : py0;
      final int wy1 = portyFp & 0xFFFF;
      final int wy0 = 65536 - wy1;

      for (int dx = 0; dx < dstSize; dx++) {
        final int portxFp = (dx * portWidth * 65536) ~/ dstSize;
        final int px0 = portxFp >> 16;
        final int px1 = (px0 + 1 < portWidth) ? px0 + 1 : px0;
        final int wx1 = portxFp & 0xFFFF;
        final int wx0 = 65536 - wx1;

        int lx00, ly00, lx10, ly10, lx01, ly01, lx11, ly11;
        switch (sensorOrientation) {
          case 90:
            lx00 = py0;
            ly00 = srcHeight - 1 - px0;
            lx10 = py0;
            ly10 = srcHeight - 1 - px1;
            lx01 = py1;
            ly01 = srcHeight - 1 - px0;
            lx11 = py1;
            ly11 = srcHeight - 1 - px1;
            break;
          case 270:
            lx00 = srcWidth - 1 - py0;
            ly00 = px0;
            lx10 = srcWidth - 1 - py0;
            ly10 = px1;
            lx01 = srcWidth - 1 - py1;
            ly01 = px0;
            lx11 = srcWidth - 1 - py1;
            ly11 = px1;
            break;
          case 180:
            lx00 = srcWidth - 1 - px0;
            ly00 = srcHeight - 1 - py0;
            lx10 = srcWidth - 1 - px1;
            ly10 = srcHeight - 1 - py0;
            lx01 = srcWidth - 1 - px0;
            ly01 = srcHeight - 1 - py1;
            lx11 = srcWidth - 1 - px1;
            ly11 = srcHeight - 1 - py1;
            break;
          default:
            lx00 = px0;
            ly00 = py0;
            lx10 = px1;
            ly10 = py0;
            lx01 = px0;
            ly01 = py1;
            lx11 = px1;
            ly11 = py1;
        }

        lx00 = lx00.clamp(0, srcWidth - 1);
        lx10 = lx10.clamp(0, srcWidth - 1);
        lx01 = lx01.clamp(0, srcWidth - 1);
        lx11 = lx11.clamp(0, srcWidth - 1);
        ly00 = ly00.clamp(0, srcHeight - 1);
        ly10 = ly10.clamp(0, srcHeight - 1);
        ly01 = ly01.clamp(0, srcHeight - 1);
        ly11 = ly11.clamp(0, srcHeight - 1);

        final int y00 = yPlane[ly00 * yRowStride + lx00] & 0xFF;
        final int y10 = yPlane[ly10 * yRowStride + lx10] & 0xFF;
        final int y01 = yPlane[ly01 * yRowStride + lx01] & 0xFF;
        final int y11 = yPlane[ly11 * yRowStride + lx11] & 0xFF;
        final int yVal = (y00 * wy0 * wx0 +
                y10 * wy0 * wx1 +
                y01 * wy1 * wx0 +
                y11 * wy1 * wx1 +
                0x80000000) >>>
            32;

        final int uvR00 = (ly00 >> 1) * uvRowStride;
        final int uvC00 = (lx00 >> 1) * uvPixelStride;
        final int uvR10 = (ly10 >> 1) * uvRowStride;
        final int uvC10 = (lx10 >> 1) * uvPixelStride;
        final int uvR01 = (ly01 >> 1) * uvRowStride;
        final int uvC01 = (lx01 >> 1) * uvPixelStride;
        final int uvR11 = (ly11 >> 1) * uvRowStride;
        final int uvC11 = (lx11 >> 1) * uvPixelStride;

        final int u00 = uPlane[uvR00 + uvC00] & 0xFF;
        final int u10 = uPlane[uvR10 + uvC10] & 0xFF;
        final int u01 = uPlane[uvR01 + uvC01] & 0xFF;
        final int u11 = uPlane[uvR11 + uvC11] & 0xFF;
        final int uVal = (u00 * wy0 * wx0 +
                u10 * wy0 * wx1 +
                u01 * wy1 * wx0 +
                u11 * wy1 * wx1 +
                0x80000000) >>>
            32;

        final int v00 = vPlane[uvR00 + uvC00] & 0xFF;
        final int v10 = vPlane[uvR10 + uvC10] & 0xFF;
        final int v01 = vPlane[uvR01 + uvC01] & 0xFF;
        final int v11 = vPlane[uvR11 + uvC11] & 0xFF;
        final int vVal = (v00 * wy0 * wx0 +
                v10 * wy0 * wx1 +
                v01 * wy1 * wx0 +
                v11 * wy1 * wx1 +
                0x80000000) >>>
            32;

        final int yp = yVal;
        final int up = uVal - 128;
        final int vp = vVal - 128;

        int r = yp + ((1436 * vp) >> 10);
        int g = yp - ((352 * up) >> 10) - ((731 * vp) >> 10);
        int b = yp + ((1815 * up) >> 10);

        if (r < 0) {
          r = 0;
        } else if (r > 255) {
          r = 255;
        }
        if (g < 0) {
          g = 0;
        } else if (g > 255) {
          g = 255;
        }
        if (b < 0) {
          b = 0;
        } else if (b > 255) {
          b = 255;
        }

        out[outIdx++] = (r * invScale255 + inputZeroPoint).round().clamp(-128, 127);
        out[outIdx++] = (g * invScale255 + inputZeroPoint).round().clamp(-128, 127);
        out[outIdx++] = (b * invScale255 + inputZeroPoint).round().clamp(-128, 127);
      }
    }
    return out;
  }

  /// Converts YUV420 planes directly to a normalized [Float32List] buffer [0.0, 1.0]
  /// of shape [dstSize, dstSize, 3] (HWC).
  static Float32List yuv420ToFloat32Hwc({
    required Uint8List yPlane,
    required Uint8List uPlane,
    required Uint8List vPlane,
    required int srcWidth,
    required int srcHeight,
    required int uvRowStride,
    required int uvPixelStride,
    required int yRowStride,
    required int dstSize,
    int sensorOrientation = 90,
  }) {
    final out = Float32List(dstSize * dstSize * 3);
    int outIdx = 0;

    final bool swapAxes = sensorOrientation == 90 || sensorOrientation == 270;
    final int portWidth = swapAxes ? srcHeight : srcWidth;
    final int portHeight = swapAxes ? srcWidth : srcHeight;

    for (int dy = 0; dy < dstSize; dy++) {
      final int portyFp = (dy * portHeight * 65536) ~/ dstSize;
      final int py0 = portyFp >> 16;
      final int py1 = (py0 + 1 < portHeight) ? py0 + 1 : py0;
      final int wy1 = portyFp & 0xFFFF;
      final int wy0 = 65536 - wy1;

      for (int dx = 0; dx < dstSize; dx++) {
        final int portxFp = (dx * portWidth * 65536) ~/ dstSize;
        final int px0 = portxFp >> 16;
        final int px1 = (px0 + 1 < portWidth) ? px0 + 1 : px0;
        final int wx1 = portxFp & 0xFFFF;
        final int wx0 = 65536 - wx1;

        int lx00, ly00, lx10, ly10, lx01, ly01, lx11, ly11;
        switch (sensorOrientation) {
          case 90:
            lx00 = py0;
            ly00 = srcHeight - 1 - px0;
            lx10 = py0;
            ly10 = srcHeight - 1 - px1;
            lx01 = py1;
            ly01 = srcHeight - 1 - px0;
            lx11 = py1;
            ly11 = srcHeight - 1 - px1;
            break;
          case 270:
            lx00 = srcWidth - 1 - py0;
            ly00 = px0;
            lx10 = srcWidth - 1 - py0;
            ly10 = px1;
            lx01 = srcWidth - 1 - py1;
            ly01 = px0;
            lx11 = srcWidth - 1 - py1;
            ly11 = px1;
            break;
          case 180:
            lx00 = srcWidth - 1 - px0;
            ly00 = srcHeight - 1 - py0;
            lx10 = srcWidth - 1 - px1;
            ly10 = srcHeight - 1 - py0;
            lx01 = srcWidth - 1 - px0;
            ly01 = srcHeight - 1 - py1;
            lx11 = srcWidth - 1 - px1;
            ly11 = srcHeight - 1 - py1;
            break;
          default:
            lx00 = px0;
            ly00 = py0;
            lx10 = px1;
            ly10 = py0;
            lx01 = px0;
            ly01 = py1;
            lx11 = px1;
            ly11 = py1;
        }

        lx00 = lx00.clamp(0, srcWidth - 1);
        lx10 = lx10.clamp(0, srcWidth - 1);
        lx01 = lx01.clamp(0, srcWidth - 1);
        lx11 = lx11.clamp(0, srcWidth - 1);
        ly00 = ly00.clamp(0, srcHeight - 1);
        ly10 = ly10.clamp(0, srcHeight - 1);
        ly01 = ly01.clamp(0, srcHeight - 1);
        ly11 = ly11.clamp(0, srcHeight - 1);

        final int y00 = yPlane[ly00 * yRowStride + lx00] & 0xFF;
        final int y10 = yPlane[ly10 * yRowStride + lx10] & 0xFF;
        final int y01 = yPlane[ly01 * yRowStride + lx01] & 0xFF;
        final int y11 = yPlane[ly11 * yRowStride + lx11] & 0xFF;
        final int yVal = (y00 * wy0 * wx0 +
                y10 * wy0 * wx1 +
                y01 * wy1 * wx0 +
                y11 * wy1 * wx1 +
                0x80000000) >>>
            32;

        final int uvR00 = (ly00 >> 1) * uvRowStride;
        final int uvC00 = (lx00 >> 1) * uvPixelStride;
        final int uvR10 = (ly10 >> 1) * uvRowStride;
        final int uvC10 = (lx10 >> 1) * uvPixelStride;
        final int uvR01 = (ly01 >> 1) * uvRowStride;
        final int uvC01 = (lx01 >> 1) * uvPixelStride;
        final int uvR11 = (ly11 >> 1) * uvRowStride;
        final int uvC11 = (lx11 >> 1) * uvPixelStride;

        final int u00 = uPlane[uvR00 + uvC00] & 0xFF;
        final int u10 = uPlane[uvR10 + uvC10] & 0xFF;
        final int u01 = uPlane[uvR01 + uvC01] & 0xFF;
        final int u11 = uPlane[uvR11 + uvC11] & 0xFF;
        final int uVal = (u00 * wy0 * wx0 +
                u10 * wy0 * wx1 +
                u01 * wy1 * wx0 +
                u11 * wy1 * wx1 +
                0x80000000) >>>
            32;

        final int v00 = vPlane[uvR00 + uvC00] & 0xFF;
        final int v10 = vPlane[uvR10 + uvC10] & 0xFF;
        final int v01 = vPlane[uvR01 + uvC01] & 0xFF;
        final int v11 = vPlane[uvR11 + uvC11] & 0xFF;
        final int vVal = (v00 * wy0 * wx0 +
                v10 * wy0 * wx1 +
                v01 * wy1 * wx0 +
                v11 * wy1 * wx1 +
                0x80000000) >>>
            32;

        final int yp = yVal;
        final int up = uVal - 128;
        final int vp = vVal - 128;

        int r = yp + ((1436 * vp) >> 10);
        int g = yp - ((352 * up) >> 10) - ((731 * vp) >> 10);
        int b = yp + ((1815 * up) >> 10);

        if (r < 0) {
          r = 0;
        } else if (r > 255) {
          r = 255;
        }
        if (g < 0) {
          g = 0;
        } else if (g > 255) {
          g = 255;
        }
        if (b < 0) {
          b = 0;
        } else if (b > 255) {
          b = 255;
        }

        out[outIdx++] = r / 255.0;
        out[outIdx++] = g / 255.0;
        out[outIdx++] = b / 255.0;
      }
    }
    return out;
  }

  /// Converts YUV420 planes directly to a normalized [Float32List] buffer [0.0, 1.0]
  /// of shape [3, dstSize, dstSize] (CHW / Planar NCHW).
  static Float32List yuv420ToFloat32Chw({
    required Uint8List yPlane,
    required Uint8List uPlane,
    required Uint8List vPlane,
    required int srcWidth,
    required int srcHeight,
    required int uvRowStride,
    required int uvPixelStride,
    required int yRowStride,
    required int dstSize,
    int sensorOrientation = 90,
  }) {
    final int planeSize = dstSize * dstSize;
    final out = Float32List(planeSize * 3);
    int pixelIdx = 0;

    final bool swapAxes = sensorOrientation == 90 || sensorOrientation == 270;
    final int portWidth = swapAxes ? srcHeight : srcWidth;
    final int portHeight = swapAxes ? srcWidth : srcHeight;

    for (int dy = 0; dy < dstSize; dy++) {
      final int portyFp = (dy * portHeight * 65536) ~/ dstSize;
      final int py0 = portyFp >> 16;
      final int py1 = (py0 + 1 < portHeight) ? py0 + 1 : py0;
      final int wy1 = portyFp & 0xFFFF;
      final int wy0 = 65536 - wy1;

      for (int dx = 0; dx < dstSize; dx++) {
        final int portxFp = (dx * portWidth * 65536) ~/ dstSize;
        final int px0 = portxFp >> 16;
        final int px1 = (px0 + 1 < portWidth) ? px0 + 1 : px0;
        final int wx1 = portxFp & 0xFFFF;
        final int wx0 = 65536 - wx1;

        int lx00, ly00, lx10, ly10, lx01, ly01, lx11, ly11;
        switch (sensorOrientation) {
          case 90:
            lx00 = py0;
            ly00 = srcHeight - 1 - px0;
            lx10 = py0;
            ly10 = srcHeight - 1 - px1;
            lx01 = py1;
            ly01 = srcHeight - 1 - px0;
            lx11 = py1;
            ly11 = srcHeight - 1 - px1;
            break;
          case 270:
            lx00 = srcWidth - 1 - py0;
            ly00 = px0;
            lx10 = srcWidth - 1 - py0;
            ly10 = px1;
            lx01 = srcWidth - 1 - py1;
            ly01 = px0;
            lx11 = srcWidth - 1 - py1;
            ly11 = px1;
            break;
          case 180:
            lx00 = srcWidth - 1 - px0;
            ly00 = srcHeight - 1 - py0;
            lx10 = srcWidth - 1 - px1;
            ly10 = srcHeight - 1 - py0;
            lx01 = srcWidth - 1 - px0;
            ly01 = srcHeight - 1 - py1;
            lx11 = srcWidth - 1 - px1;
            ly11 = srcHeight - 1 - py1;
            break;
          default:
            lx00 = px0;
            ly00 = py0;
            lx10 = px1;
            ly10 = py0;
            lx01 = px0;
            ly01 = py1;
            lx11 = px1;
            ly11 = py1;
        }

        lx00 = lx00.clamp(0, srcWidth - 1);
        lx10 = lx10.clamp(0, srcWidth - 1);
        lx01 = lx01.clamp(0, srcWidth - 1);
        lx11 = lx11.clamp(0, srcWidth - 1);
        ly00 = ly00.clamp(0, srcHeight - 1);
        ly10 = ly10.clamp(0, srcHeight - 1);
        ly01 = ly01.clamp(0, srcHeight - 1);
        ly11 = ly11.clamp(0, srcHeight - 1);

        final int y00 = yPlane[ly00 * yRowStride + lx00] & 0xFF;
        final int y10 = yPlane[ly10 * yRowStride + lx10] & 0xFF;
        final int y01 = yPlane[ly01 * yRowStride + lx01] & 0xFF;
        final int y11 = yPlane[ly11 * yRowStride + lx11] & 0xFF;
        final int yVal = (y00 * wy0 * wx0 +
                y10 * wy0 * wx1 +
                y01 * wy1 * wx0 +
                y11 * wy1 * wx1 +
                0x80000000) >>>
            32;

        final int uvR00 = (ly00 >> 1) * uvRowStride;
        final int uvC00 = (lx00 >> 1) * uvPixelStride;
        final int uvR10 = (ly10 >> 1) * uvRowStride;
        final int uvC10 = (lx10 >> 1) * uvPixelStride;
        final int uvR01 = (ly01 >> 1) * uvRowStride;
        final int uvC01 = (lx01 >> 1) * uvPixelStride;
        final int uvR11 = (ly11 >> 1) * uvRowStride;
        final int uvC11 = (lx11 >> 1) * uvPixelStride;

        final int u00 = uPlane[uvR00 + uvC00] & 0xFF;
        final int u10 = uPlane[uvR10 + uvC10] & 0xFF;
        final int u01 = uPlane[uvR01 + uvC01] & 0xFF;
        final int u11 = uPlane[uvR11 + uvC11] & 0xFF;
        final int uVal = (u00 * wy0 * wx0 +
                u10 * wy0 * wx1 +
                u01 * wy1 * wx0 +
                u11 * wy1 * wx1 +
                0x80000000) >>>
            32;

        final int v00 = vPlane[uvR00 + uvC00] & 0xFF;
        final int v10 = vPlane[uvR10 + uvC10] & 0xFF;
        final int v01 = vPlane[uvR01 + uvC01] & 0xFF;
        final int v11 = vPlane[uvR11 + uvC11] & 0xFF;
        final int vVal = (v00 * wy0 * wx0 +
                v10 * wy0 * wx1 +
                v01 * wy1 * wx0 +
                v11 * wy1 * wx1 +
                0x80000000) >>>
            32;

        final int yp = yVal;
        final int up = uVal - 128;
        final int vp = vVal - 128;

        int r = yp + ((1436 * vp) >> 10);
        int g = yp - ((352 * up) >> 10) - ((731 * vp) >> 10);
        int b = yp + ((1815 * up) >> 10);

        if (r < 0) {
          r = 0;
        } else if (r > 255) {
          r = 255;
        }
        if (g < 0) {
          g = 0;
        } else if (g > 255) {
          g = 255;
        }
        if (b < 0) {
          b = 0;
        } else if (b > 255) {
          b = 255;
        }

        out[pixelIdx] = r / 255.0;
        out[planeSize + pixelIdx] = g / 255.0;
        out[planeSize * 2 + pixelIdx] = b / 255.0;
        pixelIdx++;
      }
    }
    return out;
  }
}
