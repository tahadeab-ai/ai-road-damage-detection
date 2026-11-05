import 'dart:convert';
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

  /// Stores a new hazard incident with duplicate suppression.
  Future<bool> logHazard(RoadHazard hazard) async {
    if (_box == null) await initialize();

    // Deduplication filter: Avoid logging identical defect within 3 seconds
    final existing = _box!.values.where((h) =>
        h.classId == hazard.classId &&
        hazard.timestamp.difference(h.timestamp).inSeconds.abs() < 3);

    if (existing.isNotEmpty) {
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
