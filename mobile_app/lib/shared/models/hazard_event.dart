import 'dart:convert';

enum HazardSeverity {
  low,
  medium,
  high,
  critical,
}

class HazardEvent {
  final String incidentId;
  final int trackId;
  final int classId;
  final String className;
  final double confidence;
  final List<double> bbox; // [x1, y1, x2, y2]
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final double speedKmh;
  final HazardSeverity severity;
  final bool isSynced;

  const HazardEvent({
    required this.incidentId,
    required this.trackId,
    required this.classId,
    required this.className,
    required this.confidence,
    required this.bbox,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.speedKmh = 0.0,
    required this.severity,
    this.isSynced = false,
  });

  /// Authoritative class names mapped by classId
  static const Map<int, String> classNames = {
    0: 'D00_longitudinal_crack',
    1: 'D10_transverse_crack',
    2: 'D20_alligator_crack',
    3: 'D40_pothole',
  };

  static HazardSeverity severityForClass(int classId, double confidence) {
    if (classId == 3) {
      // Pothole
      return confidence > 0.75 ? HazardSeverity.critical : HazardSeverity.high;
    } else if (classId == 2) {
      // Alligator Crack
      return confidence > 0.70 ? HazardSeverity.high : HazardSeverity.medium;
    } else {
      // Longitudinal or Transverse Crack
      return confidence > 0.60 ? HazardSeverity.medium : HazardSeverity.low;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'incident_id': incidentId,
      'track_id': trackId,
      'class_id': classId,
      'class_name': className,
      'confidence': confidence,
      'bbox': jsonEncode(bbox),
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'speed_kmh': speedKmh,
      'severity': severity.name,
      'is_synced': isSynced ? 1 : 0,
    };
  }

  factory HazardEvent.fromMap(Map<String, dynamic> map) {
    final rawBbox = map['bbox'];
    List<double> parsedBbox;
    if (rawBbox is String) {
      parsedBbox = (jsonDecode(rawBbox) as List).map((e) => (e as num).toDouble()).toList();
    } else if (rawBbox is List) {
      parsedBbox = rawBbox.map((e) => (e as num).toDouble()).toList();
    } else {
      parsedBbox = [0.0, 0.0, 0.0, 0.0];
    }

    return HazardEvent(
      incidentId: map['incident_id'] as String,
      trackId: map['track_id'] as int,
      classId: map['class_id'] as int,
      className: map['class_name'] as String? ?? classNames[map['class_id'] as int] ?? 'unknown',
      confidence: (map['confidence'] as num).toDouble(),
      bbox: parsedBbox,
      timestamp: DateTime.parse(map['timestamp'] as String),
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      speedKmh: (map['speed_kmh'] as num?)?.toDouble() ?? 0.0,
      severity: HazardSeverity.values.firstWhere(
        (s) => s.name == map['severity'],
        orElse: () => HazardSeverity.medium,
      ),
      isSynced: (map['is_synced'] as int?) == 1,
    );
  }

  HazardEvent copyWith({
    String? incidentId,
    int? trackId,
    int? classId,
    String? className,
    double? confidence,
    List<double>? bbox,
    DateTime? timestamp,
    double? latitude,
    double? longitude,
    double? speedKmh,
    HazardSeverity? severity,
    bool? isSynced,
  }) {
    return HazardEvent(
      incidentId: incidentId ?? this.incidentId,
      trackId: trackId ?? this.trackId,
      classId: classId ?? this.classId,
      className: className ?? this.className,
      confidence: confidence ?? this.confidence,
      bbox: bbox ?? this.bbox,
      timestamp: timestamp ?? this.timestamp,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      speedKmh: speedKmh ?? this.speedKmh,
      severity: severity ?? this.severity,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}
