import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/core/localization/app_localizations.dart';
import 'package:road_guard_mobile/features/detection/data/datasources/tflite_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLanguageNotifier & Localization Tests', () {
    test('Language switches cleanly between Arabic (RTL) and English (LTR)', () {
      final notifier = AppLanguageNotifier.instance;

      // Ensure starts with Arabic
      notifier.setLanguage(AppLanguage.arabic);
      expect(AppStrings.isArabic, isTrue);
      expect(AppStrings.direction, equals(TextDirection.rtl));
      expect(AppStrings.languageToggleLabel, equals('EN'));
      expect(AppStrings.speedUnit, equals('كم/س'));
      expect(AppStrings.getDefectName(3), equals('حفرة'));
      expect(AppStrings.getDefectBadge(3, 0.88), equals('حفرة 88%'));

      // Toggle to English
      notifier.toggleLanguage();
      expect(AppStrings.isArabic, isFalse);
      expect(AppStrings.direction, equals(TextDirection.ltr));
      expect(AppStrings.languageToggleLabel, equals('عربي'));
      expect(AppStrings.speedUnit, equals('KM/H'));
      expect(AppStrings.getDefectName(3), equals('Pothole'));
      expect(AppStrings.getDefectBadge(3, 0.88), equals('Pothole 88%'));

      // Toggle back to Arabic
      notifier.toggleLanguage();
      expect(AppStrings.isArabic, isTrue);
      expect(AppStrings.direction, equals(TextDirection.rtl));
    });
  });

  group('Road Surface Binary Gate Tests', () {
    late TfliteEngine engine;

    setUp(() {
      engine = TfliteEngine();
    });

    test('Identifies neutral grey asphalt as valid road surface', () async {
      // 640x640x3 Float32 buffer of neutral asphalt grey (R=0.35, G=0.35, B=0.35)
      final roadBuffer = Float32List(640 * 640 * 3);
      for (int i = 0; i < roadBuffer.length; i++) {
        roadBuffer[i] = 0.35;
      }

      final isRoad = await engine.checkRoadSurface(roadBuffer);
      expect(isRoad, isTrue);
    });

    test('Identifies high-saturation indoor wood/carpet as non-road', () async {
      // 640x640x3 Float32 buffer of saturated orange/red wood floor (R=0.90, G=0.30, B=0.10)
      final indoorBuffer = Float32List(640 * 640 * 3);
      for (int i = 0; i < indoorBuffer.length; i += 3) {
        indoorBuffer[i] = 0.90; // High R
        indoorBuffer[i + 1] = 0.30; // Medium G
        indoorBuffer[i + 2] = 0.10; // Low B (Sat > 0.85)
      }

      final isRoad = await engine.checkRoadSurface(indoorBuffer);
      expect(isRoad, isFalse);
    });
  });
}
