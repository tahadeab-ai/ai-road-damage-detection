import 'dart:math';
import 'package:flutter/material.dart';

/// Inverse Perspective Mapping (IPM) & Ground Plane Geometry.
/// Projects 2D normalized camera viewport coordinates onto the 3D metric road plane (X_m, Y_m),
/// and re-projects metric road-plane points back to 2D viewport coordinates for HUD drawing.
class InversePerspectiveMapping {
  // Nominal windshield camera mount calibration parameters
  final double mountHeightMeters; // Height above ground (default 1.25m)
  final double mountPitchDeg;     // Downward tilt angle below horizontal (default 15.0 deg)
  final double fovVerticalDeg;    // Camera vertical field of view (default 54.0 deg)
  final double fovHorizontalDeg;  // Camera horizontal field of view (default 68.0 deg)

  late final double _pitchRad;
  late final double _fovVRad;
  late final double _fovHRad;

  InversePerspectiveMapping({
    this.mountHeightMeters = 1.25,
    this.mountPitchDeg = 15.0,
    this.fovVerticalDeg = 54.0,
    this.fovHorizontalDeg = 68.0,
  }) {
    _pitchRad = mountPitchDeg * (pi / 180.0);
    _fovVRad = fovVerticalDeg * (pi / 180.0);
    _fovHRad = fovHorizontalDeg * (pi / 180.0);
  }

  /// Projects normalized image bottom-center (u, v) in [0.0, 1.0] to road-plane metric coordinates (X_m, Y_m).
  /// Origin (0, 0) is directly under the vehicle's front bumper on the ground plane.
  /// X_m: Lateral offset in meters (positive = right, negative = left).
  /// Y_m: Longitudinal distance forward in meters.
  /// If the ray is parallel to or above the road horizon (v < horizon), returns null.
  Offset? imageToRoadPlane(double u, double v, {double dynamicPitchOffsetRad = 0.0}) {
    final effectivePitch = _pitchRad + dynamicPitchOffsetRad;

    // Angle of ray relative to camera optical axis
    // v = 0.5 is optical center, v > 0.5 is below optical axis (closer to ground)
    final double alphaY = (v - 0.5) * _fovVRad;

    // Total downward depression angle to road point
    final double gamma = effectivePitch + alphaY;

    // Ray is pointing near/above horizon -> infinite distance
    if (gamma <= (1.0 * pi / 180.0)) {
      return null;
    }

    // Longitudinal metric distance: Y_m = h / tan(gamma)
    final double ym = mountHeightMeters / tan(gamma);
    if (ym <= 0.0 || ym > 60.0) {
      return null; // Beyond reliable road horizon
    }

    // Lateral metric distance: X_m = Y_m * tan(alphaX)
    final double alphaX = (u - 0.5) * _fovHRad;
    final double xm = ym * tan(alphaX);

    return Offset(xm, ym);
  }

  /// Re-projects road-plane metric coordinates (X_m, Y_m) back to normalized viewport coordinates (u, v).
  /// Returns null if point is behind camera or beyond field of view.
  Offset? roadPlaneToImage(double xm, double ym, {double dynamicPitchOffsetRad = 0.0}) {
    if (ym <= 0.2) return null; // Behind or right at bumper

    final effectivePitch = _pitchRad + dynamicPitchOffsetRad;

    // gamma = atan(h / ym)
    final double gamma = atan2(mountHeightMeters, ym);
    final double alphaY = gamma - effectivePitch;
    final double v = 0.5 + (alphaY / _fovVRad);

    // alphaX = atan(xm / ym)
    final double alphaX = atan2(xm, ym);
    final double u = 0.5 + (alphaX / _fovHRad);

    return Offset(u.clamp(0.0, 1.0), v.clamp(0.0, 1.0));
  }

  /// Calculates the range-dependent association gating distance d_gate in meters.
  /// Accounts for quadratic error growth at longer distances.
  double calculateAssociationGate(double ym) {
    return (0.80 + 0.07 * ym).clamp(0.90, 2.50);
  }
}
