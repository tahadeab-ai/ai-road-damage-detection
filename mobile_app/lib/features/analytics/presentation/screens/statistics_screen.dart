import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../detection/presentation/bloc/detection_state.dart';

class StatisticsScreen extends StatelessWidget {
  final DetectionState state;

  const StatisticsScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final int totalDefects = state.d00Count + state.d10Count + state.d20Count + state.d40Count;
    final double qualityIndex = (100.0 - (totalDefects * 3.5)).clamp(15.0, 100.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xE60B0F17),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.laserCyan, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'FLEET TELEMETRY ANALYTICS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Road Quality Index Hero Card
              _buildQualityIndexCard(qualityIndex, totalDefects),

              const SizedBox(height: 16),

              // 2. Telemetry Grid (FPS, Latency, Speed, Max Sev)
              _buildTelemetryGrid(),

              const SizedBox(height: 20),

              // 3. Defect Taxonomy Breakdown
              const Text(
                'RDD2022 DEFECT TAXONOMY BREAKDOWN',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 10),
              _buildDefectBreakdownCard(totalDefects),

              const SizedBox(height: 20),

              // 4. System & Edge Runtime Status
              const Text(
                'EDGE RUNTIME ARCHITECTURE',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 10),
              _buildRuntimeStatusCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQualityIndexCard(double qualityIndex, int totalDefects) {
    Color qualityColor = AppColors.successGps;
    String qualityRating = 'EXCELLENT';
    if (qualityIndex < 50.0) {
      qualityColor = AppColors.d40Pothole;
      qualityRating = 'CRITICAL ATTENTION REQUIRED';
    } else if (qualityIndex < 75.0) {
      qualityColor = AppColors.warning;
      qualityRating = 'MODERATE DEGRADATION';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xE6151C28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: qualityColor.withValues(alpha: 0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: qualityColor.withValues(alpha: 0.15),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ROAD SURFACE HEALTH INDEX',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: qualityColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  qualityRating,
                  style: TextStyle(
                    color: qualityColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '${qualityIndex.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: qualityColor,
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$totalDefects Detected Incidents Logged',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Monitored over ${state.gpsData.speedKmh.toStringAsFixed(0)} KM/H live GPS roadway traversal',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryGrid() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.8,
      children: [
        _buildMetricTile('INFERENCE LATENCY', '${state.inferenceLatencyMs} ms', Icons.speed_rounded, AppColors.laserCyan),
        _buildMetricTile('VISION FRAMERATE', '${state.fps.toStringAsFixed(1)} FPS', Icons.camera_enhance_rounded, AppColors.laserCyan),
        _buildMetricTile('PEAK SEVERITY', '${state.maxSeverityScore.toStringAsFixed(1)} / 10', Icons.priority_high_rounded, AppColors.d40Pothole),
        _buildMetricTile('ROADWAY SPEED', '${state.gpsData.speedKmh.toStringAsFixed(0)} KM/H', Icons.navigation_rounded, AppColors.successGps),
      ],
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xE6151C28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              Icon(icon, color: color, size: 16),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 19,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefectBreakdownCard(int total) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xE6151C28),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        children: [
          _buildDefectRow('D00', 'Longitudinal Crack', state.d00Count, total, AppColors.d00Longitudinal),
          const Divider(color: AppColors.border, height: 18),
          _buildDefectRow('D10', 'Transverse Crack', state.d10Count, total, AppColors.d10Transverse),
          const Divider(color: AppColors.border, height: 18),
          _buildDefectRow('D20', 'Alligator Crack', state.d20Count, total, AppColors.d20Alligator),
          const Divider(color: AppColors.border, height: 18),
          _buildDefectRow('D40', 'Pothole (Severe)', state.d40Count, total, AppColors.d40Pothole),
        ],
      ),
    );
  }

  Widget _buildDefectRow(String code, String name, int count, int total, Color color) {
    final double ratio = total > 0 ? (count / total) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    code,
                    style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  name,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: ratio,
          backgroundColor: AppColors.surfaceLight,
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 4,
          borderRadius: BorderRadius.circular(2),
        ),
      ],
    );
  }

  Widget _buildRuntimeStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xE6151C28),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        children: [
          _buildStatusRow(
            'Inference Acceleration',
            state.isNativeRustEngine ? 'Rust Core SIMD + NEON' : 'TFLite NNAPI GPU Delegate',
            AppColors.laserCyan,
          ),
          const SizedBox(height: 10),
          _buildStatusRow('Active Weights', 'YOLO11n RDD2022 INT8 QAT (3.2 MB)', Colors.white),
          const SizedBox(height: 10),
          _buildStatusRow(
            'Operational Mode',
            state.isBenchTestMode ? 'BENCH TEST (Override 0 KM/H)' : 'AUTOMOTIVE DRIVE MODE',
            state.isBenchTestMode ? AppColors.warning : AppColors.successGps,
          ),
          const SizedBox(height: 10),
          _buildStatusRow(
            'SQLite WAL Deduplication',
            state.pendingSyncCount == 0 ? 'SYNCHRONIZED (0 Pending)' : '${state.pendingSyncCount} Items Queued',
            state.pendingSyncCount == 0 ? AppColors.successGps : AppColors.warning,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        Text(
          value,
          style: TextStyle(color: valueColor, fontSize: 11, fontWeight: FontWeight.w800, fontFamily: 'monospace'),
        ),
      ],
    );
  }
}
