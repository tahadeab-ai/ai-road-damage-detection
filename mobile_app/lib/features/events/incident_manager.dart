import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:road_guard_mobile/shared/models/hazard_event.dart';

class IncidentManager extends ChangeNotifier {
  final List<HazardEvent> _incidents = [];
  final Set<int> _recordedTrackIds = {};

  final _incidentStreamController = StreamController<HazardEvent>.broadcast();
  Stream<HazardEvent> get incidentStream => _incidentStreamController.stream;

  List<HazardEvent> get incidents => List.unmodifiable(_incidents);
  int get totalCount => _incidents.length;
  int get pendingSyncCount => _incidents.where((e) => !e.isSynced).length;

  int countForClass(int classId) =>
      _incidents.where((e) => e.classId == classId).length;

  bool recordIncident(HazardEvent event) {
    // Deduplication check: prevent multiple recordings of the same Track ID
    if (_recordedTrackIds.contains(event.trackId)) {
      return false;
    }

    _recordedTrackIds.add(event.trackId);
    _incidents.insert(0, event); // Latest first
    _incidentStreamController.add(event);
    notifyListeners();
    return true;
  }

  void markAsSynced(String incidentId) {
    final index = _incidents.indexWhere((e) => e.incidentId == incidentId);
    if (index != -1) {
      _incidents[index] = _incidents[index].copyWith(isSynced: true);
      notifyListeners();
    }
  }

  void markAllAsSynced() {
    for (int i = 0; i < _incidents.length; i++) {
      _incidents[i] = _incidents[i].copyWith(isSynced: true);
    }
    notifyListeners();
  }

  void clear() {
    _incidents.clear();
    _recordedTrackIds.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _incidentStreamController.close();
    super.dispose();
  }
}

