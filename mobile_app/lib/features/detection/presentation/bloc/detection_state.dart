import 'package:equatable/equatable.dart';
import '../../../../core/errors/failures.dart';
import '../../../telemetry/services/gps_service.dart';
import '../../domain/models/detection_result.dart';

class DetectionState extends Equatable {
  final bool isInitialized;
  final bool isStreaming;
  final List<DetectionResult> detections;
  final int inferenceLatencyMs;
  final double fps;
  final GpsData gpsData;
  final DetectionResult? criticalHazardAlert;
  final double confidenceThreshold;
  final int totalLoggedCount;
  final Failure? failure;

  const DetectionState({
    required this.isInitialized,
    required this.isStreaming,
    required this.detections,
    required this.inferenceLatencyMs,
    required this.fps,
    required this.gpsData,
    this.criticalHazardAlert,
    required this.confidenceThreshold,
    required this.totalLoggedCount,
    this.failure,
  });

  factory DetectionState.initial() {
    return const DetectionState(
      isInitialized: false,
      isStreaming: false,
      detections: [],
      inferenceLatencyMs: 0,
      fps: 0.0,
      gpsData: GpsData.empty,
      criticalHazardAlert: null,
      confidenceThreshold: 0.35,
      totalLoggedCount: 0,
      failure: null,
    );
  }

  DetectionState copyWith({
    bool? isInitialized,
    bool? isStreaming,
    List<DetectionResult>? detections,
    int? inferenceLatencyMs,
    double? fps,
    GpsData? gpsData,
    DetectionResult? Function()? criticalHazardAlert,
    double? confidenceThreshold,
    int? totalLoggedCount,
    Failure? failure,
  }) {
    return DetectionState(
      isInitialized: isInitialized ?? this.isInitialized,
      isStreaming: isStreaming ?? this.isStreaming,
      detections: detections ?? this.detections,
      inferenceLatencyMs: inferenceLatencyMs ?? this.inferenceLatencyMs,
      fps: fps ?? this.fps,
      gpsData: gpsData ?? this.gpsData,
      criticalHazardAlert: criticalHazardAlert != null ? criticalHazardAlert() : this.criticalHazardAlert,
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
      totalLoggedCount: totalLoggedCount ?? this.totalLoggedCount,
      failure: failure ?? this.failure,
    );
  }

  @override
  List<Object?> get props => [
        isInitialized,
        isStreaming,
        detections,
        inferenceLatencyMs,
        fps,
        gpsData,
        criticalHazardAlert,
        confidenceThreshold,
        totalLoggedCount,
        failure,
      ];
}
