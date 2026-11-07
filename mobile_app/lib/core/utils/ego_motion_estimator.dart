import 'dart:math';
import 'package:flutter/material.dart';

/// 2D SE(2) Ego-Motion Estimator & Inertial Sensor Fusion.
/// Projects vehicle motion between camera frames using vehicle speed (from GPS/OBD)
/// and yaw rate (from gyroscope), corrected for camera mount tilt.
/// Also detects deceleration pitch-dive (braking) and road grade/slope.
class EgoMotionEstimator {
  // Mounting pitch angle in radians (downward from horizontal)
  final double mountPitchRad;

  // Deceleration pitch-dive threshold in m/s^2 (braking dive)
  static const double pitchDiveDecelThreshold = -3.0;

  // Road slope/grade deviation threshold in degrees (relative to nominal pitch)
  static const double slopeAngleThresholdDeg = 5.0;

  EgoMotionEstimator({
    double mountPitchDeg = 15.0,
  }) : mountPitchRad = mountPitchDeg * (pi / 180.0);

  /// Transforms raw device body-frame angular velocity (gyroscope) to world-frame yaw rate.
  /// When the phone is mounted on the windshield tilted down by pitch [theta],
  /// the vehicle's yaw rotation in the horizontal world plane projects onto the device
  /// Z-axis (cos theta) and Y-axis (-sin theta).
  ///
  /// omega_world_yaw = omega_z * cos(theta) - omega_y * sin(theta)
  double computeWorldYawRate({
    required double gyroYRadPerSec,
    required double gyroZRadPerSec,
    double? dynamicPitchRad,
  }) {
    final theta = dynamicPitchRad ?? mountPitchRad;
    return (gyroZRadPerSec * cos(theta)) - (gyroYRadPerSec * sin(theta));
  }

  /// Evaluates whether vehicle braking is causing a transient downward pitch-dive.
  /// If longitudinal deceleration a_y < -3.0 m/s^2, the front suspension compresses,
  /// temporarily altering the camera pitch angle.
  bool detectPitchDive({required double accelYMps2}) {
    return accelYMps2 < pitchDiveDecelThreshold;
  }

  /// Evaluates whether the vehicle is traversing a significant incline/decline (road slope).
  /// Computes pitch from accelerometer gravity vector: pitch = atan2(accelZ, sqrt(accelX^2 + accelY^2)).
  /// Flags slope degraded if |pitch - nominalPitch| > 5.0 degrees.
  bool detectRoadSlope({
    required double accelXMps2,
    required double accelYMps2,
    required double accelZMps2,
  }) {
    final double gNorm = sqrt(accelXMps2 * accelXMps2 + accelYMps2 * accelYMps2 + accelZMps2 * accelZMps2);
    if (gNorm < 1.0) return false; // In freefall or sensor anomaly

    // Tilt angle relative to gravity
    final double measuredPitch = atan2(accelZMps2.abs(), sqrt(accelXMps2 * accelXMps2 + accelYMps2 * accelYMps2));
    final double pitchDiffDeg = (measuredPitch - mountPitchRad).abs() * (180.0 / pi);

    return pitchDiffDeg > slopeAngleThresholdDeg;
  }

  /// Predicts the updated position of a stationary road-plane target (X_m, Y_m)
  /// in the vehicle coordinate frame after time elapsed [dtSec] with vehicle speed [speedMps]
  /// and yaw rate [yawRateRadPerSec].
  ///
  /// 2D SE(2) Rigid Body Transformation:
  /// Delta_Ym = v * dt * cos(Delta_psi / 2)
  /// Delta_Xm = v * dt * sin(Delta_psi / 2)
  /// Delta_psi = yawRate * dt
  ///
  /// [ X_new ] = [  cos(Delta_psi)  sin(Delta_psi) ] [ X_old - Delta_Xm ]
  /// [ Y_new ]   [ -sin(Delta_psi)  cos(Delta_psi) ] [ Y_old - Delta_Ym ]
  Offset predictTargetPosition({
    required Offset currentRoadPointMeters,
    required double dtSec,
    required double speedMps,
    required double yawRateRadPerSec,
    bool isPitchDiveActive = false,
  }) {
    if (dtSec <= 0.0) return currentRoadPointMeters;

    // Longitudinal and lateral displacement of vehicle
    final double deltaPsi = yawRateRadPerSec * dtSec;
    final double halfPsi = deltaPsi / 2.0;

    // If pitch-dive is active, suspension compression makes forward projection unreliable;
    // freeze longitudinal displacement update to prevent track collapse.
    final double deltaYm = isPitchDiveActive ? 0.0 : (speedMps * dtSec * cos(halfPsi));
    final double deltaXm = speedMps * dtSec * sin(halfPsi);

    // Translate relative to vehicle motion
    final double translatedX = currentRoadPointMeters.dx - deltaXm;
    final double translatedY = currentRoadPointMeters.dy - deltaYm;

    // Rotate into new vehicle heading frame
    final double cosPsi = cos(deltaPsi);
    final double sinPsi = sin(deltaPsi);

    final double xNew = (cosPsi * translatedX) + (sinPsi * translatedY);
    final double yNew = (-sinPsi * translatedX) + (cosPsi * translatedY);

    return Offset(xNew, yNew);
  }
}
