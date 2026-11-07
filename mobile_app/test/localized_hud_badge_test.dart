import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/core/localization/app_localizations.dart';
import 'package:road_guard_mobile/core/utils/temporal_filter.dart';
import 'package:road_guard_mobile/features/detection/presentation/widgets/bbox_painter.dart';

void main() {
  group('Localized Automotive HUD Badge Tests', () {
    setUp(() {
      AppStrings.currentLanguage = AppLanguage.arabic;
    });

    tearDown(() {
      AppStrings.currentLanguage = AppLanguage.arabic;
    });

    test('Arabic mode generates correct localized defect labels and RTL direction', () {
      AppStrings.currentLanguage = AppLanguage.arabic;

      expect(AppStrings.isArabic, isTrue);
      expect(AppStrings.direction, equals(TextDirection.rtl));

      expect(AppStrings.getDefectName(0), equals('تشقق طولي'));
      expect(AppStrings.getDefectName(1), equals('تشقق عرضي'));
      expect(AppStrings.getDefectName(2), equals('تشقق شبكي'));
      expect(AppStrings.getDefectName(3), equals('حفرة'));

      expect(AppStrings.getDefectBadge(3, 0.94), equals('حفرة 94%'));
    });

    test('English mode generates correct localized defect labels and LTR direction', () {
      AppStrings.currentLanguage = AppLanguage.english;

      expect(AppStrings.isArabic, isFalse);
      expect(AppStrings.direction, equals(TextDirection.ltr));

      expect(AppStrings.getDefectName(0), equals('Longitudinal Crack'));
      expect(AppStrings.getDefectName(1), equals('Transverse Crack'));
      expect(AppStrings.getDefectName(2), equals('Alligator Crack'));
      expect(AppStrings.getDefectName(3), equals('Pothole'));

      expect(AppStrings.getDefectBadge(3, 0.94), equals('Pothole 94%'));
    });

    test('Tracked hazard formats localized automotive badge string correctly', () {
      final track = TrackedDetection(
        trackingId: 42,
        classId: 3,
        className: 'Pothole',
        confidence: 0.94,
        smoothedRect: const Rect.fromLTWH(0.2, 0.4, 0.3, 0.2),
        associationCount: 5,
        lifecycle: TrackingLifecycle.confirmed,
      );

      // Verify Track ID formatting
      expect(track.formattedTrackId, equals('#042'));

      // In Arabic mode
      AppStrings.currentLanguage = AppLanguage.arabic;
      final arabicLabel = '${track.formattedTrackId} ${AppStrings.getDefectName(track.classId)} ${(track.confidence * 100).round()}%';
      expect(arabicLabel, equals('#042 حفرة 94%'));

      // In English mode
      AppStrings.currentLanguage = AppLanguage.english;
      final englishLabel = '${track.formattedTrackId} ${AppStrings.getDefectName(track.classId)} ${(track.confidence * 100).round()}%';
      expect(englishLabel, equals('#042 Pothole 94%'));
    });

    test('BBoxOverlayPainter renders without error with confirmed localized tracks', () {
      final track = TrackedDetection(
        trackingId: 15,
        classId: 0,
        className: 'Longitudinal Crack',
        confidence: 0.88,
        smoothedRect: const Rect.fromLTWH(0.1, 0.2, 0.4, 0.3),
        associationCount: 4,
        lifecycle: TrackingLifecycle.confirmed,
      );

      final painter = BBoxOverlayPainter(
        trackedDetections: [track],
        cameraAspectRatio: 9.0 / 16.0,
        isRoadDetected: true,
        showDebugInfo: true,
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const size = Size(1080, 1920);

      // Verify painting runs smoothly without throwing
      expect(() => painter.paint(canvas, size), returnsNormally);
      final picture = recorder.endRecording();
      picture.dispose();
    });
  });
}
