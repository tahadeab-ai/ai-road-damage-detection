import 'dart:math';

enum TrackState {
  tentative,
  confirmed,
  logged,
  lost,
}

class TrackedHazard {
  final int trackId;
  final int classId;
  double confidence;
  List<double> bbox; // [x1, y1, x2, y2]
  Point<double> centroid;
  Point<double> velocity; // [vx, vy] per second
  double lastTimestamp;
  final double firstTimestamp;

  int hitCount = 1;
  int missCount = 0;
  TrackState state = TrackState.tentative;
  bool hasLoggedIncident = false;

  TrackedHazard({
    required this.trackId,
    required this.classId,
    required this.confidence,
    required List<double> initialBbox,
    required this.lastTimestamp,
  })  : bbox = List<double>.from(initialBbox),
        firstTimestamp = lastTimestamp,
        centroid = Point<double>(
          (initialBbox[0] + initialBbox[2]) / 2.0,
          (initialBbox[1] + initialBbox[3]) / 2.0,
        ),
        velocity = const Point<double>(0.0, 0.0);

  Point<double> predict(double currentTimestamp) {
    final double dt = max(0.001, currentTimestamp - lastTimestamp);
    return Point<double>(
      centroid.x + (velocity.x * dt),
      centroid.y + (velocity.y * dt),
    );
  }

  void update({
    required List<double> newBbox,
    required double newConfidence,
    required double currentTimestamp,
    double alphaPos = 0.7,
    double alphaVel = 0.3,
  }) {
    final double dt = max(0.001, currentTimestamp - lastTimestamp);
    final newCentroid = Point<double>(
      (newBbox[0] + newBbox[2]) / 2.0,
      (newBbox[1] + newBbox[3]) / 2.0,
    );

    // Delta-t velocity estimation
    final instantVel = Point<double>(
      (newCentroid.x - centroid.x) / dt,
      (newCentroid.y - centroid.y) / dt,
    );
    velocity = Point<double>(
      (alphaVel * instantVel.x) + ((1.0 - alphaVel) * velocity.x),
      (alphaVel * instantVel.y) + ((1.0 - alphaVel) * velocity.y),
    );

    // Exponential Moving Average position smoothing
    centroid = Point<double>(
      (alphaPos * newCentroid.x) + ((1.0 - alphaPos) * centroid.x),
      (alphaPos * newCentroid.y) + ((1.0 - alphaPos) * centroid.y),
    );

    for (int i = 0; i < 4; i++) {
      bbox[i] = (alphaPos * newBbox[i]) + ((1.0 - alphaPos) * bbox[i]);
    }

    confidence = (alphaPos * newConfidence) + ((1.0 - alphaPos) * confidence);
    lastTimestamp = currentTimestamp;
    hitCount++;
    missCount = 0;

    // Transition to confirmed after minimum hits
    if (state == TrackState.tentative && hitCount >= 3) {
      state = TrackState.confirmed;
    }
  }

  void markMissed(int maxMisses) {
    missCount++;
    if (missCount >= maxMisses) {
      state = TrackState.lost;
    }
  }
}

class HazardTracker {
  final double iouWeight;
  final double distWeight;
  final double maxDistThreshold;
  final double minIouThreshold;
  final int minHitsToConfirm;
  final int maxMissesToDrop;

  int _nextTrackId = 1;
  final Map<int, TrackedHazard> tracks = {};

  HazardTracker({
    this.iouWeight = 0.6,
    this.distWeight = 0.4,
    this.maxDistThreshold = 0.25,
    this.minIouThreshold = 0.20,
    this.minHitsToConfirm = 3,
    this.maxMissesToDrop = 8,
  });

  static double computeIoU(List<double> b1, List<double> b2) {
    final double x1 = max(b1[0], b2[0]);
    final double y1 = max(b1[1], b2[1]);
    final double x2 = min(b1[2], b2[2]);
    final double y2 = min(b1[3], b2[3]);

    final double inter = max(0.0, x2 - x1) * max(0.0, y2 - y1);
    final double area1 = (b1[2] - b1[0]) * (b1[3] - b1[1]);
    final double area2 = (b2[2] - b2[0]) * (b2[3] - b2[1]);
    final double union = area1 + area2 - inter;

    if (union <= 0.0) return 0.0;
    return inter / union;
  }

  double _associationCost(
    TrackedHazard track,
    Map<String, dynamic> det,
    double currentTimestamp,
  ) {
    if (track.classId != det['class_id']) return 1.0;

    final List<double> detBbox = (det['bbox'] as List).cast<double>();
    final double iou = computeIoU(track.bbox, detBbox);

    final Point<double> pred = track.predict(currentTimestamp);
    final Point<double> detCentroid = Point<double>(
      (detBbox[0] + detBbox[2]) / 2.0,
      (detBbox[1] + detBbox[3]) / 2.0,
    );

    final double dist = sqrt(
      pow(pred.x - detCentroid.x, 2) + pow(pred.y - detCentroid.y, 2),
    );

    if (dist > maxDistThreshold && iou < minIouThreshold) {
      return 1.0;
    }

    return (distWeight * min(1.0, dist / maxDistThreshold)) +
        (iouWeight * (1.0 - iou));
  }

  Map<String, List<Map<String, dynamic>>> processFrame({
    required List<Map<String, dynamic>> detections,
    double? timestampSeconds,
  }) {
    final double now =
        timestampSeconds ?? (DateTime.now().millisecondsSinceEpoch / 1000.0);

    final List<int> trackIds = tracks.keys.toList();
    final Set<int> assignedTracks = {};
    final Set<int> assignedDets = {};

    // Association Greedy Matching
    final List<List<dynamic>> candidates = [];
    for (int tIdx = 0; tIdx < trackIds.length; tIdx++) {
      final tid = trackIds[tIdx];
      for (int dIdx = 0; dIdx < detections.length; dIdx++) {
        final cost = _associationCost(tracks[tid]!, detections[dIdx], now);
        if (cost < 0.70) {
          candidates.add([cost, tid, dIdx]);
        }
      }
    }

    candidates.sort((a, b) => (a[0] as double).compareTo(b[0] as double));

    for (final cand in candidates) {
      final int tid = cand[1] as int;
      final int dIdx = cand[2] as int;
      if (!assignedTracks.contains(tid) && !assignedDets.contains(dIdx)) {
        final det = detections[dIdx];
        tracks[tid]!.update(
          newBbox: (det['bbox'] as List).cast<double>(),
          newConfidence: (det['confidence'] as num).toDouble(),
          currentTimestamp: now,
        );
        assignedTracks.add(tid);
        assignedDets.add(dIdx);
      }
    }

    // Mark missed tracks
    for (final tid in trackIds) {
      if (!assignedTracks.contains(tid)) {
        tracks[tid]!.markMissed(maxMissesToDrop);
      }
    }

    // Register new tentative tracks
    for (int dIdx = 0; dIdx < detections.length; dIdx++) {
      if (!assignedDets.contains(dIdx)) {
        final det = detections[dIdx];
        final newTrack = TrackedHazard(
          trackId: _nextTrackId,
          classId: det['class_id'] as int,
          confidence: (det['confidence'] as num).toDouble(),
          initialBbox: (det['bbox'] as List).cast<double>(),
          lastTimestamp: now,
        );
        tracks[_nextTrackId] = newTrack;
        _nextTrackId++;
      }
    }

    final List<Map<String, dynamic>> activeHudAlerts = [];
    final List<Map<String, dynamic>> newIncidentsToLog = [];
    final List<int> deadTracks = [];

    for (final entry in tracks.entries) {
      final track = entry.value;
      if (track.state == TrackState.lost) {
        deadTracks.add(entry.key);
        continue;
      }

      if (track.state == TrackState.confirmed ||
          track.state == TrackState.logged) {
        activeHudAlerts.add({
          'track_id': track.trackId,
          'class_id': track.classId,
          'confidence': track.confidence,
          'bbox': track.bbox,
          'hit_count': track.hitCount,
          'state': track.state.name,
        });
      }

      if (track.state == TrackState.confirmed && !track.hasLoggedIncident) {
        track.hasLoggedIncident = true;
        track.state = TrackState.logged;
        newIncidentsToLog.add({
          'incident_id': 'INC-${track.trackId}-${track.firstTimestamp.toInt()}',
          'track_id': track.trackId,
          'class_id': track.classId,
          'confidence': track.confidence,
          'bbox': track.bbox,
          'timestamp': track.firstTimestamp,
        });
      }
    }

    for (final tid in deadTracks) {
      tracks.remove(tid);
    }

    return {
      'hud_alerts': activeHudAlerts,
      'logged_incidents': newIncidentsToLog,
    };
  }
}
