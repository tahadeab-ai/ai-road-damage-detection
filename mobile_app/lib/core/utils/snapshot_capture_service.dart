import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../../features/detection/domain/models/detection_result.dart';

/// Captures live camera buffer snapshots with rasterized bounding box evidence.
class SnapshotCaptureService {
  static const int imageWidth = 640;
  static const int imageHeight = 640;

  /// Asynchronously creates, annotates, and saves a JPEG evidence snapshot.
  static Future<String?> captureHazardSnapshot({
    required Float32List rgbBuffer,
    required DetectionResult detection,
  }) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final hazardsDir = Directory('${appDir.path}/hazards');
      if (!await hazardsDir.exists()) {
        await hazardsDir.create(recursive: true);
      }

      final fileName = 'hazard_${DateTime.now().millisecondsSinceEpoch}_${detection.classId}.jpg';
      final filePath = '${hazardsDir.path}/$fileName';

      // Clone float buffer data for isolate safety
      final bufferCopy = Float32List.fromList(rgbBuffer);
      final normRect = detection.normalizedRect;

      final savedPath = await compute(_renderAndEncodeSnapshot, {
        'buffer': bufferCopy,
        'left': normRect.left,
        'top': normRect.top,
        'right': normRect.right,
        'bottom': normRect.bottom,
        'classId': detection.classId,
        'outputPath': filePath,
      });

      return savedPath;
    } catch (e) {
      debugPrint('[SnapshotCaptureService] Snapshot notice: $e');
      return null;
    }
  }

  /// Background isolate function to build image, draw bounding box, and encode JPEG.
  static String? _renderAndEncodeSnapshot(Map<String, dynamic> params) {
    try {
      final Float32List buffer = params['buffer'] as Float32List;
      final double left = params['left'] as double;
      final double top = params['top'] as double;
      final double right = params['right'] as double;
      final double bottom = params['bottom'] as double;
      final int classId = params['classId'] as int;
      final String outputPath = params['outputPath'] as String;

      final image = img.Image(width: imageWidth, height: imageHeight);

      // Populate pixels from normalized Float32 RGB buffer
      for (int y = 0; y < imageHeight; y++) {
        for (int x = 0; x < imageWidth; x++) {
          final int idx = (y * imageWidth + x) * 3;
          final int r = (buffer[idx] * 255.0).clamp(0.0, 255.0).toInt();
          final int g = (buffer[idx + 1] * 255.0).clamp(0.0, 255.0).toInt();
          final int b = (buffer[idx + 2] * 255.0).clamp(0.0, 255.0).toInt();
          image.setPixelRgb(x, y, r, g, b);
        }
      }

      // Determine bounding box color
      // 0: Cyan, 1: Orange, 2: Amber, 3: Red
      img.ColorRgba8 boxColor;
      switch (classId) {
        case 0:
          boxColor = img.ColorRgba8(0, 242, 254, 255); // Cyan
          break;
        case 1:
          boxColor = img.ColorRgba8(249, 115, 22, 255); // Orange
          break;
        case 2:
          boxColor = img.ColorRgba8(245, 158, 11, 255); // Amber
          break;
        case 3:
          boxColor = img.ColorRgba8(239, 68, 68, 255); // Red Pothole
          break;
        default:
          boxColor = img.ColorRgba8(255, 255, 255, 255);
      }

      final int x1 = (left * imageWidth).clamp(0.0, (imageWidth - 1).toDouble()).toInt();
      final int y1 = (top * imageHeight).clamp(0.0, (imageHeight - 1).toDouble()).toInt();
      final int x2 = (right * imageWidth).clamp(0.0, (imageWidth - 1).toDouble()).toInt();
      final int y2 = (bottom * imageHeight).clamp(0.0, (imageHeight - 1).toDouble()).toInt();

      // Render prominent bounding box on raster image
      img.drawRect(
        image,
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        color: boxColor,
        thickness: 4,
      );

      // Encode as JPEG with 85% quality
      final jpegBytes = img.encodeJpg(image, quality: 85);
      File(outputPath).writeAsBytesSync(jpegBytes);
      return outputPath;
    } catch (_) {
      return null;
    }
  }
}
