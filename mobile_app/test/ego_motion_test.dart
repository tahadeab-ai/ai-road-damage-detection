import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/core/utils/ego_motion_estimator.dart';

void main() {
  group('EgoMotionEstimator Tests', () {
    late EgoMotionEstimator estimator;

    setUp(() {
      // Nominal windshield camera mount pitch 15 degrees
      estimator = EgoMotionEstimator(mountPitchDeg: 15.0);
    });

    test('World-frame gyroscope transformation correctly removes tilt pitch leak', () {
      const double thetaRad = 15.0 * (pi / 180.0);
      const double rawGyroZ = 0.10; // 0.10 rad/s body yaw
      const double rawGyroY = 0.05; // 0.05 rad/s body roll/pitch cross-coupling

      // Expected world yaw = gyroZ * cos(theta) - gyroY * sin(theta)
      final expectedWorldYaw = (rawGyroZ * cos(thetaRad)) - (rawGyroY * sin(thetaRad));

      final computedYaw = estimator.computeWorldYawRate(
        gyroYRadPerSec: rawGyroY,
        gyroZRadPerSec: rawGyroZ,
      );

      expect(computedYaw, closeTo(expectedWorldYaw, 1e-6));
    });

    test('Deceleration pitch-dive correctly triggers at braking deceleration < -3.0 m/s^2', () {
      expect(estimator.detectPitchDive(accelYMps2: -1.5), isFalse);
      expect(estimator.detectPitchDive(accelYMps2: -2.9), isFalse);
      expect(estimator.detectPitchDive(accelYMps2: -3.1), isTrue); // Braking dive active
      expect(estimator.detectPitchDive(accelYMps2: -5.0), isTrue); // Emergency hard stop
    });

    test('Road slope detection flags incline/decline when pitch deviates by > 5.0 degrees', () {
      // Normal flat road acceleration: gravity pointing downwards along Z with nominal 15 deg tilt
      final g = 9.81;
      final nomPitch = 15.0 * (pi / 180.0);
      final ax = 0.0;
      final ay = g * cos(nomPitch);
      final az = g * sin(nomPitch);

      expect(estimator.detectRoadSlope(accelXMps2: ax, accelYMps2: ay, accelZMps2: az), isFalse);

      // Steep incline: tilt changes to 23 degrees (diff = 8 degrees > 5.0 deg threshold)
      final steepPitch = 23.0 * (pi / 180.0);
      final aySteep = g * cos(steepPitch);
      final azSteep = g * sin(steepPitch);

      expect(estimator.detectRoadSlope(accelXMps2: ax, accelYMps2: aySteep, accelZMps2: azSteep), isTrue);
    });

    test('2D SE(2) motion prediction translates target closer to vehicle during forward motion', () {
      // Vehicle moving forward at 5 m/s (~18 km/h), dt = 0.1s, yaw rate = 0 (straight line)
      // Stationary road hazard at X=0.0m, Y=10.0m
      const initialPos = Offset(0.0, 10.0);
      final predictedPos = estimator.predictTargetPosition(
        currentRoadPointMeters: initialPos,
        dtSec: 0.1,
        speedMps: 5.0,
        yawRateRadPerSec: 0.0,
      );

      // Forward travel = 5.0 * 0.1 = 0.5 meters
      // New distance Y = 10.0 - 0.5 = 9.5 meters, lateral offset X = 0.0 meters
      expect(predictedPos.dx, closeTo(0.0, 1e-4));
      expect(predictedPos.dy, closeTo(9.5, 1e-4));
    });

    test('2D SE(2) motion prediction shifts target laterally during vehicle steering turn', () {
      // Stationary road hazard at X=0.0m, Y=10.0m
      // Vehicle turning left (positive yaw rate = 0.2 rad/s), speed = 4 m/s, dt = 0.2s
      const initialPos = Offset(0.0, 10.0);
      final predictedPosLeftTurn = estimator.predictTargetPosition(
        currentRoadPointMeters: initialPos,
        dtSec: 0.2,
        speedMps: 4.0,
        yawRateRadPerSec: 0.2,
      );

      // In vehicle frame turning left, stationary target in front appears to shift right (positive X)
      expect(predictedPosLeftTurn.dx, greaterThan(0.0));
      expect(predictedPosLeftTurn.dy, lessThan(10.0));

      // Vehicle turning right (negative yaw rate = -0.2 rad/s)
      final predictedPosRightTurn = estimator.predictTargetPosition(
        currentRoadPointMeters: initialPos,
        dtSec: 0.2,
        speedMps: 4.0,
        yawRateRadPerSec: -0.2,
      );

      // In vehicle frame turning right, stationary target in front appears to shift left (negative X)
      expect(predictedPosRightTurn.dx, lessThan(0.0));
      expect(predictedPosRightTurn.dy, lessThan(10.0));
    });

    test('Pitch-dive suspends longitudinal translation to avoid track collapse during hard braking', () {
      const initialPos = Offset(0.5, 8.0);
      final predictedPos = estimator.predictTargetPosition(
        currentRoadPointMeters: initialPos,
        dtSec: 0.2,
        speedMps: 6.0,
        yawRateRadPerSec: 0.0,
        isPitchDiveActive: true, // Braking dive active
      );

      // Longitudinal Y should remain frozen to prevent track collapse
      expect(predictedPos.dy, equals(8.0));
      expect(predictedPos.dx, equals(0.5));
    });
  });
}
