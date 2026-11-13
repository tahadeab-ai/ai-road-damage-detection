import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class GpsData {
  final double latitude;
  final double longitude;
  final double speedKmh;
  final String address;
  final bool isGpsLocked;

  const GpsData({
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    required this.address,
    required this.isGpsLocked,
  });

  static const empty = GpsData(
    latitude: 0.0,
    longitude: 0.0,
    speedKmh: 0.0,
    address: 'Acquiring GPS Signal...',
    isGpsLocked: false,
  );
}

/// Service managing device GNSS/GPS positioning and street reverse geocoding.
class GpsService {
  StreamSubscription<Position>? _positionSubscription;
  final _gpsDataController = StreamController<GpsData>.broadcast();

  Stream<GpsData> get gpsStream => _gpsDataController.stream;
  GpsData _currentGpsData = GpsData.empty;
  GpsData get currentGpsData => _currentGpsData;

  DateTime _lastGeocodingTime = DateTime.fromMillisecondsSinceEpoch(0);
  String _cachedAddress = 'Locating Roadway...';

  /// Initializes location stream with non-blocking foreground permissions check and fast fallback.
  Future<void> initialize() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled().timeout(
        const Duration(seconds: 2),
        onTimeout: () => false,
      );
      if (!serviceEnabled) {
        _updateGpsData(GpsData.empty);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission().timeout(
        const Duration(seconds: 1),
        onTimeout: () => LocationPermission.denied,
      );
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission().timeout(
          const Duration(seconds: 2),
          onTimeout: () => LocationPermission.denied,
        );
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          _updateGpsData(GpsData.empty);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _updateGpsData(GpsData.empty);
        return;
      }

      // Fast check for last known cached position without waiting for satellite lock
      try {
        final lastPos = await Geolocator.getLastKnownPosition().timeout(
          const Duration(seconds: 1),
          onTimeout: () => null,
        );
        if (lastPos != null) {
          _updateGpsData(GpsData(
            latitude: lastPos.latitude,
            longitude: lastPos.longitude,
            speedKmh: lastPos.speed > 0 ? (lastPos.speed * 3.6) : 0.0,
            address: '${lastPos.latitude.toStringAsFixed(4)}°N, ${lastPos.longitude.toStringAsFixed(4)}°E',
            isGpsLocked: true,
          ));
        }
      } catch (_) {}

      // Subscribe to position updates
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // update every 5 meters
      );

      _positionSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (Position position) async {
          final speedKmh = position.speed > 0 ? (position.speed * 3.6) : 0.0;
          final address = await _reverseGeocode(position.latitude, position.longitude);

          final data = GpsData(
            latitude: position.latitude,
            longitude: position.longitude,
            speedKmh: speedKmh,
            address: address,
            isGpsLocked: true,
          );
          _updateGpsData(data);
        },
        onError: (e) {
          debugPrint('[GpsService] Position error: $e');
        },
      );
    } catch (e) {
      debugPrint('[GpsService] Initialization error: $e');
    }
  }

  void _updateGpsData(GpsData data) {
    _currentGpsData = data;
    if (!_gpsDataController.isClosed) {
      _gpsDataController.add(data);
    }
  }

  /// Throttled reverse geocoding to prevent rate limiting geocoding services.
  Future<String> _reverseGeocode(double lat, double lng) async {
    final now = DateTime.now();
    if (now.difference(_lastGeocodingTime).inSeconds < 10) {
      return _cachedAddress;
    }

    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final street = p.street?.isNotEmpty == true ? p.street : p.name;
        final locality = p.locality ?? p.subAdministrativeArea ?? '';
        _cachedAddress = '$street, $locality'.trim();
        _lastGeocodingTime = now;
      }
    } catch (_) {
      // In case offline, retain coordinate summary
      _cachedAddress = '${lat.toStringAsFixed(4)}°N, ${lng.toStringAsFixed(4)}°E';
    }
    return _cachedAddress;
  }

  void dispose() {
    _positionSubscription?.cancel();
    _gpsDataController.close();
  }
}
