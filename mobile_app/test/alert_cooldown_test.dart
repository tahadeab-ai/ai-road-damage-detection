import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/core/utils/alert_cooldown_manager.dart';
import 'package:road_guard_mobile/core/utils/temporal_filter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (MethodCall methodCall) async => 1,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (MethodCall methodCall) async => 1,
    );
  });

  group('AlertCooldownManager Unit Tests', () {
    late AlertCooldownManager manager;

    setUp(() {
      manager = AlertCooldownManager();
      manager.reset();
      manager.isMuted = false;
    });

    test('Mute toggle flips state correctly', () {
      expect(manager.isMuted, isFalse);
      manager.toggleMute();
      expect(manager.isMuted, isTrue);
      manager.toggleMute();
      expect(manager.isMuted, isFalse);
    });

    test('Unconfirmed detections do not trigger alerts', () async {
      final unconfirmedTrack = TrackedDetection(
        trackingId: 1,
        classId: 3,
        className: 'Pothole',
        confidence: 0.85,
        smoothedRect: const Rect.fromLTWH(0.2, 0.5, 0.2, 0.2),
        lifecycle: TrackingLifecycle.candidate,
      );

      await manager.evaluateAlerts(
        detections: [unconfirmedTrack],
        currentSpeedKmh: 45.0,
      );
    });

    test('Confirmed detections evaluate alerts without crashing', () async {
      final confirmedTrack = TrackedDetection(
        trackingId: 1,
        classId: 3,
        className: 'Pothole',
        confidence: 0.85,
        smoothedRect: const Rect.fromLTWH(0.2, 0.5, 0.2, 0.2),
        lifecycle: TrackingLifecycle.confirmed,
      );

      final now = DateTime.now();

      await manager.evaluateAlerts(
        detections: [confirmedTrack],
        currentSpeedKmh: 45.0,
        timestamp: now,
      );

      // Second evaluation within 5 seconds cooldown should be suppressed
      await manager.evaluateAlerts(
        detections: [confirmedTrack],
        currentSpeedKmh: 45.0,
        timestamp: now.add(const Duration(seconds: 2)),
      );
    });
  });
}
