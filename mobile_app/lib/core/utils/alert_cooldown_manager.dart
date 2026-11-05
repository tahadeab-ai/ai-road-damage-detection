import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'temporal_filter.dart';

/// Singleton Audio & Haptic Cooldown Manager.
/// Eliminates continuous chime looping and alert noise spam.
class AlertCooldownManager {
  static final AlertCooldownManager _instance = AlertCooldownManager._internal();
  factory AlertCooldownManager({AudioPlayer? player}) {
    if (player != null) {
      _instance._audioPlayer = player;
    }
    return _instance;
  }
  AlertCooldownManager._internal();

  AudioPlayer? _audioPlayer;
  AudioPlayer get audioPlayer => _audioPlayer ??= AudioPlayer();

  final Map<int, DateTime> _lastAlertByClass = {};
  bool _isPlayingAudio = false;
  bool isMuted = false;

  static const Duration classCooldown = Duration(milliseconds: 5000);
  static const double minAlertSpeedKmh = 8.0;

  /// Toggles global audio alert mute.
  void toggleMute() {
    isMuted = !isMuted;
  }

  /// Evaluates confirmed detections and triggers appropriate sensory alerts.
  Future<void> evaluateAlerts({
    required List<TrackedDetection> detections,
    required double currentSpeedKmh,
    DateTime? timestamp,
  }) async {
    final now = timestamp ?? DateTime.now();

    // 1. Movement Gate: Suppress audio alarms if vehicle is stationary or parking (< 8 km/h)
    final bool isMoving = currentSpeedKmh >= minAlertSpeedKmh;

    for (final track in detections) {
      // Must be confirmed across >= 3 frames to avoid transient sensor noise
      if (!track.isConfirmed) continue;

      final lastAlert = _lastAlertByClass[track.classId];
      final bool onCooldown = lastAlert != null && now.difference(lastAlert) < classCooldown;

      // Tier 1: Moderate confidence (0.50 - 0.69) -> Silent visual HUD + gentle haptic
      if (track.confidence >= 0.50 && track.confidence < 0.70) {
        if (!onCooldown) {
          _lastAlertByClass[track.classId] = now;
          try {
            HapticFeedback.lightImpact();
          } catch (_) {}
        }
      }
      // Tier 2: High severity (>= 0.70 on critical hazard) -> Chime + double haptic
      else if (track.confidence >= 0.70 && track.isCritical) {
        if (!onCooldown) {
          _lastAlertByClass[track.classId] = now;

          // Double haptic pulse
          try {
            HapticFeedback.heavyImpact();
            Future.delayed(const Duration(milliseconds: 120), () {
              try {
                HapticFeedback.heavyImpact();
              } catch (_) {}
            });
          } catch (_) {}

          // Play sound if not muted, vehicle moving, and audio channel free
          if (!isMuted && isMoving && !_isPlayingAudio) {
            _playChime();
          }
        }
      }
    }
  }

  Future<void> _playChime() async {
    try {
      _isPlayingAudio = true;
      final player = audioPlayer;
      await player.stop();
      await player.play(AssetSource('sounds/alert_chime.wav'), volume: 0.85);
      player.onPlayerComplete.first.then((_) {
        _isPlayingAudio = false;
      });
    } catch (_) {
      _isPlayingAudio = false;
    }
  }

  /// Resets cooldowns (e.g., when driving session stops).
  void reset() {
    _lastAlertByClass.clear();
    _isPlayingAudio = false;
  }

  void dispose() {
    _audioPlayer?.dispose();
    _audioPlayer = null;
  }
}
