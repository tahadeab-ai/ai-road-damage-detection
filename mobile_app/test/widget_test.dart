import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/core/constants/app_theme.dart';
import 'package:road_guard_mobile/core/constants/colors.dart';
import 'package:road_guard_mobile/features/detection/domain/models/detection_result.dart';
import 'package:road_guard_mobile/features/detection/presentation/bloc/detection_state.dart';
import 'package:road_guard_mobile/features/detection/presentation/widgets/bbox_painter.dart';
import 'package:road_guard_mobile/features/detection/presentation/widgets/camera_hud_overlay.dart';
import 'package:road_guard_mobile/features/telemetry/services/gps_service.dart';

void main() {
  group('Widget & CustomPainter Tests', () {
    testWidgets('CameraHudOverlay renders speedometer, latency, and controls without overflow', (tester) async {
      final state = DetectionState.initial().copyWith(
        isStreaming: true,
        inferenceLatencyMs: 14,
        fps: 22.5,
        gpsData: const GpsData(
          latitude: 37.7749,
          longitude: -122.4194,
          speedKmh: 58.0,
          address: 'Market St, San Francisco',
          isGpsLocked: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: CameraHudOverlay(
              state: state,
              onToggleStreaming: () {},
              onOpenHistory: () {},
              onOpenAnalytics: () {},
            ),
          ),
        ),
      );

      // Verify speedometer is rendered
      expect(
        find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('58 KM/H')),
        findsOneWidget,
      );

      // Verify inference latency HUD
      expect(find.text('14ms • 22.5 FPS'), findsOneWidget);

      // Verify AI action button
      expect(find.text('PAUSE AI'), findsOneWidget);
    });

    test('BBoxOverlayPainter calculates correct pixel mapping across aspect ratios', () {
      const detection = DetectionResult(
        classId: 3,
        className: 'Pothole',
        confidence: 0.85,
        normalizedRect: Rect.fromLTWH(0.25, 0.50, 0.50, 0.25),
      );

      final painter = BBoxOverlayPainter(detections: [detection]);
      expect(painter.detections.length, equals(1));

      // Test on 1080x1920 portrait screen
      const portraitSize = Size(1080, 1920);
      final pixelRect = detection.toPixelRect(portraitSize);

      expect(pixelRect.left, equals(270.0));
      expect(pixelRect.top, equals(960.0));
      expect(pixelRect.width, equals(540.0));
      expect(pixelRect.height, equals(480.0));

      // Test on 1920x1080 landscape screen
      const landscapeSize = Size(1920, 1080);
      final landscapeRect = detection.toPixelRect(landscapeSize);

      expect(landscapeRect.left, equals(480.0));
      expect(landscapeRect.top, equals(540.0));
      expect(landscapeRect.width, equals(960.0));
      expect(landscapeRect.height, equals(270.0));
    });

    test('AppColors returns correct neon accents per defect class', () {
      expect(AppColors.getColorForDefect(0), equals(AppColors.d00Longitudinal));
      expect(AppColors.getColorForDefect(1), equals(AppColors.d10Transverse));
      expect(AppColors.getColorForDefect(2), equals(AppColors.d20Alligator));
      expect(AppColors.getColorForDefect(3), equals(AppColors.d40Pothole));
    });
  });
}
