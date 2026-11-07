import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/features/detection/presentation/widgets/bbox_painter.dart';

void main() {
  group('Camera Geometry & Letterbox Un-Mapping Tests', () {
    test('Maps normalized coordinates directly when no camera aspect ratio is provided', () {
      const normRect = Rect.fromLTRB(0.25, 0.40, 0.75, 0.80);
      const screenSize = Size(1000.0, 2000.0);

      final mapped = BBoxOverlayPainter.mapNormalizedRect(normRect, screenSize);

      expect(mapped.left, 250.0);
      expect(mapped.top, 800.0);
      expect(mapped.right, 750.0);
      expect(mapped.bottom, 1600.0);
    });

    test('Portrait viewport (9:19.5 taller than 9:16 camera) crops sides equally in BoxFit.cover', () {
      // Screen: 1080 x 2340 (aspect ratio ~0.4615)
      // Camera stream: 9:16 (aspect ratio 0.5625)
      // Since screenAspect < cameraAspect, height fits exactly (2340), renderW = 2340 * 0.5625 = 1316.25
      // Crop on left/right: offsetX = (1316.25 - 1080) / 2 = 118.125
      const normRect = Rect.fromLTRB(0.5, 0.5, 0.5, 0.5); // Center point
      const screenSize = Size(1080.0, 2340.0);
      const cameraAspect = 9.0 / 16.0;

      final mapped = BBoxOverlayPainter.mapNormalizedRect(
        normRect,
        screenSize,
        cameraAspectRatio: cameraAspect,
        fit: BoxFit.cover,
      );

      // Center point in camera (0.5, 0.5) must remain centered on screen (540, 1170)
      expect(mapped.center.dx, closeTo(540.0, 1e-3));
      expect(mapped.center.dy, closeTo(1170.0, 1e-3));
    });

    test('Landscape viewport (19.5:9 wider than 16:9 camera) crops top/bottom in BoxFit.cover', () {
      // Screen: 2340 x 1080 (aspect ratio ~2.166)
      // Camera stream: 16:9 (aspect ratio ~1.777)
      // screenAspect > cameraAspect -> width fits (2340), renderH = 2340 / (16/9) = 1316.25
      // Crop on top/bottom: offsetY = (1316.25 - 1080) / 2 = 118.125
      const normRect = Rect.fromLTRB(0.5, 0.5, 0.5, 0.5); // Center point
      const screenSize = Size(2340.0, 1080.0);
      const cameraAspect = 16.0 / 9.0;

      final mapped = BBoxOverlayPainter.mapNormalizedRect(
        normRect,
        screenSize,
        cameraAspectRatio: cameraAspect,
        fit: BoxFit.cover,
      );

      // Center point (0.5, 0.5) must map exactly to viewport center (1170, 540)
      expect(mapped.center.dx, closeTo(1170.0, 1e-3));
      expect(mapped.center.dy, closeTo(540.0, 1e-3));
    });

    test('Contain mode adds letterbox / pillarbox bars without coordinate distortion', () {
      // Screen: 1000 x 2000 (aspect 0.5)
      // Camera: 1000 x 1000 (aspect 1.0)
      // Taller screen -> renderH = 1000 / 1.0 = 1000, offsetY = (2000 - 1000) / 2 = 500
      const normRect = Rect.fromLTRB(0.0, 0.0, 1.0, 1.0);
      const screenSize = Size(1000.0, 2000.0);
      const cameraAspect = 1.0;

      final mapped = BBoxOverlayPainter.mapNormalizedRect(
        normRect,
        screenSize,
        cameraAspectRatio: cameraAspect,
        fit: BoxFit.contain,
      );

      expect(mapped.left, 0.0);
      expect(mapped.right, 1000.0);
      expect(mapped.top, 500.0);
      expect(mapped.bottom, 1500.0);
    });
  });
}
