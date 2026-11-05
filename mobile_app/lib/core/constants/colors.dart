import 'package:flutter/material.dart';

/// Futuristic Dark UI palette designed for in-car heads-up display (HUD).
class AppColors {
  // Backgrounds & Surface (Slate / Zinc tones)
  static const Color background = Color(0xFF090D16);
  static const Color surface = Color(0xFF111827);
  static const Color surfaceLight = Color(0xFF1E293B);
  static const Color surfaceGlass = Color(0xCC0F172A);
  static const Color border = Color(0xFF334155);
  static const Color borderGlow = Color(0x3300E5FF);

  // Typography
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Road Damage Category Accents
  static const Color d00Longitudinal = Color(0xFF00E5FF); // Neon Cyan
  static const Color d10Transverse = Color(0xFF2979FF);   // Electric Blue
  static const Color d20Alligator = Color(0xFFFF9100);    // Radiant Amber
  static const Color d40Pothole = Color(0xFFFF1744);      // Fluorescent Crimson

  // System & Telemetry Accents
  static const Color successGps = Color(0xFF00E676);      // Neon Green
  static const Color warning = Color(0xFFFFAB00);
  static const Color error = Color(0xFFFF1744);
  static const Color cyanAccent = Color(0xFF00E5FF);

  /// Returns the signature color for a defect class ID or name.
  static Color getColorForDefect(dynamic defect) {
    if (defect is int) {
      switch (defect) {
        case 0:
          return d00Longitudinal;
        case 1:
          return d10Transverse;
        case 2:
          return d20Alligator;
        case 3:
          return d40Pothole;
        default:
          return d00Longitudinal;
      }
    }
    final name = defect.toString().toLowerCase();
    if (name.contains('longitudinal') || name.contains('d00')) return d00Longitudinal;
    if (name.contains('transverse') || name.contains('d10')) return d10Transverse;
    if (name.contains('alligator') || name.contains('d20')) return d20Alligator;
    if (name.contains('pothole') || name.contains('d40')) return d40Pothole;
    return d00Longitudinal;
  }
}
