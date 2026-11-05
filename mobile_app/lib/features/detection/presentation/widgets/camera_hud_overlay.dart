import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/localization/app_localizations.dart';
import '../bloc/detection_state.dart';

class CameraHudOverlay extends StatelessWidget {
  final DetectionState state;
  final VoidCallback onToggleStreaming;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleTorch;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenAnalytics;

  const CameraHudOverlay({
    super.key,
    required this.state,
    required this.onToggleStreaming,
    required this.onToggleMute,
    required this.onToggleTorch,
    required this.onOpenHistory,
    required this.onOpenAnalytics,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: AppStrings.direction,
      child: SafeArea(
        child: Column(
          children: [
            // 1. Top Automotive Telemetry HUD Header
            _buildTopHudBar(context),

            // 2. Critical Alert Warning Banner (Confirmed Pothole or Severe Alligator Crack)
            if (state.criticalHazardAlert != null)
              _buildCriticalWarningBanner(context),

            const Spacer(),

            // 3. Bottom HUD Automotive Console
            _buildBottomControlBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHudBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceGlass,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.borderGlow, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Vehicle Speedometer & Standby Badge
                Row(
                  children: [
                    const Icon(Icons.speed_rounded, color: AppColors.cyanAccent, size: 22),
                    const SizedBox(width: 6),
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
                          TextSpan(
                            text: ' ${AppStrings.speedUnit}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (state.isLowSpeed) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: AppStrings.standbyTooltip,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.20),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.warning, width: 1),
                          ),
                          child: Text(
                            AppStrings.standby,
                            style: const TextStyle(
                              color: AppColors.warning,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                // Latency & Framerate Telemetry Tag
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border, width: 0.6),
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
                        '${state.inferenceLatencyMs}${AppStrings.msUnit} • ${state.fps} ${AppStrings.fpsUnit}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),

                // Controls & Lock: GPS, Incident Count, Audio Mute Toggle
                Row(
                  children: [
                    Icon(
                      state.gpsData.isGpsLocked ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
                      color: state.gpsData.isGpsLocked ? AppColors.successGps : AppColors.warning,
                      size: 17,
                    ),
                    const SizedBox(width: 8),

                    // Active Confirmed Hazard Count Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.d40Pothole.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.d40Pothole, width: 1),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: AppColors.d40Pothole, size: 12),
                          const SizedBox(width: 3),
                          Text(
                            '${state.trackedDetections.where((t) => t.isConfirmed).length}',
                            style: const TextStyle(
                              color: AppColors.d40Pothole,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // HUD Audio Mute Toggle Button
                    GestureDetector(
                      onTap: onToggleMute,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: state.isMuted
                              ? Colors.red.withValues(alpha: 0.25)
                              : Colors.white.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: state.isMuted ? Colors.red : AppColors.border,
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          state.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                          color: state.isMuted ? Colors.redAccent : AppColors.cyanAccent,
                          size: 16,
                        ),
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
    final defectName = AppStrings.getDefectName(alert.classId);
    final percent = (alert.confidence * 100).toInt();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.d40Pothole.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.d40Pothole.withValues(alpha: 0.55),
                  blurRadius: 22,
                  spreadRadius: 3,
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
                        AppStrings.criticalHazardTitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppStrings.criticalHazardSubtitle(defectName, percent),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
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
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceGlass,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Incident Log Navigation
                IconButton(
                  icon: const Icon(Icons.history_rounded, color: AppColors.textPrimary, size: 24),
                  tooltip: AppStrings.incidentLogs,
                  onPressed: onOpenHistory,
                ),

                // Flashlight / Night Torch Toggle
                IconButton(
                  icon: Icon(
                    state.isTorchOn ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                    color: state.isTorchOn ? AppColors.warning : AppColors.textSecondary,
                    size: 24,
                  ),
                  tooltip: AppStrings.nightVision,
                  onPressed: onToggleTorch,
                ),

                // Main Vision Stream Action Button
                GestureDetector(
                  onTap: onToggleStreaming,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: state.isStreaming
                            ? [const Color(0xFFEF4444), const Color(0xFFB91C1C)]
                            : [AppColors.cyanAccent, const Color(0xFF00B0FF)],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: (state.isStreaming ? Colors.red : AppColors.cyanAccent).withValues(alpha: 0.45),
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
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          state.isStreaming ? AppStrings.pauseAi : AppStrings.resumeAi,
                          style: TextStyle(
                            color: state.isStreaming ? Colors.white : Colors.black,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Analytics & Device Diagnostics
                IconButton(
                  icon: const Icon(Icons.analytics_outlined, color: AppColors.textPrimary, size: 24),
                  tooltip: AppStrings.diagnostics,
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
