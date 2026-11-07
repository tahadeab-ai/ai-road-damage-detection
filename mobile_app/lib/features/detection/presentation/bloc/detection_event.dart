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
  final int sensorOrientation;
  final int deviceOrientationAngle;

  const ProcessCameraFrame(
    this.image, {
    this.sensorOrientation = 90,
    this.deviceOrientationAngle = 0,
  });

  @override
  List<Object?> get props => [image, sensorOrientation, deviceOrientationAngle];
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

class RunDiagnosticVerificationPass extends DetectionEvent {
  final int stage; // 1: real road pothole detection, 2: camera occlusion, 3: non-road carpet rejection
  const RunDiagnosticVerificationPass({this.stage = 1});

  @override
  List<Object?> get props => [stage];
}
