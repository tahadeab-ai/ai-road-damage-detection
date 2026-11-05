import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/constants/colors.dart';
import '../bloc/detection_state.dart';

class CameraHudOverlay extends StatelessWidget {
  final DetectionState state;
  final VoidCallback onToggleStreaming;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenAnalytics;

  const CameraHudOverlay({
    super.key,
    required this.state,
    required this.onToggleStreaming,
    required this.onOpenHistory,
    required this.onOpenAnalytics,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // 1. Top HUD Header
          _buildTopHudBar(context),

          // 2. Critical Alert Banner (When Pothole or Severe Alligator Crack detected)
          if (state.criticalHazardAlert != null)
            _buildCriticalWarningBanner(context),

          const Spacer(),

          // 3. Bottom HUD Control Bar
          _buildBottomControlBar(context),
        ],
      ),
    );
  }

  Widget _buildTopHudBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceGlass,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.borderGlow, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Vehicle Speedometer
                Row(
                  children: [
                    const Icon(Icons.speed, color: AppColors.cyanAccent, size: 20),
                    const SizedBox(width: 8),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: state.gpsData.speedKmh.toStringAsFixed(0),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const TextSpan(
                            text: ' KM/H',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Latency & Inference Performance
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: state.isStreaming ? AppColors.successGps : AppColors.warning,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${state.inferenceLatencyMs}ms • ${state.fps} FPS',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),

                // GPS Lock & Active Hazards
                Row(
                  children: [
                    Icon(
                      state.gpsData.isGpsLocked ? Icons.gps_fixed : Icons.gps_not_fixed,
                      color: state.gpsData.isGpsLocked ? AppColors.successGps : AppColors.warning,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    // Incident Count Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.d40Pothole.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.d40Pothole, width: 1),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: AppColors.d40Pothole, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${state.detections.length}',
                            style: const TextStyle(
                              color: AppColors.d40Pothole,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCriticalWarningBanner(BuildContext context) {
    final alert = state.criticalHazardAlert!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.d40Pothole.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.d40Pothole.withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.emergency_outlined, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CRITICAL ROAD HAZARD DETECTED',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${alert.className.toUpperCase()} Ahead (${(alert.confidence * 100).toStringAsFixed(0)}% Conf)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().shake(duration: 400.ms, hz: 4).fadeIn(duration: 200.ms);
  }

  Widget _buildBottomControlBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceGlass,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Incident Log Navigation
                IconButton(
                  icon: const Icon(Icons.history_rounded, color: AppColors.textPrimary, size: 26),
                  tooltip: 'Incident History',
                  onPressed: onOpenHistory,
                ),

                // Main Vision Stream Action Button
                GestureDetector(
                  onTap: onToggleStreaming,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: state.isStreaming
                            ? [const Color(0xFFEF4444), const Color(0xFFB91C1C)]
                            : [AppColors.cyanAccent, const Color(0xFF00B0FF)],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: (state.isStreaming ? Colors.red : AppColors.cyanAccent).withValues(alpha: 0.4),
                          blurRadius: 16,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          state.isStreaming ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: state.isStreaming ? Colors.white : Colors.black,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          state.isStreaming ? 'PAUSE AI' : 'RESUME AI',
                          style: TextStyle(
                            color: state.isStreaming ? Colors.white : Colors.black,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Analytics Navigation
                IconButton(
                  icon: const Icon(Icons.analytics_outlined, color: AppColors.textPrimary, size: 26),
                  tooltip: 'Device Telemetry & Analytics',
                  onPressed: onOpenAnalytics,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
