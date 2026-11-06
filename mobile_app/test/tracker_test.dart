import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/features/events/incident_manager.dart';
import 'package:road_guard_mobile/features/hazard_detection/hazard_tracker.dart';
import 'package:road_guard_mobile/features/hazard_detection/inference_engine.dart';
import 'package:road_guard_mobile/features/hazard_detection/surface_filter.dart';
import 'package:road_guard_mobile/shared/models/hazard_event.dart';

void main() {
  group('Mobile HazardTracker Tests', () {
    test('Tracks hazard across frames and logs incident once upon confirmation', () {
      final tracker = HazardTracker();

      // Frame 1
      final res1 = tracker.processFrame(
        detections: [
          {'class_id': 3, 'confidence': 0.85, 'bbox': [0.2, 0.4, 0.3, 0.5]},
        ],
        timestampSeconds: 0.0,
      );
      expect(res1['hud_alerts']!.isEmpty, true); // Tentative
      expect(res1['logged_incidents']!.isEmpty, true);

      // Frame 2
      final res2 = tracker.processFrame(
        detections: [
          {'class_id': 3, 'confidence': 0.88, 'bbox': [0.22, 0.44, 0.32, 0.54]},
        ],
        timestampSeconds: 0.1,
      );
      expect(res2['logged_incidents']!.isEmpty, true); // Tentative, 2 hits

      // Frame 3 - Confirmation
      final res3 = tracker.processFrame(
        detections: [
          {'class_id': 3, 'confidence': 0.90, 'bbox': [0.24, 0.48, 0.34, 0.58]},
        ],
        timestampSeconds: 0.2,
      );
      expect(res3['hud_alerts']!.length, 1);
      expect(res3['logged_incidents']!.length, 1);
      expect(res3['logged_incidents']![0]['track_id'], 1);
      expect(res3['logged_incidents']![0]['class_id'], 3);

      // Frame 4 - Persistent track should NOT log duplicate incident
      final res4 = tracker.processFrame(
        detections: [
          {'class_id': 3, 'confidence': 0.92, 'bbox': [0.26, 0.52, 0.36, 0.62]},
        ],
        timestampSeconds: 0.3,
      );
      expect(res4['hud_alerts']!.length, 1);
      expect(res4['logged_incidents']!.isEmpty, true); // No duplicate log
    });

    test('Surface filter suppresses detections above horizon and preserves high confidence', () {
      final filter = RoadSurfaceContextFilter();

      // Sky detection (above 30% horizon)
      final skyDet = {'class_id': 3, 'confidence': 0.50, 'bbox': [0.2, 0.05, 0.4, 0.15]};
      expect(filter.filterDetection(detection: skyDet, frameWidth: 1280, frameHeight: 720), false);

      // Road plane detection
      final roadDet = {'class_id': 3, 'confidence': 0.50, 'bbox': [0.2, 0.45, 0.4, 0.60]};
      expect(filter.filterDetection(detection: roadDet, frameWidth: 1280, frameHeight: 720), true);

      // High confidence bypass rule
      final highConfSky = {'class_id': 3, 'confidence': 0.85, 'bbox': [0.2, 0.05, 0.4, 0.15]};
      expect(filter.filterDetection(detection: highConfSky, frameWidth: 1280, frameHeight: 720), true);

      // Debug toggle (enabled: false)
      final disabledFilter = RoadSurfaceContextFilter(enabled: false);
      expect(disabledFilter.filterDetection(detection: skyDet, frameWidth: 1280, frameHeight: 720), true);
    });

    test('InferenceEngine decodes raw 4-class tensor and filters properly', () {
      final engine = InferenceEngine();

      // Synthetic [8, 8400] tensor
      final tensor = List.generate(8, (_) => List<double>.filled(8400, 0.0));

      // Anchor 50: D40 Pothole (class 3) score 0.92
      tensor[0][50] = 0.50; // xc
      tensor[1][50] = 0.60; // yc
      tensor[2][50] = 0.10; // w
      tensor[3][50] = 0.10; // h
      tensor[7][50] = 0.92; // D40 score

      // Anchor 51: Duplicate D40 (overlapping, score 0.70)
      tensor[0][51] = 0.505;
      tensor[1][51] = 0.602;
      tensor[2][51] = 0.098;
      tensor[3][51] = 0.099;
      tensor[7][51] = 0.70;

      // Anchor 200: D10 Transverse Crack (class 1) score 0.88
      tensor[0][200] = 0.35;
      tensor[1][200] = 0.50;
      tensor[2][200] = 0.20;
      tensor[3][200] = 0.05;
      tensor[5][200] = 0.88; // D10 score

      final decoded = engine.decodeRawTensor(
        tensor: tensor,
        frameWidth: 640,
        frameHeight: 640,
      );

      // NMS should suppress duplicate anchor 51, leaving exactly 2 hazards
      expect(decoded.length, 2);
      expect(decoded[0]['class_id'], 3); // Highest confidence first (0.92)
      expect(decoded[1]['class_id'], 1); // Second highest (0.88)
    });

    test('IncidentManager records incidents without duplicates and tracks counts', () {
      final manager = IncidentManager();

      final inc1 = HazardEvent(
        incidentId: 'inc_1',
        trackId: 10,
        classId: 3,
        className: 'D40_pothole',
        confidence: 0.91,
        bbox: const [100, 200, 200, 300],
        timestamp: DateTime.now(),
        severity: HazardSeverity.critical,
      );

      final incDuplicate = HazardEvent(
        incidentId: 'inc_2',
        trackId: 10, // Same track ID
        classId: 3,
        className: 'D40_pothole',
        confidence: 0.94,
        bbox: const [105, 205, 205, 305],
        timestamp: DateTime.now(),
        severity: HazardSeverity.critical,
      );

      final recorded1 = manager.recordIncident(inc1);
      final recorded2 = manager.recordIncident(incDuplicate);

      expect(recorded1, true);
      expect(recorded2, false); // Blocked duplicate
      expect(manager.totalCount, 1);
      expect(manager.countForClass(3), 1);
      expect(manager.pendingSyncCount, 1);

      manager.markAsSynced('inc_1');
      expect(manager.pendingSyncCount, 0);
    });
  });
}
