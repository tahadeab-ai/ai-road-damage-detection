import 'package:flutter/material.dart';

/// Cyber-Automotive Dark HUD palette designed for VeloPath AI v2.0 (zero windshield glare day and night)
class AppColors {
  // Backgrounds & Surface (Obsidian & Slate Card)
  static const Color background = Color(0xFF0B0F17); // Deep Obsidian
  static const Color surface = Color(0xFF151C28);    // Slate Card
  static const Color surfaceLight = Color(0xFF1E2838);
  static const Color surfaceGlass = Color(0xCC151C28);
  static const Color border = Color(0xFF263345);
  static const Color borderGlow = Color(0x3300F0FF);

  // Primary Brand Accent
  static const Color laserCyan = Color(0xFF00F0FF);
  static const Color cyanAccent = Color(0xFF00F0FF);

  // Typography
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Road Damage Category Accents (RDD2022)
  static const Color d00Longitudinal = Color(0xFFFFB800); // Amber Pulse
  static const Color d10Transverse = Color(0xFFFFB800);   // Amber Pulse
  static const Color d20Alligator = Color(0xFFFF6B00);    // Vivid Orange
  static const Color d40Pothole = Color(0xFFFF1E42);      // Crimson Neon

  // System & Telemetry Accents
  static const Color successGps = Color(0xFF10B981);      // Emerald
  static const Color warning = Color(0xFFFFB800);
  static const Color error = Color(0xFFFF1E42);

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
