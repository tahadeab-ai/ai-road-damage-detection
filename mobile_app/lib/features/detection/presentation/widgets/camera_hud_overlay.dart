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
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: AppLanguageNotifier.instance,
      builder: (context, lang, child) {
        return Directionality(
          textDirection: AppStrings.direction,
          child: SafeArea(
            child: Column(
              children: [
                // 1. Top Automotive Telemetry HUD Header (Overflow-Proof via FittedBox)
                _buildTopHudBar(context),

                // Non-production diagnostic tag required for measurement build
                _buildMeasurementTag(context),

                // 2. Scene Intelligence Status Chip (V1.1 UI/UX)
                _buildSceneStatusChip(context),

                // 3. Inspection Mode & Operational Regime Banner (≤ 8 km/h)
                _buildInspectionModeBanner(context),

                // 4. GPS Degraded Warning Banner
                if (!state.gpsData.isGpsLocked || (state.gpsData.latitude == 0.0 && state.gpsData.longitude == 0.0))
                  _buildGpsWarningBanner(context),

                // 5. Critical Alert Warning Banner (Confirmed Pothole or Severe Alligator Crack)
                // Suppressed if off-road to eliminate false alarms
                if (state.criticalHazardAlert != null && state.isRoadDetected)
                  _buildCriticalWarningBanner(context),

                const Spacer(),

                // 3. Bottom HUD Automotive Console
                _buildBottomControlBar(context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopHudBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Vehicle Speedometer & Standby Badge
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.speed_rounded, color: AppColors.cyanAccent, size: 20),
                      const SizedBox(width: 4),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: state.gpsData.speedKmh.toStringAsFixed(0),
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 20,
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
                        const SizedBox(width: 6),
                        Tooltip(
                          message: AppStrings.standbyTooltip,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.warning, width: 0.8),
                            ),
                            child: Text(
                              AppStrings.standby,
                              style: const TextStyle(
                                color: AppColors.warning,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(width: 10),

                  // Latency & Framerate Telemetry Tag
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border, width: 0.6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: state.isStreaming ? AppColors.successGps : AppColors.warning,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${state.inferenceLatencyMs}${AppStrings.msUnit} • ${state.fps} ${AppStrings.fpsUnit}',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Controls: Language Switcher, GPS, Incident Count, Audio Mute
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Quick Language Switcher Button (AR / EN)
                      GestureDetector(
                        onTap: () => AppLanguageNotifier.instance.toggleLanguage(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.cyanAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.cyanAccent, width: 1.0),
                          ),
                          child: Text(
                            AppStrings.languageToggleLabel,
                            style: const TextStyle(
                              color: AppColors.cyanAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // GPS Indicator
                      Icon(
                        state.gpsData.isGpsLocked ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
                        color: state.gpsData.isGpsLocked ? AppColors.successGps : AppColors.warning,
                        size: 16,
                      ),
                      const SizedBox(width: 6),

                      // Active Confirmed Hazard Count Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.d40Pothole.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.d40Pothole, width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: AppColors.d40Pothole, size: 12),
                            const SizedBox(width: 2),
                            Text(
                              '${state.trackedDetections.where((t) => t.isConfirmed).length}',
                              style: const TextStyle(
                                color: AppColors.d40Pothole,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),

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
                            size: 15,
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
      ),
    );
  }

  Widget _buildMeasurementTag(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.90), // High-visibility Amber
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: const Text(
        'DEBUG BUILD — BLIND MODE INSTRUMENTATION',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.black,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildSceneStatusChip(BuildContext context) {
    final bool isRoad = state.isRoadDetected;
    final bool isTracking = state.trackedDetections.any((t) => t.isConfirmed);
    final bool hasDetections = state.trackedDetections.isNotEmpty;

    String statusText;
    IconData statusIcon;
    Color statusColor;

    if (state.sceneStateIndex == 6) {
      statusText = AppStrings.sceneCameraObstructed;
      statusIcon = Icons.block_rounded;
      statusColor = AppColors.d40Pothole;
    } else if (!isRoad) {
      statusText = AppStrings.sceneNonRoadSurface;
      statusIcon = Icons.visibility_off_rounded;
      statusColor = AppColors.warning;
    } else if (isTracking) {
      statusText = AppStrings.sceneTrackingHazard;
      statusIcon = Icons.track_changes_rounded;
      statusColor = AppColors.d40Pothole;
    } else if (hasDetections) {
      statusText = AppStrings.sceneHazardDetected;
      statusIcon = Icons.warning_amber_rounded;
      statusColor = AppColors.cyanAccent;
    } else {
      statusText = AppStrings.sceneRoadDetected;
      statusIcon = Icons.navigation_rounded;
      statusColor = AppColors.successGps;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: statusColor.withValues(alpha: 0.6), width: 1.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, color: statusColor, size: 14),
                const SizedBox(width: 6),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (!isRoad) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      AppStrings.isArabic ? 'متوقف' : 'PAUSED',
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInspectionModeBanner(BuildContext context) {
    final speed = state.gpsData.speedKmh;
    final bool isSpeedExceeded = speed > 8.0;

    final color = isSpeedExceeded ? AppColors.warning : AppColors.successGps;
    final text = isSpeedExceeded
        ? 'SPEED EXCEEDED (>8 KM/H) - DETECTION MUTED'
        : 'INSPECTION MODE (≤ 8 KM/H)';
    final icon = isSpeedExceeded ? Icons.speed_rounded : Icons.verified_user_rounded;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color, width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 5),
            Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsWarningBanner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.warning, width: 1.0),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.gps_off_rounded, color: AppColors.warning, size: 13),
            SizedBox(width: 5),
            Text(
              '⚠️ GPS DEGRADED - VISUAL ONLY',
              style: TextStyle(
                color: AppColors.warning,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCriticalWarningBanner(BuildContext context) {
    final alert = state.criticalHazardAlert!;
    final defectName = AppStrings.getDefectName(alert.classId);
    final percent = (alert.confidence * 100).toInt();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                const Icon(Icons.emergency_outlined, color: Colors.white, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.criticalHazardTitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppStrings.criticalHazardSubtitle(defectName, percent),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
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
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
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
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          state.isStreaming ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: state.isStreaming ? Colors.white : Colors.black,
                          size: 19,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          state.isStreaming ? AppStrings.pauseAi : AppStrings.resumeAi,
                          style: TextStyle(
                            color: state.isStreaming ? Colors.white : Colors.black,
                            fontSize: 12,
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
