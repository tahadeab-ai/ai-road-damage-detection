import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

enum PermissionStep {
  initial,
  requestingCamera,
  requestingLocation,
  requestingNotification,
  allGranted,
  denied,
  permanentlyDenied,
}

/// Robust Sequential Permission Lifecycle Handler for Android 10–15 (API 29–35)
class PermissionStateMachine extends ChangeNotifier {
  PermissionStep _currentStep = PermissionStep.initial;
  String _errorMessage = '';

  PermissionStep get currentStep => _currentStep;
  String get errorMessage => _errorMessage;
  bool get isReady => _currentStep == PermissionStep.allGranted;

  /// Request permissions in strict deterministic sequence
  Future<bool> requestSequentialPermissions() async {
    // 1. Camera Permission
    _currentStep = PermissionStep.requestingCamera;
    notifyListeners();

    var cameraStatus = await Permission.camera.status;
    if (!cameraStatus.isGranted) {
      cameraStatus = await Permission.camera.request();
    }

    if (cameraStatus.isPermanentlyDenied) {
      _currentStep = PermissionStep.permanentlyDenied;
      _errorMessage = 'Camera permission is permanently denied. Please enable it in Settings.';
      notifyListeners();
      return false;
    }

    if (!cameraStatus.isGranted) {
      _currentStep = PermissionStep.denied;
      _errorMessage = 'Camera access is required for real-time road inspection.';
      notifyListeners();
      return false;
    }

    // 2. Geolocation (Fine & Coarse)
    _currentStep = PermissionStep.requestingLocation;
    notifyListeners();

    var locationStatus = await Permission.locationWhenInUse.status;
    if (!locationStatus.isGranted) {
      locationStatus = await Permission.locationWhenInUse.request();
    }

    if (locationStatus.isPermanentlyDenied) {
      _currentStep = PermissionStep.permanentlyDenied;
      _errorMessage = 'Location permission is permanently denied. Please enable it in Settings.';
      notifyListeners();
      return false;
    }

    if (!locationStatus.isGranted) {
      _currentStep = PermissionStep.denied;
      _errorMessage = 'Location is required to geotag detected road hazards.';
      notifyListeners();
      return false;
    }

    // 3. Notification & Foreground service (Android 13+)
    _currentStep = PermissionStep.requestingNotification;
    notifyListeners();

    final notifStatus = await Permission.notification.status;
    if (!notifStatus.isGranted) {
      await Permission.notification.request();
    }

    // All mandatory permissions granted cleanly
    _currentStep = PermissionStep.allGranted;
    _errorMessage = '';
    notifyListeners();
    return true;
  }

  /// Open Android App Settings
  Future<void> openAppSettingsMenu() async {
    await openAppSettings();
  }
}
