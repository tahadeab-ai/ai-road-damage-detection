import 'package:equatable/equatable.dart';
import 'package:hive/hive.dart';
import 'detection_result.dart';

part 'road_hazard.g.dart';

@HiveType(typeId: 0)
class RoadHazard extends Equatable {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String defectClass;

  @HiveField(2)
  final int classId;

  @HiveField(3)
  final double confidence;

  @HiveField(4)
  final double? latitude;

  @HiveField(5)
  final double? longitude;

  @HiveField(6)
  final double speedKmh;

  @HiveField(7)
  final DateTime timestamp;

  @HiveField(8)
  final String address;

  @HiveField(9)
  final String? snapshotPath;

  @HiveField(10)
  final double? roadXMeters;

  @HiveField(11)
  final double? roadYMeters;

  /// Alias for snapshotPath for backward & evidence capture compatibility.
  String? get imagePath => snapshotPath;

  const RoadHazard({
    required this.id,
    required this.defectClass,
    required this.classId,
    required this.confidence,
    this.latitude,
    this.longitude,
    required this.speedKmh,
    required this.timestamp,
    required this.address,
    this.snapshotPath,
    this.roadXMeters,
    this.roadYMeters,
  });

  factory RoadHazard.fromDetection({
    required String id,
    required DetectionResult detection,
    double? latitude,
    double? longitude,
    required double speedKmh,
    required String address,
    String? snapshotPath,
    double? roadXMeters,
    double? roadYMeters,
  }) {
    return RoadHazard(
      id: id,
      defectClass: detection.className,
      classId: detection.classId,
      confidence: detection.confidence,
      latitude: latitude,
      longitude: longitude,
      speedKmh: speedKmh,
      timestamp: DateTime.now(),
      address: address,
      snapshotPath: snapshotPath,
      roadXMeters: roadXMeters,
      roadYMeters: roadYMeters,
    );
  }

  /// Converts this record to a Map for SQLite persistence.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'defect_class': defectClass,
      'class_id': classId,
      'confidence': confidence,
      'latitude': latitude,
      'longitude': longitude,
      'speed_kmh': speedKmh,
      'timestamp': timestamp.toIso8601String(),
      'address': address,
      'snapshot_path': snapshotPath,
      'road_x_meters': roadXMeters,
      'road_y_meters': roadYMeters,
    };
  }

  /// Deserializes a record from a SQLite database row.
  factory RoadHazard.fromMap(Map<String, dynamic> map) {
    return RoadHazard(
      id: map['id'] as String,
      defectClass: map['defect_class'] as String,
      classId: (map['class_id'] as num).toInt(),
      confidence: (map['confidence'] as num).toDouble(),
      latitude: map['latitude'] != null ? (map['latitude'] as num).toDouble() : null,
      longitude: map['longitude'] != null ? (map['longitude'] as num).toDouble() : null,
      speedKmh: (map['speed_kmh'] as num).toDouble(),
      timestamp: DateTime.parse(map['timestamp'] as String),
      address: (map['address'] as String?) ?? '',
      snapshotPath: map['snapshot_path'] as String?,
      roadXMeters: map['road_x_meters'] != null ? (map['road_x_meters'] as num).toDouble() : null,
      roadYMeters: map['road_y_meters'] != null ? (map['road_y_meters'] as num).toDouble() : null,
    );
  }

  /// Converts this record to standard GeoJSON Feature format.
  Map<String, dynamic> toGeoJsonFeature() {
    return {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [longitude, latitude],
      },
      'properties': {
        'id': id,
        'class': defectClass,
        'class_id': classId,
        'confidence': confidence,
        'speed_kmh': speedKmh,
        'timestamp': timestamp.toIso8601String(),
        'address': address,
      },
    };
  }

  /// Converts this record to CSV row format.
  String toCsvRow() {
    return '$id,"$defectClass",$classId,$confidence,$latitude,$longitude,$speedKmh,"${timestamp.toIso8601String()}","$address"';
  }

  static String csvHeader() {
    return 'id,defect_class,class_id,confidence,latitude,longitude,speed_kmh,timestamp,address';
  }

  @override
  List<Object?> get props => [
        id,
        defectClass,
        classId,
        confidence,
        latitude,
        longitude,
        speedKmh,
        timestamp,
        address,
        snapshotPath,
        roadXMeters,
        roadYMeters,
      ];
}
