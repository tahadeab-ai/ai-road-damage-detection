import 'package:equatable/equatable.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/temporal_filter.dart';
import '../../../telemetry/services/gps_service.dart';
import '../../domain/models/detection_result.dart';

class DetectionState extends Equatable {
  final bool isInitialized;
  final bool isStreaming;
  final List<DetectionResult> detections;
  final List<TrackedDetection> trackedDetections;
  final int inferenceLatencyMs;
  final double fps;
  final GpsData gpsData;
  final DetectionResult? criticalHazardAlert;
  final double confidenceThreshold;
  final int totalLoggedCount;
  final bool isMuted;
  final bool isTorchOn;
  final bool isRoadDetected;
  final int sceneStateIndex; // 0: checking, 1: road, 2: nonRoad, 3: detecting, 4: hazardDetected, 5: trackingHazard
  final double maxSeverityScore;
  final String sceneStatusText;
  final bool isNativeRustEngine;
  final bool isBenchTestMode;
  final bool isRoadGateEnabled;
  final bool isArabic;
  final int d00Count;
  final int d10Count;
  final int d20Count;
  final int d40Count;
  final int pendingSyncCount;
  final Failure? failure;

  const DetectionState({
    required this.isInitialized,
    required this.isStreaming,
    required this.detections,
    required this.trackedDetections,
    required this.inferenceLatencyMs,
    required this.fps,
    required this.gpsData,
    this.criticalHazardAlert,
    required this.confidenceThreshold,
    required this.totalLoggedCount,
    this.isMuted = false,
    this.isTorchOn = false,
    this.isRoadDetected = true,
    this.sceneStateIndex = 1,
    this.maxSeverityScore = 0.0,
    this.sceneStatusText = 'OPTIMAL',
    this.isNativeRustEngine = false,
    this.isBenchTestMode = false,
    this.isRoadGateEnabled = true,
    this.isArabic = false,
    this.d00Count = 0,
    this.d10Count = 0,
    this.d20Count = 0,
    this.d40Count = 0,
    this.pendingSyncCount = 0,
    this.failure,
  });

  bool get isLowSpeed => !isBenchTestMode && gpsData.speedKmh < 8.0;
  int get totalHazardsCount => d00Count + d10Count + d20Count + d40Count;

  factory DetectionState.initial() {
    return const DetectionState(
      isInitialized: false,
      isStreaming: false,
      detections: [],
      trackedDetections: [],
      inferenceLatencyMs: 0,
      fps: 0.0,
      gpsData: GpsData.empty,
      criticalHazardAlert: null,
      confidenceThreshold: 0.50,
      totalLoggedCount: 0,
      isMuted: false,
      isTorchOn: false,
      isRoadDetected: true,
      sceneStateIndex: 0,
      maxSeverityScore: 0.0,
      sceneStatusText: 'INITIALIZING',
      isNativeRustEngine: false,
      isBenchTestMode: false,
      isRoadGateEnabled: true,
      isArabic: false,
      d00Count: 0,
      d10Count: 0,
      d20Count: 0,
      d40Count: 0,
      pendingSyncCount: 0,
      failure: null,
    );
  }

  DetectionState copyWith({
    bool? isInitialized,
    bool? isStreaming,
    List<DetectionResult>? detections,
    List<TrackedDetection>? trackedDetections,
    int? inferenceLatencyMs,
    double? fps,
    GpsData? gpsData,
    DetectionResult? Function()? criticalHazardAlert,
    double? confidenceThreshold,
    int? totalLoggedCount,
    bool? isMuted,
    bool? isTorchOn,
    bool? isRoadDetected,
    int? sceneStateIndex,
    double? maxSeverityScore,
    String? sceneStatusText,
    bool? isNativeRustEngine,
    bool? isBenchTestMode,
    bool? isRoadGateEnabled,
    bool? isArabic,
    int? d00Count,
    int? d10Count,
    int? d20Count,
    int? d40Count,
    int? pendingSyncCount,
    Failure? failure,
  }) {
    return DetectionState(
      isInitialized: isInitialized ?? this.isInitialized,
      isStreaming: isStreaming ?? this.isStreaming,
      detections: detections ?? this.detections,
      trackedDetections: trackedDetections ?? this.trackedDetections,
      inferenceLatencyMs: inferenceLatencyMs ?? this.inferenceLatencyMs,
      fps: fps ?? this.fps,
      gpsData: gpsData ?? this.gpsData,
      criticalHazardAlert: criticalHazardAlert != null ? criticalHazardAlert() : this.criticalHazardAlert,
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
      totalLoggedCount: totalLoggedCount ?? this.totalLoggedCount,
      isMuted: isMuted ?? this.isMuted,
      isTorchOn: isTorchOn ?? this.isTorchOn,
      isRoadDetected: isRoadDetected ?? this.isRoadDetected,
      sceneStateIndex: sceneStateIndex ?? this.sceneStateIndex,
      maxSeverityScore: maxSeverityScore ?? this.maxSeverityScore,
      sceneStatusText: sceneStatusText ?? this.sceneStatusText,
      isNativeRustEngine: isNativeRustEngine ?? this.isNativeRustEngine,
      isBenchTestMode: isBenchTestMode ?? this.isBenchTestMode,
      isRoadGateEnabled: isRoadGateEnabled ?? this.isRoadGateEnabled,
      isArabic: isArabic ?? this.isArabic,
      d00Count: d00Count ?? this.d00Count,
      d10Count: d10Count ?? this.d10Count,
      d20Count: d20Count ?? this.d20Count,
      d40Count: d40Count ?? this.d40Count,
      pendingSyncCount: pendingSyncCount ?? this.pendingSyncCount,
      failure: failure ?? this.failure,
    );
  }

  @override
  List<Object?> get props => [
        isInitialized,
        isStreaming,
        detections,
        trackedDetections,
        inferenceLatencyMs,
        fps,
        gpsData,
        criticalHazardAlert,
        confidenceThreshold,
        totalLoggedCount,
        isMuted,
        isTorchOn,
        isRoadDetected,
        sceneStateIndex,
        maxSeverityScore,
        sceneStatusText,
        isNativeRustEngine,
        isBenchTestMode,
        isRoadGateEnabled,
        isArabic,
        d00Count,
        d10Count,
        d20Count,
        d40Count,
        pendingSyncCount,
        failure,
      ];
}
