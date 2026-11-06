import 'dart:math';

/// State of the surrounding driving environment.
enum SceneState {
  checking, // Initializing / calibrating
  road,     // Verified navigable road scene
  nonRoad,  // Off-road / indoor (wall, floor, ceiling, furniture)
  uncertain // Ambiguous / transition state (hysteresis hold)
}

/// Lightweight Stage 1 Scene Classifier.
/// Pre-filters camera frames before YOLO11n damage detection.
/// Features 3-frame temporal hysteresis and periodic execution (N=5 frames).
class SceneClassifier {
  final int periodicInterval;
  final double roadThreshold;
  final double nonRoadThreshold;
  final int hysteresisFrames;

  SceneState _currentState = SceneState.checking;
  int _frameCounter = 0;
  double _lastRoadProb = 1.0;

  int _consecutiveRoadVotes = 0;
  int _consecutiveNonRoadVotes = 0;

  SceneClassifier({
    this.periodicInterval = 5,
    this.roadThreshold = 0.65,
    this.nonRoadThreshold = 0.70,
    this.hysteresisFrames = 3,
  });

  SceneState get currentState => _currentState;
  bool get isRoad => _currentState == SceneState.road;
  bool get shouldRunDamageDetection => isRoad;
  double get roadProbability => _lastRoadProb;

  /// Evaluates an incoming camera frame.
  /// Supports optional [mockRoadProb] for unit testing and deterministic simulation.
  Map<String, dynamic> evaluateFrame({
    double? mockRoadProb,
    int? frameWidth,
    int? frameHeight,
  }) {
    _frameCounter++;

    // Periodic execution optimization: reuse last state on intermediate frames
    if (_frameCounter % periodicInterval != 0 && _currentState != SceneState.checking) {
      return {
        'state': _currentState,
        'is_road': isRoad,
        'road_prob': _lastRoadProb,
        'skipped_inference': true,
      };
    }

    final double roadProb = (mockRoadProb ?? _lastRoadProb).clamp(0.0, 1.0);
    _lastRoadProb = roadProb;

    // Update consecutive votes
    if (roadProb >= roadThreshold) {
      _consecutiveRoadVotes++;
      _consecutiveNonRoadVotes = 0;
    } else if (roadProb <= (1.0 - nonRoadThreshold)) {
      _consecutiveNonRoadVotes++;
      _consecutiveRoadVotes = 0;
    } else {
      // Borderline / ambiguous region
      _consecutiveRoadVotes = max(0, _consecutiveRoadVotes - 1);
      _consecutiveNonRoadVotes = max(0, _consecutiveNonRoadVotes - 1);
    }

    // State transition via temporal hysteresis
    if (_consecutiveRoadVotes >= hysteresisFrames) {
      _currentState = SceneState.road;
    } else if (_consecutiveNonRoadVotes >= hysteresisFrames) {
      _currentState = SceneState.nonRoad;
    } else if (_currentState == SceneState.checking) {
      _currentState = roadProb >= 0.50 ? SceneState.road : SceneState.nonRoad;
    }

    return {
      'state': _currentState,
      'is_road': isRoad,
      'road_prob': _lastRoadProb,
      'skipped_inference': false,
    };
  }

  void reset() {
    _currentState = SceneState.checking;
    _frameCounter = 0;
    _consecutiveRoadVotes = 0;
    _consecutiveNonRoadVotes = 0;
    _lastRoadProb = 1.0;
  }
}
