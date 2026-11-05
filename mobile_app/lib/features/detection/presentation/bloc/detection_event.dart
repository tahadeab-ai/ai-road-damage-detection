import 'package:camera/camera.dart';
import 'package:equatable/equatable.dart';
import '../../../telemetry/services/gps_service.dart';

abstract class DetectionEvent extends Equatable {
  const DetectionEvent();

  @override
  List<Object?> get props => [];
}

class InitializeDetectionSystem extends DetectionEvent {}

class ProcessCameraFrame extends DetectionEvent {
  final CameraImage image;

  const ProcessCameraFrame(this.image);

  @override
  List<Object?> get props => [image];
}

class UpdateTelemetryData extends DetectionEvent {
  final GpsData gpsData;

  const UpdateTelemetryData(this.gpsData);

  @override
  List<Object?> get props => [gpsData];
}

class ToggleDetectionStreaming extends DetectionEvent {
  final bool isStreaming;

  const ToggleDetectionStreaming(this.isStreaming);

  @override
  List<Object?> get props => [isStreaming];
}

class ChangeConfidenceThreshold extends DetectionEvent {
  final double threshold;

  const ChangeConfidenceThreshold(this.threshold);

  @override
  List<Object?> get props => [threshold];
}

class ToggleMuteAudio extends DetectionEvent {}

class ToggleTorchMode extends DetectionEvent {}
