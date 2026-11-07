import 'dart:io';
import 'package:flutter/foundation.dart';

/// Centralized diagnostic logger for RoadGuard blind-mode pipeline debugging.
/// Simultaneously logs to Android Logcat (`debugPrint`) and appends raw unbuffered
/// lines to `/sdcard/Android/data/com.roadguard.road_guard_mobile/files/street_test.txt`
/// ensuring zero log loss during disconnected physical street tests.
class DebugLogger {
  static File? _logFile;
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    try {
      const path = '/sdcard/Android/data/com.roadguard.road_guard_mobile/files/street_test.txt';
      _logFile = File(path);
      if (!_logFile!.parent.existsSync()) {
        _logFile!.parent.createSync(recursive: true);
      }
      _logFile!.writeAsStringSync(
        '=== ROADGUARD ADAS BLIND-MODE DEBUG LOG START: ${DateTime.now().toIso8601String()} ===\n',
      );
      _initialized = true;
      debugPrint('[DebugLogger] Initialized file logging at $path');
    } catch (e) {
      debugPrint('[DebugLogger] Notice: unable to initialize on-device file logger ($e)');
    }
  }

  static void log(String tag, String message) {
    final line = '$tag $message';
    debugPrint(line);
    try {
      if (_logFile != null) {
        _logFile!.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
      }
    } catch (_) {}
  }
}
