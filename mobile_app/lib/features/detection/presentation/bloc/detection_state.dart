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
    this.failure,
  });

  bool get isLowSpeed => gpsData.speedKmh < 8.0;

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
      confidenceThreshold: 0.55,
      totalLoggedCount: 0,
      isMuted: false,
      isTorchOn: false,
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
        failure,
      ];
}
