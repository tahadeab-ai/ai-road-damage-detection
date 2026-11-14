import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  final TemporalFilter _temporalFilter = TemporalFilter();
  final AlertCooldownManager _alertManager = AlertCooldownManager();
  final VeloPathRustBridge _rustBridge = VeloPathRustBridge.instance;

  StreamSubscription<GpsData>? _gpsSubscription;
  bool _isProcessingFrame = false;
  bool _isInitializing = false;
  DateTime _lastFrameTime = DateTime.now();
  int _rawFrameCounter = 0;

  bool get isProcessingFrame => _isProcessingFrame;

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
    on<ToggleBenchTestMode>(_onToggleBenchTest);
    on<ToggleRoadGateMode>(_onToggleRoadGate);
    on<ToggleLanguageMode>(_onToggleLanguage);
    on<ResetHazardCounters>(_onResetCounters);
    on<CycleSampleTestMode>(_onCycleSampleTest);
  }

  void _onToggleBenchTest(
    ToggleBenchTestMode event,
    Emitter<DetectionState> emit,
  ) {
    final nextBenchMode = !state.isBenchTestMode;
    emit(state.copyWith(
      isBenchTestMode: nextBenchMode,
      isRoadGateEnabled: nextBenchMode ? false : true,
      confidenceThreshold: nextBenchMode ? 0.12 : 0.20,
      sceneStatusText: nextBenchMode ? 'BENCH TEST (GATE: OFF)' : 'OPTIMAL',
    ));
  }

  void _onToggleRoadGate(
    ToggleRoadGateMode event,
    Emitter<DetectionState> emit,
  ) {
    emit(state.copyWith(isRoadGateEnabled: !state.isRoadGateEnabled));
  }

  void _onToggleLanguage(
    ToggleLanguageMode event,
    Emitter<DetectionState> emit,
  ) {
    emit(state.copyWith(isArabic: !state.isArabic));
  }

  void _onResetCounters(
    ResetHazardCounters event,
    Emitter<DetectionState> emit,
  ) {
    _rawFrameCounter = 0;
    emit(state.copyWith(
      d00Count: 0,
      d10Count: 0,
      d20Count: 0,
      d40Count: 0,
      frameCount: 0,
    ));
  }

  Future<void> _onCycleSampleTest(
    CycleSampleTestMode event,
    Emitter<DetectionState> emit,
  ) async {
    final int nextMode = (state.sampleTestMode + 1) % 3;
    debugPrint('[SampleTestMode] Cycle triggered -> Mode $nextMode');

    if (nextMode == 0) {
      // Return to Live Camera feed
      debugPrint('[SampleTestMode] Resuming LIVE CAMERA stream.');
      emit(state.copyWith(
        sampleTestMode: 0,
        sampleImagePath: () => null,
        sceneStatusText: 'OPTIMAL',
        detections: [],
        trackedDetections: [],
        criticalHazardAlert: () => null,
      ));
      return;
    }

    final String assetPath = nextMode == 1
        ? 'assets/samples/sample_pothole.jpg'
        : 'assets/samples/sample_cracks.jpg';
    final String modeLabel = nextMode == 1 ? 'SAMPLE 1: POTHOLE (D40)' : 'SAMPLE 2: CRACKS (D00)';

    try {
      if (!tfliteEngine.isInitialized) {
        await tfliteEngine.initialize();
      }

      final byteData = await rootBundle.load(assetPath);
      final rawUint8 = byteData.buffer.asUint8List();

      final codec = await ui.instantiateImageCodec(rawUint8, targetWidth: 512, targetHeight: 512);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final rgbaByteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (rgbaByteData != null) {
        final rgbaBytes = rgbaByteData.buffer.asUint8List();
        final int8Buffer = tfliteEngine.reusableInputBuffer;
        ImageProcessor.rgbaToInt8Tensor512(rgbaBytes, int8Buffer);

        final sw = Stopwatch()..start();
        final detections = await tfliteEngine.runInferenceInt8(
          int8Buffer,
          confThreshold: 0.15,
          iouThreshold: 0.35,
          roadRoiTop: 0.0,
          benchMode: true,
        );
        sw.stop();

        debugPrint('[SampleTestMode] ========================================');
        debugPrint('[SampleTestMode] Loaded $modeLabel from $assetPath in ${sw.elapsedMilliseconds}ms');
        debugPrint('[SampleTestMode] Verified Detections count: ${detections.length}');
        for (final d in detections) {
          debugPrint(
            '[SampleTestMode] >> ${d.className} [Class ${d.classId}] - Conf: ${(d.confidence * 100).toStringAsFixed(1)}% | BBox: [L:${d.normalizedRect.left.toStringAsFixed(3)}, T:${d.normalizedRect.top.toStringAsFixed(3)}, R:${d.normalizedRect.right.toStringAsFixed(3)}, B:${d.normalizedRect.bottom.toStringAsFixed(3)}]',
          );
        }
        debugPrint('[SampleTestMode] ========================================');

        double maxSev = 0.0;
        for (final d in detections) {
          final sev = d.classId == 3 ? (7.0 + 3.0 * d.confidence) : (3.0 + 3.0 * d.confidence);
          if (sev > maxSev) maxSev = sev;
        }

        emit(state.copyWith(
          sampleTestMode: nextMode,
          sampleImagePath: () => assetPath,
          detections: detections,
          trackedDetections: [],
          inferenceLatencyMs: sw.elapsedMilliseconds,
          maxSeverityScore: maxSev,
          sceneStatusText: '🧪 $modeLabel',
          criticalHazardAlert: () => detections.isNotEmpty ? detections.first : null,
        ));
      }
    } catch (e, st) {
      debugPrint('[SampleTestMode] Error testing sample image: $e\n$st');
    }
  }

  Future<void> _onInitialize(
    InitializeDetectionSystem event,
    Emitter<DetectionState> emit,
  ) async {
    if (_isInitializing || state.isInitialized) return;
    _isInitializing = true;
    try {
      // 1. Await ONLY TFLite engine initialization (local asset load, < 50ms)
      await tfliteEngine.initialize();

      // 2. Non-blocking background Rust Bridge initialization
      unawaited(_rustBridge.initialize().catchError((e) {
        debugPrint('[DetectionBloc] Rust init notice: $e');
        return false;
      }));

      // 3. Non-blocking background Hazard repository initialization
      unawaited(hazardRepository.initialize().then((_) {
        if (!isClosed) {
          add(UpdateTelemetryData(state.gpsData));
        }
      }).catchError((e) {
        debugPrint('[DetectionBloc] Hazard repo init notice: $e');
      }));

      // 4. Non-blocking background GPS service initialization & stream subscription
      _gpsSubscription?.cancel();
      _gpsSubscription = gpsService.gpsStream.listen((gpsData) {
        if (!isClosed) {
          add(UpdateTelemetryData(gpsData));
        }
      });
      unawaited(gpsService.initialize().catchError((e) {
        debugPrint('[DetectionBloc] GPS init notice: $e');
      }));

      emit(state.copyWith(
        isInitialized: true,
        isStreaming: true,
        isBenchTestMode: false,
        isRoadGateEnabled: true,
        confidenceThreshold: 0.20,
        totalLoggedCount: 0,
        gpsData: gpsService.currentGpsData,
        isMuted: _alertManager.isMuted,
        isNativeRustEngine: _rustBridge.isNativeLoaded,
        sceneStatusText: 'ROAD SCANNING',
        lastPipelineError: () => null,
      ));
    } catch (e, st) {
      debugPrint('[DetectionBloc] Initialize error: $e\n$st');
      emit(state.copyWith(
        isInitialized: true,
        isStreaming: true,
        isNativeRustEngine: _rustBridge.isNativeLoaded,
        lastPipelineError: () => 'Init: $e',
      ));
    } finally {
      _isInitializing = false;
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
    // Drop frame if sample test mode is active or previous inference is still in-flight
    if (!state.isStreaming || _isProcessingFrame || state.sampleTestMode != 0) return;

    _isProcessingFrame = true;
    _rawFrameCounter++;
    final stopwatch = Stopwatch()..start();
    final now = DateTime.now();
    final double deltaSec = now.difference(_lastFrameTime).inMilliseconds / 1000.0;
    _lastFrameTime = now;
    final double currentFps = deltaSec > 0.005 ? (1.0 / deltaSec).clamp(1.0, 120.0) : 30.0;

    // Immediately emit frame counter before inference so F#1, F#2... ticks guaranteed
    emit(state.copyWith(
      frameCount: _rawFrameCounter,
      fps: double.parse(currentFps.toStringAsFixed(1)),
    ));

    try {
      // Auto-initialize if frame arrives before lifecycle completes
      if (!tfliteEngine.isInitialized) {
        await tfliteEngine.initialize();
      }

      // 1. Direct single-pass conversion to pre-allocated target INT8 tensor (Zero-Heap Allocation)
      final int8Buffer = tfliteEngine.reusableInputBuffer;
      ImageProcessor.cameraImageToInt8Tensor512(event.image, int8Buffer);

      // 2. High-speed Camera Lens Occlusion Check (< 0.05ms)
      if (ImageProcessor.isLensOccludedInt8(int8Buffer)) {
        stopwatch.stop();
        emit(state.copyWith(
          sceneStatusText: '⚠️ CAMERA LENS OCCLUDED',
          detections: [],
          trackedDetections: [],
          inferenceLatencyMs: stopwatch.elapsedMilliseconds,
          fps: double.parse(currentFps.toStringAsFixed(1)),
          lastPipelineError: () => null,
        ));
        return;
      }

      // 3. Road Surface Spectral Gating (Door / Wall / Carpet suppression in DRIVE mode)
      if (state.isRoadGateEnabled && !state.isBenchTestMode) {
        final isRoad = await tfliteEngine.checkRoadSurfaceInt8(int8Buffer, benchMode: false);
        if (!isRoad) {
          stopwatch.stop();
          emit(state.copyWith(
            sceneStatusText: 'SURFACE GATE: NON-ROAD SCENE (PAUSE)',
            detections: [],
            trackedDetections: [],
            inferenceLatencyMs: stopwatch.elapsedMilliseconds,
            fps: double.parse(currentFps.toStringAsFixed(1)),
            lastPipelineError: () => null,
          ));
          return;
        }
      }

      // 4. Zero-allocation high-speed TFLite INT8 inference
      final rawDetections = await tfliteEngine.runInferenceInt8(
        int8Buffer,
        confThreshold: state.confidenceThreshold,
        iouThreshold: 0.35,
        roadRoiTop: state.isBenchTestMode ? 0.0 : 0.20,
        benchMode: state.isBenchTestMode,
      );

      debugPrint('[DetectionBloc] Frame #$_rawFrameCounter TFLite INT8 done in ${stopwatch.elapsedMilliseconds}ms, detections=${rawDetections.length}');

      double maxSeverity = 0.0;
      for (final d in rawDetections) {
        double sev = 3.0;
        switch (d.classId) {
          case 0:
            sev = 2.0 + 2.0 * d.confidence;
            break;
          case 1:
            sev = 3.0 + 2.0 * d.confidence;
            break;
          case 2:
            sev = 5.0 + 3.0 * d.confidence;
            break;
          case 3:
            sev = 7.0 + 3.0 * d.confidence;
            break;
        }
        if (sev > maxSeverity) maxSeverity = sev;
      }

      stopwatch.stop();
      final latencyMs = stopwatch.elapsedMilliseconds;
      final double fps = currentFps;

      // 3. Temporal Tracking & Coordinate EMA Smoothing
      final trackedList = _temporalFilter.processFrame(rawDetections, timestamp: now);

      // 4. Sensory Alert Evaluation
      await _alertManager.evaluateAlerts(
        detections: trackedList,
        currentSpeedKmh: state.isBenchTestMode ? 45.0 : state.gpsData.speedKmh,
        timestamp: now,
      );

      // 5. Check for confirmed critical hazards
      DetectionResult? criticalAlert;
      final criticalTracked = trackedList.where((t) => t.isCritical).toList();
      if (criticalTracked.isNotEmpty) {
        criticalAlert = criticalTracked.first.toDetectionResult();
      }

      // Update defect class cumulative counts (strictly increment for confirmed unique tracks)
      int d00 = state.d00Count;
      int d10 = state.d10Count;
      int d20 = state.d20Count;
      int d40 = state.d40Count;

      // 6. Persist confirmed hazard incidents (Duplicate-free: strictly 1 record per unique track event)
      int loggedCount = state.totalLoggedCount;
      final confirmedTracks = trackedList.where((t) => t.isConfirmed).toList();
      if (confirmedTracks.isNotEmpty) {
        for (final track in confirmedTracks) {
          if (track.hasBeenLogged) continue;
          track.hasBeenLogged = true;

          final det = track.toDetectionResult();

          // Increment class counter strictly once per unique confirmed hazard
          switch (det.classId) {
            case 0:
              d00++;
              break;
            case 1:
              d10++;
              break;
            case 2:
              d20++;
              break;
            case 3:
              d40++;
              break;
          }

          // 100% Guaranteed Evidence snapshot capture from active frame memory
          final snapshotPath = await SnapshotCaptureService.captureHazardSnapshotFromInt8(
            int8Buffer: int8Buffer,
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

      final statusText = state.isBenchTestMode
          ? 'BENCH TEST'
          : (rawDetections.isNotEmpty ? 'HAZARDS DETECTED' : 'ROAD SCANNING');

      emit(state.copyWith(
        isRoadDetected: true,
        detections: rawDetections,
        trackedDetections: List.from(trackedList),
        inferenceLatencyMs: latencyMs,
        fps: double.parse(fps.toStringAsFixed(1)),
        criticalHazardAlert: () => criticalAlert,
        totalLoggedCount: loggedCount,
        maxSeverityScore: maxSeverity,
        sceneStatusText: statusText,
        isNativeRustEngine: _rustBridge.isNativeLoaded,
        d00Count: d00,
        d10Count: d10,
        d20Count: d20,
        d40Count: d40,
        frameCount: _rawFrameCounter,
        pendingSyncCount: _rustBridge.getPendingSyncCount(),
        lastPipelineError: () => null,
      ));
    } catch (e, st) {
      debugPrint('[DetectionBloc] Frame error: $e\n$st');
      stopwatch.stop();
      emit(state.copyWith(
        inferenceLatencyMs: stopwatch.elapsedMilliseconds > 0 ? stopwatch.elapsedMilliseconds : 16,
        fps: double.parse(currentFps.toStringAsFixed(1)),
        isNativeRustEngine: _rustBridge.isNativeLoaded,
        frameCount: _rawFrameCounter,
        lastPipelineError: () => e.toString(),
      ));
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
