import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/image_processor.dart';
import '../../../history/data/repositories/hazard_repository.dart';
import '../../../telemetry/services/gps_service.dart';
import '../../data/datasources/tflite_engine.dart';
import '../../domain/models/detection_result.dart';
import '../../domain/models/road_hazard.dart';
import 'detection_event.dart';
import 'detection_state.dart';

class DetectionBloc extends Bloc<DetectionEvent, DetectionState> {
  final TfliteEngine tfliteEngine;
  final GpsService gpsService;
  final HazardRepository hazardRepository;
  final AudioPlayer _audioPlayer = AudioPlayer();

  StreamSubscription<GpsData>? _gpsSubscription;
  bool _isProcessingFrame = false;
  DateTime _lastFrameTime = DateTime.now();
  DateTime _lastAlertTime = DateTime.fromMillisecondsSinceEpoch(0);

  DetectionBloc({
    required this.tfliteEngine,
    required this.gpsService,
    required this.hazardRepository,
  }) : super(DetectionState.initial()) {
    on<InitializeDetectionSystem>(_onInitialize);
    on<ProcessCameraFrame>(_onProcessFrame);
    on<UpdateTelemetryData>(_onUpdateTelemetry);
    on<ToggleDetectionStreaming>(_onToggleStreaming);
    on<ChangeConfidenceThreshold>(_onChangeConfidenceThreshold);
  }

  Future<void> _onInitialize(
    InitializeDetectionSystem event,
    Emitter<DetectionState> emit,
  ) async {
    try {
      await tfliteEngine.initialize();
      await hazardRepository.initialize();
      await gpsService.initialize();

      _gpsSubscription?.cancel();
      _gpsSubscription = gpsService.gpsStream.listen((gpsData) {
        add(UpdateTelemetryData(gpsData));
      });

      final totalLogged = hazardRepository.getAllHazards().length;

      emit(state.copyWith(
        isInitialized: true,
        isStreaming: true,
        totalLoggedCount: totalLogged,
        gpsData: gpsService.currentGpsData,
      ));
    } catch (e) {
      // Retain active state with fallback
      emit(state.copyWith(isInitialized: true, isStreaming: true));
    }
  }

  void _onUpdateTelemetry(
    UpdateTelemetryData event,
    Emitter<DetectionState> emit,
  ) {
    emit(state.copyWith(gpsData: event.gpsData));
  }

  void _onToggleStreaming(
    ToggleDetectionStreaming event,
    Emitter<DetectionState> emit,
  ) {
    emit(state.copyWith(
      isStreaming: event.isStreaming,
      detections: event.isStreaming ? state.detections : [],
    ));
  }

  void _onChangeConfidenceThreshold(
    ChangeConfidenceThreshold event,
    Emitter<DetectionState> emit,
  ) {
    emit(state.copyWith(confidenceThreshold: event.threshold));
  }

  Future<void> _onProcessFrame(
    ProcessCameraFrame event,
    Emitter<DetectionState> emit,
  ) async {
    // Drop frame if previous inference is still in-flight to prevent frame queue lag
    if (!state.isStreaming || _isProcessingFrame) return;

    _isProcessingFrame = true;
    final stopwatch = Stopwatch()..start();

    try {
      // 1. Process camera image bytes into normalized tensor buffer
      final float32Buffer = ImageProcessor.cameraImageToFloat32Array(event.image);

      // 2. Execute on-device YOLO11 inference
      final detections = await tfliteEngine.runInference(
        float32Buffer,
        confThreshold: state.confidenceThreshold,
      );

      stopwatch.stop();
      final latencyMs = stopwatch.elapsedMilliseconds;

      // 3. Compute frame rate
      final now = DateTime.now();
      final double deltaSec = now.difference(_lastFrameTime).inMilliseconds / 1000.0;
      _lastFrameTime = now;
      final double fps = deltaSec > 0.0 ? (1.0 / deltaSec).clamp(0.0, 60.0) : 0.0;

      // 4. Critical hazard alert trigger (>65% confidence on Pothole or Alligator crack)
      DetectionResult? criticalAlert;
      final criticalDetections = detections.where((d) => d.isCritical).toList();

      if (criticalDetections.isNotEmpty) {
        criticalAlert = criticalDetections.first;
        // Trigger haptic & chime if 2 seconds elapsed since last alert
        if (now.difference(_lastAlertTime).inSeconds >= 2) {
          _lastAlertTime = now;
          _triggerHazardAlert();
        }
      }

      // 5. Asynchronously persist new hazard incidents to Hive
      int loggedCount = state.totalLoggedCount;
      if (detections.isNotEmpty) {
        for (final det in detections) {
          final hazard = RoadHazard.fromDetection(
            id: '${DateTime.now().millisecondsSinceEpoch}_${det.classId}',
            detection: det,
            latitude: state.gpsData.latitude,
            longitude: state.gpsData.longitude,
            speedKmh: state.gpsData.speedKmh,
            address: state.gpsData.address,
          );
          final logged = await hazardRepository.logHazard(hazard);
          if (logged) loggedCount++;
        }
      }

      emit(state.copyWith(
        detections: detections,
        inferenceLatencyMs: latencyMs,
        fps: double.parse(fps.toStringAsFixed(1)),
        criticalHazardAlert: () => criticalAlert,
        totalLoggedCount: loggedCount,
      ));
    } catch (_) {
      // Avoid crashing live video loop on corrupted single frame
    } finally {
      _isProcessingFrame = false;
    }
  }

  void _triggerHazardAlert() {
    try {
      HapticFeedback.heavyImpact();
      _audioPlayer.play(AssetSource('sounds/alert_chime.wav'), volume: 0.8);
    } catch (_) {}
  }

  @override
  Future<void> close() {
    _gpsSubscription?.cancel();
    _audioPlayer.dispose();
    tfliteEngine.dispose();
    gpsService.dispose();
    return super.close();
  }
}
