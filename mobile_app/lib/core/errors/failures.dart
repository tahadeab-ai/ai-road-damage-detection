import 'package:equatable/equatable.dart';

/// Base Failure class conforming to Clean Architecture.
abstract class Failure extends Equatable {
  final String message;
  final String? code;

  const Failure(this.message, {this.code});

  @override
  List<Object?> get props => [message, code];
}

class CameraFailure extends Failure {
  const CameraFailure(super.message, {super.code});
}

class ModelInferenceFailure extends Failure {
  const ModelInferenceFailure(super.message, {super.code});
}

class TelemetryFailure extends Failure {
  const TelemetryFailure(super.message, {super.code});
}

class StorageFailure extends Failure {
  const StorageFailure(super.message, {super.code});
}

class PermissionFailure extends Failure {
  const PermissionFailure(super.message, {super.code});
}
