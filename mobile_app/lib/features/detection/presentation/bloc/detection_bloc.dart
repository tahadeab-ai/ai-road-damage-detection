import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/alert_cooldown_manager.dart';
import '../../../../core/utils/camera_occlusion_detector.dart';
import '../../../../core/utils/detection_filter.dart';
import '../../../../core/utils/image_processor.dart';
import '../../../../core/utils/road_surface_gate.dart';
import '../../../../core/utils/snapshot_capture_service.dart';
import '../../../../core/utils/temporal_filter.dart';
import '../../../history/data/repositories/hazard_repository.dart';
import '../../../telemetry/services/gps_service.dart';
import '../../data/datasources/onnx_inference_engine.dart';
import '../../data/datasources/tflite_engine.dart';
import '../../domain/models/detection_result.dart';
import '../../domain/models/road_hazard.dart';
import 'detection_event.dart';
import 'detection_state.dart';

/// Debug flag: Set to true only during development benchmarking or regression validation.
/// In production and release builds, TFLite is the exclusive inference path.
const bool kDebugUseOnnx = false;

/// Production ADAS Detection BLoC for RoadGuard AI V1.2.
/// Coordinates orientation-aware preprocessing, camera occlusion gating,
/// multi-color-space road surface verification, real-time TFLite model inference,
/// time-based tracking, and offline incident logging with nullable GPS.
class DetectionBloc extends Bloc<DetectionEvent, DetectionState> {
  final TfliteEngine tfliteEngine;
  final OnnxInferenceEngine? debugOnnxEngine;
  final GpsService gpsService;
  final HazardRepository hazardRepository;
  final AlertCooldownManager _alertManager = AlertCooldownManager();
  final RoadSurfaceGate _roadSurfaceGate = RoadSurfaceGate(historySize: 5);
  final TemporalFilter _temporalFilter = TemporalFilter(
    iouThreshold: 0.35,
    emaAlpha: 0.65,
    confirmationWindowMs: 150,
    lostGraceThresholdMs: 800,
    removalGraceThresholdMs: 3000,
  );

  StreamSubscription<GpsData>? _gpsSubscription;
  bool _isProcessingFrame = false;
  DateTime _lastFrameTime = DateTime.now();

  DetectionBloc({
    required this.tfliteEngine,
    this.debugOnnxEngine,
    required this.gpsService,
    required this.hazardRepository,
  }) : super(DetectionState.initial()) {
    on<InitializeDetectionSystem>(_onInitialize);
    on<ProcessCameraFrame>(_onProcessFrame);
    on<UpdateTelemetryData>(_onUpdateTelemetry);
    on<ToggleDetectionStreaming>(_onToggleStreaming);
    on<ChangeConfidenceThreshold>(_onChangeConfidenceThreshold);
    on<ToggleMuteAudio>(_onToggleMute);
    on<ToggleTorchMode>(_onToggleTorch);
  }

  Future<void> _onInitialize(
    InitializeDetectionSystem event,
    Emitter<DetectionState> emit,
  ) async {
    try {
      // 1. Initialize primary on-device TFLite engine via 4-tier delegate ladder
      await tfliteEngine.initialize();

      // Debug-only engine initialization
      if (kDebugUseOnnx && debugOnnxEngine != null) {
        await debugOnnxEngine!.initialize(provider: HardwareExecutionProvider.cpu, numThreads: 4);
      }

      // 2. Initialize secondary subsystems
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
        isMuted: _alertManager.isMuted,
      ));
    } catch (e) {
      debugPrint('[DetectionBloc] Initialization notice: $e');
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
    if (!event.isStreaming) {
      _temporalFilter.reset();
      _alertManager.reset();
      _roadSurfaceGate.reset();
    }
    emit(state.copyWith(
      isStreaming: event.isStreaming,
      detections: event.isStreaming ? state.detections : [],
      trackedDetections: event.isStreaming ? state.trackedDetections : [],
    ));
  }

  void _onChangeConfidenceThreshold(
    ChangeConfidenceThreshold event,
    Emitter<DetectionState> emit,
  ) {
    emit(state.copyWith(confidenceThreshold: event.threshold));
  }

  void _onToggleMute(
    ToggleMuteAudio event,
    Emitter<DetectionState> emit,
  ) {
    _alertManager.toggleMute();
    emit(state.copyWith(isMuted: _alertManager.isMuted));
  }

  void _onToggleTorch(
    ToggleTorchMode event,
    Emitter<DetectionState> emit,
  ) {
    emit(state.copyWith(isTorchOn: !state.isTorchOn));
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
      final sw0 = Stopwatch()..start();
      // 1. Orientation-Aware Preprocessing in background Dart Isolate
      final float32Buffer = await ImageProcessor.preprocessInIsolate(
        event.image,
        sensorOrientation: event.sensorOrientation,
        deviceOrientationAngle: event.deviceOrientationAngle,
      );
      final tPre = sw0.elapsedMilliseconds;

      final sw1 = Stopwatch()..start();
      // 2. Camera Occlusion Guard (32x32 variance grid)
      final occlusion = CameraOcclusionDetector.checkOcclusion(float32Buffer);
      final double tOccMs = sw1.elapsedMicroseconds / 1000.0;

      if (occlusion.isOccluded) {
        stopwatch.stop();
        final now = DateTime.now();
        final double deltaSec = now.difference(_lastFrameTime).inMilliseconds / 1000.0;
        _lastFrameTime = now;
        final double fps = deltaSec > 0.0 ? (1.0 / deltaSec).clamp(0.0, 60.0) : 0.0;

        debugPrint('[Occlusion] Camera Obstructed: ${occlusion.reason} (computed in ${tOccMs.toStringAsFixed(2)}ms)');

        emit(state.copyWith(
          isRoadDetected: false,
          sceneStateIndex: 6, // Camera Obstructed
          detections: [],
          trackedDetections: [],
          criticalHazardAlert: () => null,
          inferenceLatencyMs: stopwatch.elapsedMilliseconds,
          fps: double.parse(fps.toStringAsFixed(1)),
        ));
        return;
      }

      final sw2 = Stopwatch()..start();
      // 3. Deterministic Road Surface Gatekeeper
      final roadEval = _roadSurfaceGate.evaluateSurface(float32Buffer, occlusion: occlusion);
      final double tGateMs = sw2.elapsedMicroseconds / 1000.0;

      if (!roadEval.status.isTraversableRoad) {
        stopwatch.stop();
        final now = DateTime.now();
        final double deltaSec = now.difference(_lastFrameTime).inMilliseconds / 1000.0;
        _lastFrameTime = now;
        final double fps = deltaSec > 0.0 ? (1.0 / deltaSec).clamp(0.0, 60.0) : 0.0;

        debugPrint('[RoadGate] Non-Road Surface Rejected: ${roadEval.rejectionReason} (computed in ${tGateMs.toStringAsFixed(2)}ms)');

        emit(state.copyWith(
          isRoadDetected: false,
          sceneStateIndex: roadEval.status == RoadSurfaceStatus.checking ? 0 : 2,
          detections: [],
          trackedDetections: [],
          criticalHazardAlert: () => null,
          inferenceLatencyMs: stopwatch.elapsedMilliseconds,
          fps: double.parse(fps.toStringAsFixed(1)),
        ));
        return;
      }

      final sw3 = Stopwatch()..start();
      // 4. Primary TFLite On-Device Inference
      List<DetectionResult> rawDetections = [];
      String delegateUsed = tfliteEngine.activeDelegateName;

      if (event.image.planes.length >= 3 && tfliteEngine.isModelLoaded) {
        final (tfliteDetections, timings) = await tfliteEngine.runInferenceOnYuv(
          yPlane: event.image.planes[0].bytes,
          uPlane: event.image.planes[1].bytes,
          vPlane: event.image.planes[2].bytes,
          srcWidth: event.image.width,
          srcHeight: event.image.height,
          yRowStride: event.image.planes[0].bytesPerRow,
          uvRowStride: event.image.planes[1].bytesPerRow,
          uvPixelStride: event.image.planes[1].bytesPerPixel ?? 1,
          sensorOrientation: event.sensorOrientation,
          confThreshold: state.confidenceThreshold,
          iouThreshold: 0.35,
        );
        rawDetections = tfliteDetections;
        delegateUsed = timings.delegateName;
      } else if (kDebugUseOnnx && debugOnnxEngine != null && debugOnnxEngine!.isModelLoaded) {
        rawDetections = await debugOnnxEngine!.runInference(
          float32Buffer,
          confThreshold: state.confidenceThreshold,
          iouThreshold: 0.35,
          roadRoiTop: 0.35,
        );
        delegateUsed = 'onnx-debug';
      }
      final tInfer = sw3.elapsedMilliseconds;
      stopwatch.stop();

      final latencyMs = stopwatch.elapsedMilliseconds;
      debugPrint('[Profiling] Total: ${latencyMs}ms (Pre: ${tPre}ms, Occ: ${tOccMs.toStringAsFixed(2)}ms, Gate: ${tGateMs.toStringAsFixed(2)}ms, Infer [$delegateUsed]: ${tInfer}ms)');

      if (rawDetections.isNotEmpty) {
        for (final d in rawDetections) {
          debugPrint('[RealDetection] Class: ${d.classId} (${d.className}), Conf: ${(d.confidence * 100).toStringAsFixed(1)}%, Box: [${d.normalizedRect.left.toStringAsFixed(3)}, ${d.normalizedRect.top.toStringAsFixed(3)}, ${d.normalizedRect.right.toStringAsFixed(3)}, ${d.normalizedRect.bottom.toStringAsFixed(3)}]');
        }
      }

      // 5. Compute frame rate
      final now = DateTime.now();
      final double deltaSec = now.difference(_lastFrameTime).inMilliseconds / 1000.0;
      _lastFrameTime = now;
      final double fps = deltaSec > 0.0 ? (1.0 / deltaSec).clamp(0.0, 60.0) : 0.0;

      // 6. Time-based Temporal Tracking with Ego-Motion & Appearance Re-ID
      final bool isGpsDegraded = !state.gpsData.isGpsLocked ||
          (state.gpsData.latitude == 0.0 && state.gpsData.longitude == 0.0);
      final double speedMps = state.gpsData.speedKmh / 3.6;

      final trackedList = _temporalFilter.processFrame(
        rawDetections,
        timestamp: now,
        rgbBuffer: float32Buffer,
        speedMps: speedMps,
        isGpsDegraded: isGpsDegraded,
      );

      // 7. Intelligent Sensory Alert Evaluation with Cooldown & Speed Gating
      if (state.gpsData.speedKmh <= 8.0) {
        await _alertManager.evaluateAlerts(
          detections: trackedList,
          currentSpeedKmh: state.gpsData.speedKmh,
          timestamp: now,
        );
      }

      // 8. Check for confirmed critical hazards
      DetectionResult? criticalAlert;
      final criticalTracked = trackedList.where((t) => t.isCritical).toList();
      if (criticalTracked.isNotEmpty) {
        criticalAlert = criticalTracked.first.toDetectionResult();
      }

      // 9. Persist confirmed hazard incidents with nullable GPS (Offline-first)
      // Removes previous GPS-suppression block: persists even when GPS is cold/null
      int loggedCount = state.totalLoggedCount;
      final confirmedTracks = trackedList.where((t) => t.isConfirmed).toList();
      if (confirmedTracks.isNotEmpty) {
        for (final track in confirmedTracks) {
          if (track.hasBeenLogged) continue;
          track.hasBeenLogged = true;

          final det = track.toDetectionResult();

          // Apply explicit logging filter floor
          final logEval = DetectionFilter.evaluate(
            rect: det.normalizedRect,
            classId: det.classId,
            confidence: det.confidence,
          );
          if (!logEval.isValidForLogging) continue;

          final snapshotPath = await SnapshotCaptureService.captureHazardSnapshot(
            rgbBuffer: float32Buffer,
            detection: det,
          );

          final hazard = RoadHazard.fromDetection(
            id: '${track.formattedTrackId}_${det.classId}_${now.millisecondsSinceEpoch ~/ 1000}',
            detection: det,
            latitude: state.gpsData.isGpsLocked ? state.gpsData.latitude : null,
            longitude: state.gpsData.isGpsLocked ? state.gpsData.longitude : null,
            speedKmh: state.gpsData.speedKmh,
            address: state.gpsData.address,
            snapshotPath: snapshotPath,
            roadXMeters: track.roadCoordsMeters?.dx,
            roadYMeters: track.roadCoordsMeters?.dy,
          );

          final logged = await hazardRepository.persistHazardAtomically(hazard: hazard);
          if (logged) loggedCount++;
        }
      }

      // 10. Update scene state index
      int sceneIdx = 1; // 1: road verified
      if (trackedList.any((t) => t.isConfirmed)) {
        sceneIdx = 5; // 5: trackingHazard
      } else if (rawDetections.isNotEmpty) {
        sceneIdx = 4; // 4: hazardDetected
      }

      emit(state.copyWith(
        isRoadDetected: true,
        sceneStateIndex: sceneIdx,
        detections: rawDetections,
        trackedDetections: trackedList,
        criticalHazardAlert: () => criticalAlert,
        inferenceLatencyMs: stopwatch.elapsedMilliseconds,
        fps: double.parse(fps.toStringAsFixed(1)),
        totalLoggedCount: loggedCount,
      ));
    } catch (e, st) {
      debugPrint('[DetectionBloc] Frame processing error: $e\n$st');
    } finally {
      _isProcessingFrame = false;
    }
  }

  @override
  Future<void> close() {
    _gpsSubscription?.cancel();
    _alertManager.dispose();
    tfliteEngine.close();
    debugOnnxEngine?.dispose();
    return super.close();
  }
}
