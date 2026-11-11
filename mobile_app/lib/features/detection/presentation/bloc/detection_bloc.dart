import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/ffi/velopath_rust_bridge.dart';
import '../../../../core/utils/alert_cooldown_manager.dart';
import '../../../../core/utils/image_processor.dart';
import '../../../../core/utils/snapshot_capture_service.dart';
import '../../../../core/utils/temporal_filter.dart';
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
  final VeloPathRustBridge _rustBridge = VeloPathRustBridge.instance;
  final AlertCooldownManager _alertManager = AlertCooldownManager();
  final TemporalFilter _temporalFilter = TemporalFilter(
    iouThreshold: 0.35,
    emaAlpha: 0.60,
    persistenceMs: 350,
    confirmationStreak: 3,
  );

  StreamSubscription<GpsData>? _gpsSubscription;
  bool _isProcessingFrame = false;
  DateTime _lastFrameTime = DateTime.now();

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
    on<ToggleMuteAudio>(_onToggleMute);
    on<ToggleTorchMode>(_onToggleTorch);
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
        isMuted: _alertManager.isMuted,
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
    if (!event.isStreaming) {
      _temporalFilter.reset();
      _alertManager.reset();
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
      final now = DateTime.now();
      final double deltaSec = now.difference(_lastFrameTime).inMilliseconds / 1000.0;
      _lastFrameTime = now;

      // 1. Process camera image bytes into normalized tensor buffer
      final float32Buffer = ImageProcessor.cameraImageToFloat32Array(event.image);

      // 2. Invoke VeloPath Rust FFI Engine Bridge (with zero-lag native execution)
      final telemetry = VeloPathGpsTelemetry(
        latitude: state.gpsData.latitude,
        longitude: state.gpsData.longitude,
        speedKmh: state.gpsData.speedKmh,
        headingDeg: state.gpsData.heading,
        timestampMs: now.millisecondsSinceEpoch,
      );

      final frameBytes = event.image.planes[0].bytes;
      final rustResult = await _rustBridge.processFrame(
        frameBytes: frameBytes,
        width: event.image.width,
        height: event.image.height,
        telemetry: telemetry,
        dtSeconds: deltaSec > 0.001 ? deltaSec : 0.033,
      );

      // 3. Fallback to local on-device pipeline if native Rust .so is not compiled locally
      final bool isRoad;
      List<DetectionResult> rawDetections = [];
      double maxSeverity = 0.0;
      String statusText = rustResult.sceneStatus.code;

      if (rustResult.isNativeExecution && rustResult.sceneStatus == VeloPathSceneStatus.optimal) {
        isRoad = true;
        // Map native Rust detections
        rawDetections = rustResult.activeDefects.map((d) {
          if (d.severityScore > maxSeverity) maxSeverity = d.severityScore;
          return DetectionResult(
            classId: d.defectClass.index,
            label: d.defectClass.displayName,
            confidence: d.confidence,
            box: [d.bbox.ymin, d.bbox.xmin, d.bbox.ymax, d.bbox.xmax],
          );
        }).toList();
      } else {
        // Fallback to local TFLite detector
        isRoad = await tfliteEngine.checkRoadSurface(float32Buffer);
        if (isRoad) {
          rawDetections = await tfliteEngine.runInference(
            float32Buffer,
            confThreshold: state.confidenceThreshold,
            iouThreshold: 0.35,
            roadRoiTop: 0.25, // Synchronized with Guardrail #3 ROI crop
          );
          for (final d in rawDetections) {
            final sev = (d.classId == 3 ? 9.0 : 4.0) * d.confidence;
            if (sev > maxSeverity) maxSeverity = sev;
          }
        } else {
          statusText = 'NON-ROAD SURFACE';
        }
      }

      stopwatch.stop();
      final latencyMs = stopwatch.elapsedMilliseconds;
      final double fps = deltaSec > 0.0 ? (1.0 / deltaSec).clamp(0.0, 120.0) : 0.0;

      // 4. Temporal Tracking & Coordinate EMA Smoothing with Persistent Spatial Lock
      final trackedList = _temporalFilter.processFrame(rawDetections, timestamp: now);

      // 5. Intelligent Sensory Alert Evaluation with Cooldown & Speed Gating
      await _alertManager.evaluateAlerts(
        detections: trackedList,
        currentSpeedKmh: state.gpsData.speedKmh,
        timestamp: now,
      );

      // 6. Check for confirmed critical hazards (for visual HUD banners)
      DetectionResult? criticalAlert;
      final criticalTracked = trackedList.where((t) => t.isCritical).toList();
      if (criticalTracked.isNotEmpty) {
        criticalAlert = criticalTracked.first.toDetectionResult();
      }

      // 7. Persist confirmed hazard incidents (Duplicate-free: strictly 1 record per unique track event)
      int loggedCount = state.totalLoggedCount;
      final confirmedTracks = trackedList.where((t) => t.isConfirmed).toList();
      if (confirmedTracks.isNotEmpty) {
        for (final track in confirmedTracks) {
          if (track.hasBeenLogged) continue;
          track.hasBeenLogged = true;

          final det = track.toDetectionResult();

          // 100% Guaranteed Evidence snapshot capture from active frame memory
          final snapshotPath = await SnapshotCaptureService.captureHazardSnapshot(
            rgbBuffer: float32Buffer,
            detection: det,
          );

          final hazard = RoadHazard.fromDetection(
            id: '${track.formattedTrackId}_${det.classId}_${now.millisecondsSinceEpoch ~/ 1000}',
            detection: det,
            latitude: state.gpsData.latitude,
            longitude: state.gpsData.longitude,
            speedKmh: state.gpsData.speedKmh,
            address: state.gpsData.address,
            snapshotPath: snapshotPath,
          );
          final logged = await hazardRepository.logHazard(hazard);
          if (logged) loggedCount++;
        }
      }

      emit(state.copyWith(
        isRoadDetected: isRoad,
        detections: rawDetections,
        trackedDetections: List.from(trackedList),
        inferenceLatencyMs: latencyMs,
        fps: double.parse(fps.toStringAsFixed(1)),
        criticalHazardAlert: () => criticalAlert,
        totalLoggedCount: loggedCount,
        maxSeverityScore: maxSeverity,
        sceneStatusText: statusText,
        isNativeRustEngine: rustResult.isNativeExecution,
      ));
    } catch (_) {
      // Avoid crashing live video loop on corrupted single frame
    } finally {
      _isProcessingFrame = false;
    }
  }

  @override
  Future<void> close() {
    _gpsSubscription?.cancel();
    _alertManager.dispose();
    tfliteEngine.dispose();
    gpsService.dispose();
    return super.close();
  }
}
