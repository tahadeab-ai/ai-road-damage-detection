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
  final VoidCallback onToggleBenchMode;
  final VoidCallback onToggleRoadGate;

  const CameraHudOverlay({
    super.key,
    required this.state,
    required this.onToggleStreaming,
    required this.onToggleMute,
    required this.onToggleTorch,
    required this.onOpenHistory,
    required this.onOpenAnalytics,
    required this.onToggleBenchMode,
    required this.onToggleRoadGate,
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
                // 1. Top Cyber-Automotive Telemetry Cockpit Card
                _buildTopCockpitCard(context),

                // Diagnostic Pipeline Error Banner (if error occurred during frame processing)
                if (state.lastPipelineError != null)
                  _buildDiagnosticErrorBanner(context),

                const SizedBox(height: 4),

                // 2. Non-Road Surface Alert or Scene Status Chip
                if (!state.isRoadDetected && !state.isBenchTestMode && state.isRoadGateEnabled)
                  _buildSurfaceGateAlertBanner(context)
                else
                  _buildSceneStatusChip(context),

                // 3. Critical Hazard Alert Banner
                if (state.criticalHazardAlert != null && (state.isRoadDetected || state.isBenchTestMode))
                  _buildCriticalWarningBanner(context),

                const Spacer(),

                // 4. Bottom Live Diagnostics Strip (Damage Counters & WAL Queue)
                _buildLiveTelemetryStrip(context),

                const SizedBox(height: 6),

                // 5. Glassmorphic Control Dock
                _buildBottomControlDock(context),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 1. Top Telemetry Cockpit Card (Glassmorphic Obsidian #0B0F17 with #00F0FF Neon Cyan border)
  Widget _buildTopCockpitCard(BuildContext context) {
    final bool isBench = state.isBenchTestMode;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xE60B0F17), // Deep Obsidian Glass
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isBench ? AppColors.laserCyan : AppColors.borderGlow,
                width: isBench ? 1.5 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isBench
                      ? AppColors.laserCyan.withValues(alpha: 0.25)
                      : Colors.black.withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left: Digital Speedometer + Mode Toggle Chip
                Expanded(
                  flex: 3,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Speedometer Icon & Value
                      Icon(
                        Icons.speed_rounded,
                        color: isBench ? AppColors.warning : AppColors.laserCyan,
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: state.gpsData.speedKmh.toStringAsFixed(0),
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const TextSpan(
                              text: ' KM/H',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Interactive Mode Toggle Chip: DRIVE vs BENCH TEST
                      GestureDetector(
                        onTap: onToggleBenchMode,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: isBench
                                ? AppColors.laserCyan.withValues(alpha: 0.25)
                                : (state.isLowSpeed
                                    ? AppColors.warning.withValues(alpha: 0.20)
                                    : AppColors.surfaceLight),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isBench
                                  ? AppColors.laserCyan
                                  : (state.isLowSpeed ? AppColors.warning : AppColors.border),
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isBench
                                      ? AppColors.laserCyan
                                      : (state.isLowSpeed ? AppColors.warning : AppColors.successGps),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isBench
                                    ? 'BENCH'
                                    : (state.isLowSpeed ? 'STANDBY' : 'DRIVE'),
                                style: TextStyle(
                                  color: isBench
                                      ? AppColors.laserCyan
                                      : (state.isLowSpeed ? AppColors.warning : AppColors.textPrimary),
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Center: Live AI Engine Core Badge
                Expanded(
                  flex: 4,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E2838), Color(0xFF151C28)],
                          ),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: state.isNativeRustEngine
                                ? AppColors.laserCyan.withValues(alpha: 0.6)
                                : AppColors.border,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.memory_rounded,
                              size: 11,
                              color: state.isNativeRustEngine ? AppColors.laserCyan : AppColors.warning,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              state.isNativeRustEngine
                                  ? 'RUST SIMD + YOLO11n INT8'
                                  : 'DART + YOLO11n INT8',
                              style: TextStyle(
                                color: state.isNativeRustEngine ? AppColors.laserCyan : AppColors.textPrimary,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: state.frameCount % 2 == 0 ? AppColors.successGps : AppColors.successGps.withValues(alpha: 0.35),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.successGps.withValues(alpha: 0.8),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${state.inferenceLatencyMs}ms • ${state.fps.toStringAsFixed(1)} FPS • F#${state.frameCount}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Right: Language Switch & Audio Alert Mute
                Expanded(
                  flex: 3,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Quick Language Switcher Button (AR / EN)
                      GestureDetector(
                        onTap: () => AppLanguageNotifier.instance.toggleLanguage(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.laserCyan.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.laserCyan, width: 0.8),
                          ),
                          child: Text(
                            AppStrings.languageToggleLabel,
                            style: const TextStyle(
                              color: AppColors.laserCyan,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),

                      // GPS Indicator
                      Icon(
                        state.gpsData.isGpsLocked ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
                        color: state.gpsData.isGpsLocked ? AppColors.successGps : AppColors.warning,
                        size: 15,
                      ),
                      const SizedBox(width: 6),

                      // HUD Audio Mute Toggle Button
                      GestureDetector(
                        onTap: onToggleMute,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: state.isMuted
                                ? AppColors.error.withValues(alpha: 0.25)
                                : AppColors.surfaceLight,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: state.isMuted ? AppColors.error : AppColors.border,
                              width: 0.8,
                            ),
                          ),
                          child: Icon(
                            state.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                            color: state.isMuted ? AppColors.error : AppColors.laserCyan,
                            size: 14,
                          ),
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
    );
  }

  Widget _buildDiagnosticErrorBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE62A0D0D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error, width: 1.0),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'PIPELINE WARNING: ${state.lastPipelineError}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFFFB4AB),
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 2. Non-Road Surface Alert Banner (Displayed when surface gate flags laptop, wall, or floor)
  Widget _buildSurfaceGateAlertBanner(BuildContext context) {
    return GestureDetector(
      onTap: onToggleBenchMode,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xCC7F1D1D), // Dark Crimson Glass
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.error, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.error.withValues(alpha: 0.35),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.sensor_occupied_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppStrings.isArabic
                          ? 'بوابة السطح: المشهد غير مطابق للطريق (انقر لتفعيل وضع الفحص)'
                          : 'SURFACE GATE: NON-ROAD SCENE (TAP FOR BENCH TEST)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.laserCyan,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'OVERRIDE',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ).animate().shake(duration: 400.ms, hz: 3).fadeIn(duration: 200.ms),
    );
  }

  /// Scene Intelligence Status Chip
  Widget _buildSceneStatusChip(BuildContext context) {
    final bool isTracking = state.trackedDetections.any((t) => t.isConfirmed);
    final bool hasDetections = state.detections.isNotEmpty;

    String statusText;
    IconData statusIcon;
    Color statusColor;

    if (state.isBenchTestMode) {
      statusText = 'BENCH TEST MODE ACTIVE (OVERRIDE)';
      statusIcon = Icons.science_outlined;
      statusColor = AppColors.laserCyan;
    } else if (isTracking) {
      statusText = AppStrings.sceneTrackingHazard;
      statusIcon = Icons.track_changes_rounded;
      statusColor = AppColors.d40Pothole;
    } else if (hasDetections) {
      statusText = '${state.detections.length} HAZARD(S) IN VIEW';
      statusIcon = Icons.warning_amber_rounded;
      statusColor = AppColors.warning;
    } else {
      statusText = 'ROAD SURFACE OPTIMAL • SCANNING ACTIVE';
      statusIcon = Icons.verified_user_outlined;
      statusColor = AppColors.successGps;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xB30B0F17),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: statusColor.withValues(alpha: 0.5), width: 1.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, color: statusColor, size: 13),
                const SizedBox(width: 6),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Critical Alert Warning Banner
  Widget _buildCriticalWarningBanner(BuildContext context) {
    final alert = state.criticalHazardAlert!;
    final defectName = AppStrings.getDefectName(alert.classId);
    final percent = (alert.confidence * 100).toInt();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.d40Pothole.withValues(alpha: 0.90),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.d40Pothole.withValues(alpha: 0.55),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.emergency_outlined, color: Colors.white, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.criticalHazardTitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppStrings.criticalHazardSubtitle(defectName, percent),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
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

  /// 4. Bottom Live Diagnostics Strip (Damage Counters & WAL Queue)
  Widget _buildLiveTelemetryStrip(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xE60B0F17),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border, width: 0.8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 4 Defect Counters
                _buildClassCounterChip('D00', state.d00Count, AppColors.d00Longitudinal),
                _buildClassCounterChip('D10', state.d10Count, AppColors.d10Transverse),
                _buildClassCounterChip('D20', state.d20Count, AppColors.d20Alligator),
                _buildClassCounterChip('D40', state.d40Count, AppColors.d40Pothole),

                // Peak Severity Gauge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: state.maxSeverityScore > 6.0
                        ? AppColors.d40Pothole.withValues(alpha: 0.25)
                        : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: state.maxSeverityScore > 6.0 ? AppColors.d40Pothole : AppColors.border,
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    'SEV ${state.maxSeverityScore.toStringAsFixed(1)}',
                    style: TextStyle(
                      color: state.maxSeverityScore > 6.0 ? AppColors.d40Pothole : AppColors.laserCyan,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),

                // SQLite WAL Queue Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: state.pendingSyncCount > 0
                        ? AppColors.warning.withValues(alpha: 0.2)
                        : AppColors.successGps.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: state.pendingSyncCount > 0 ? AppColors.warning : AppColors.successGps,
                      width: 0.6,
                    ),
                  ),
                  child: Text(
                    state.pendingSyncCount == 0 ? 'WAL: OK' : 'WAL: ${state.pendingSyncCount}',
                    style: TextStyle(
                      color: state.pendingSyncCount > 0 ? AppColors.warning : AppColors.successGps,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClassCounterChip(String code, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            code,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  /// 5. Bottom Glassmorphic Control Dock
  Widget _buildBottomControlDock(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xE60B0F17),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // 1. Incident Log History Button
                _buildDockButton(
                  icon: Icons.history_rounded,
                  label: AppStrings.isArabic ? 'السجل' : 'History',
                  onTap: onOpenHistory,
                ),

                // 2. Road ROI / Surface Gate Toggle Button
                _buildDockButton(
                  icon: state.isRoadGateEnabled ? Icons.fence_rounded : Icons.crop_free_rounded,
                  label: state.isRoadGateEnabled ? 'Gate: ON' : 'Gate: OFF',
                  color: state.isRoadGateEnabled ? AppColors.laserCyan : AppColors.warning,
                  onTap: onToggleRoadGate,
                ),

                // 3. Central AI Vision Stream Toggle Action
                GestureDetector(
                  onTap: onToggleStreaming,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: state.isStreaming
                            ? [const Color(0xFFEF4444), const Color(0xFFB91C1C)]
                            : [AppColors.laserCyan, const Color(0xFF0090FF)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: (state.isStreaming ? Colors.red : AppColors.laserCyan).withValues(alpha: 0.40),
                          blurRadius: 14,
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
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          state.isStreaming ? 'SCANNING' : 'RESUME',
                          style: TextStyle(
                            color: state.isStreaming ? Colors.white : Colors.black,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 4. Night Vision Torch Toggle Button
                _buildDockButton(
                  icon: state.isTorchOn ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                  label: AppStrings.isArabic ? 'كشاف' : 'Torch',
                  color: state.isTorchOn ? AppColors.warning : AppColors.textSecondary,
                  onTap: onToggleTorch,
                ),

                // 5. Diagnostics & Analytics Dashboard Button
                _buildDockButton(
                  icon: Icons.analytics_outlined,
                  label: AppStrings.isArabic ? 'تحليلات' : 'Analytics',
                  onTap: onOpenAnalytics,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDockButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = AppColors.textPrimary,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}