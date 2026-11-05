import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../detection/domain/models/road_hazard.dart';

class HazardRepository {
  static const String boxName = 'road_hazard_box';
  Box<RoadHazard>? _box;

  /// Initializes Hive database and opens the hazards box.
  Future<void> initialize() async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(RoadHazardAdapter());
    }
    _box = await Hive.openBox<RoadHazard>(boxName);
  }

  /// Retrieves all logged hazard records sorted newest first.
  List<RoadHazard> getAllHazards() {
    if (_box == null) return [];
    final list = _box!.values.toList();
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  /// Stores a new hazard incident with spatio-temporal duplicate suppression.
  Future<bool> logHazard(RoadHazard hazard) async {
    if (_box == null) await initialize();

    // 1. Vehicle Movement Gate: Suppress logging if stationary / parking (speed < 5 km/h)
    if (hazard.speedKmh < 5.0 && hazard.latitude != 0.0) {
      return false; // Suppressed while stationary/parking
    }

    // 2. Spatio-temporal deduplication gate:
    // Suppress same defect class if within 15 meters AND within 8.0 seconds
    final recentSameClass = _box!.values.where((h) {
      if (h.classId != hazard.classId) return false;
      final elapsedSec = hazard.timestamp.difference(h.timestamp).inMilliseconds.abs() / 1000.0;
      if (elapsedSec >= 8.0) return false;

      // Check distance if GPS coords are available
      if (hazard.latitude != 0.0 && h.latitude != 0.0) {
        final dist = Geolocator.distanceBetween(
          h.latitude,
          h.longitude,
          hazard.latitude,
          hazard.longitude,
        );
        return dist <= 15.0; // Same location within 15 meters
      }
      return true; // Fallback to temporal suppression if GPS not yet locked
    });

    if (recentSameClass.isNotEmpty) {
      return false; // Suppressed duplicate frame detection
    }

    await _box!.put(hazard.id, hazard);
    return true;
  }

  /// Clears the hazard log database.
  Future<void> clearAll() async {
    await _box?.clear();
  }

  /// Exports logged incidents as a standard GeoJSON FeatureCollection document.
  String exportToGeoJson() {
    final hazards = getAllHazards();
    final geoJsonMap = {
      'type': 'FeatureCollection',
      'features': hazards.map((h) => h.toGeoJsonFeature()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(geoJsonMap);
  }

  /// Exports logged incidents as CSV string.
  String exportToCsv() {
    final hazards = getAllHazards();
    final buffer = StringBuffer();
    buffer.writeln(RoadHazard.csvHeader());
    for (final h in hazards) {
      buffer.writeln(h.toCsvRow());
    }
    return buffer.toString();
  }
}
