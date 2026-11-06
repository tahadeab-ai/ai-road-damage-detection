import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/features/hazard_detection/scene_classifier.dart';

void main() {
  group('Flutter SceneClassifier Unit Tests', () {
    test('Identifies road scene after consecutive consistent frames', () {
      final classifier = SceneClassifier(periodicInterval: 1, hysteresisFrames: 3);

      for (int i = 0; i < 3; i++) {
        classifier.evaluateFrame(mockRoadProb: 0.90);
      }

      expect(classifier.currentState, equals(SceneState.road));
      expect(classifier.isRoad, isTrue);
      expect(classifier.shouldRunDamageDetection, isTrue);
    });

    test('Single outlier frame does not flip state (hysteresis anti-jitter)', () {
      final classifier = SceneClassifier(periodicInterval: 1, hysteresisFrames: 3);

      // Establish ROAD state
      for (int i = 0; i < 3; i++) {
        classifier.evaluateFrame(mockRoadProb: 0.85);
      }
      expect(classifier.isRoad, isTrue);

      // 1 glitch frame (wall flash)
      final res = classifier.evaluateFrame(mockRoadProb: 0.10);
      expect(res['state'], equals(SceneState.road));
      expect(classifier.isRoad, isTrue);
    });

    test('Persistent non-road frames transition state and disable damage detection', () {
      final classifier = SceneClassifier(periodicInterval: 1, hysteresisFrames: 3);

      // 3 consecutive non-road frames (e.g. phone facing room ceiling or floor)
      for (int i = 0; i < 3; i++) {
        classifier.evaluateFrame(mockRoadProb: 0.15);
      }

      expect(classifier.currentState, equals(SceneState.nonRoad));
      expect(classifier.isRoad, isFalse);
      expect(classifier.shouldRunDamageDetection, isFalse);
    });

    test('Periodic interval skips 4 out of 5 inference passes', () {
      final classifier = SceneClassifier(periodicInterval: 5, hysteresisFrames: 1);

      // Frame 1 -> runs
      final r1 = classifier.evaluateFrame(mockRoadProb: 0.90);
      expect(r1['skipped_inference'], isFalse);

      // Frames 2, 3, 4 -> skipped
      for (int i = 2; i <= 4; i++) {
        final rf = classifier.evaluateFrame(mockRoadProb: 0.90);
        expect(rf['skipped_inference'], isTrue);
      }

      // Frame 5 -> runs
      final r5 = classifier.evaluateFrame(mockRoadProb: 0.90);
      expect(r5['skipped_inference'], isFalse);
    });
  });
}
