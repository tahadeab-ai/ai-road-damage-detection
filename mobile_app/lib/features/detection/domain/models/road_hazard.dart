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
  final double latitude;

  @HiveField(5)
  final double longitude;

  @HiveField(6)
  final double speedKmh;

  @HiveField(7)
  final DateTime timestamp;

  @HiveField(8)
  final String address;

  @HiveField(9)
  final String? snapshotPath;

  const RoadHazard({
    required this.id,
    required this.defectClass,
    required this.classId,
    required this.confidence,
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    required this.timestamp,
    required this.address,
    this.snapshotPath,
  });

  factory RoadHazard.fromDetection({
    required String id,
    required DetectionResult detection,
    required double latitude,
    required double longitude,
    required double speedKmh,
    required String address,
    String? snapshotPath,
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
      ];
}
