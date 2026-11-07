import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import '../../../../core/utils/nms_utils.dart';
import '../../domain/models/detection_result.dart';

/// Supported hardware acceleration providers for ONNX Runtime.
enum HardwareExecutionProvider {
  auto,
  cpu,
  nnapi,
  xnnpack,
}

/// Production On-Device ONNX Inference Engine for YOLO11n 4-class road damage detection.
/// Strictly bound to the RDD2022 4-class taxonomy:
/// Class 0: D00 - Longitudinal Crack
/// Class 1: D10 - Transverse Crack
/// Class 2: D20 - Alligator Crack
/// Class 3: D40 - Pothole
///
/// Input Tensor Contract:  'images'  -> [1, 3, 640, 640] Float32, Normalized [0.0, 1.0]
/// Output Tensor Contract: 'output0' -> [1, 8, 8400] Float32
class OnnxInferenceEngine {
  static const String modelAssetPath = 'assets/models/roadguard-yolo-v1.1.0.onnx';
  static const String labelsAssetPath = 'assets/models/labels.txt';

  static const List<String> authoritativeLabels = [
    'Longitudinal Crack',
    'Transverse Crack',
    'Alligator Crack',
    'Pothole',
  ];

  OrtSession? _session;
  OrtRunOptions? _runOptions;
  List<String> _labels = authoritativeLabels;
  bool _isInitialized = false;
  String _activeProviderName = 'Uninitialized';
  double _lastLatencyMs = 0.0;
  String? _lastError;

  bool get isInitialized => _isInitialized;
  bool get isModelLoaded => _session != null;
  String get activeProviderName => _activeProviderName;
  double get lastInferenceLatencyMs => _lastLatencyMs;
  String? get lastError => _lastError;
  List<String> get labels => _labels;

  /// Initializes ONNX Runtime environment and loads model weights from assets.
  Future<void> initialize({
    HardwareExecutionProvider provider = HardwareExecutionProvider.auto,
    int numThreads = 4,
  }) async {
    if (_isInitialized && _session != null) return;

    try {
      // 1. Initialize ONNX Runtime global environment
      OrtEnv.instance.init();

      // 2. Load class labels from asset bundle or fallback to authoritative taxonomy
      try {
        final labelsData = await rootBundle.loadString(labelsAssetPath);
        final parsed = labelsData
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (parsed.length == 4) {
          _labels = parsed;
        }
      } catch (_) {
        _labels = authoritativeLabels;
      }

      // 3. Configure Session Options & Hardware Execution Providers
      final sessionOptions = OrtSessionOptions();
      sessionOptions.setIntraOpNumThreads(numThreads);
      sessionOptions.setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);

      _activeProviderName = 'CPUExecutionProvider';

      if (Platform.isAndroid) {
        if (provider == HardwareExecutionProvider.nnapi || provider == HardwareExecutionProvider.auto) {
          try {
            final appended = sessionOptions.appendNnapiProvider(NnapiFlags.useNone);
            if (appended) {
              _activeProviderName = 'NnapiExecutionProvider';
            }
          } catch (e) {
            debugPrint('[OnnxEngine] NNAPI notice: $e (retaining CPU provider)');
          }
        } else if (provider == HardwareExecutionProvider.xnnpack) {
          try {
            final appended = sessionOptions.appendXnnpackProvider();
            if (appended) {
              _activeProviderName = 'XnnpackExecutionProvider';
            }
          } catch (e) {
            debugPrint('[OnnxEngine] XNNPACK notice: $e (retaining CPU provider)');
          }
        }
      }

      // 4. Load ONNX model bytes from asset bundle
      final ByteData modelBytes = await rootBundle.load(modelAssetPath);
      final Uint8List rawBytes = modelBytes.buffer.asUint8List(
        modelBytes.offsetInBytes,
        modelBytes.lengthInBytes,
      );

      _session = OrtSession.fromBuffer(rawBytes, sessionOptions);
      _runOptions = OrtRunOptions();
      _isInitialized = true;
      _lastError = null;

      debugPrint('[OnnxEngine] Loaded $modelAssetPath successfully. Provider: $_activeProviderName');
    } catch (e) {
      _lastError = e.toString();
      _isInitialized = false;
      _session = null;
      debugPrint('[OnnxEngine] Initialization failed: $e');
    }
  }

  /// Converts HWC normalized buffer [640, 640, 3] into NCHW tensor buffer [3, 640, 640].
  static Float32List hwcToChw(Float32List hwcBuffer) {
    const int planeSize = 640 * 640;
    final Float32List chw = Float32List(3 * planeSize);

    for (int i = 0; i < planeSize; i++) {
      final int hwcIdx = i * 3;
      chw[i] = hwcBuffer[hwcIdx];                     // Channel 0: R
      chw[planeSize + i] = hwcBuffer[hwcIdx + 1];     // Channel 1: G
      chw[2 * planeSize + i] = hwcBuffer[hwcIdx + 2]; // Channel 2: B
    }
    return chw;
  }

  /// Runs real ONNX inference on a normalized [640, 640, 3] Float32 buffer.
  /// If the model is not loaded or fails, returns EMPTY list [] and logs error.
  /// NEVER generates synthetic or mock detections.
  Future<List<DetectionResult>> runInference(
    Float32List hwcBuffer, {
    double confThreshold = 0.45,
    double iouThreshold = 0.40,
    double roadRoiTop = 0.35,
  }) async {
    if (!_isInitialized || _session == null) {
      debugPrint('[OnnxEngine] runInference aborted: Model is not initialized. Returning empty detections.');
      return [];
    }

    final stopwatch = Stopwatch()..start();

    try {
      // 1. Transpose HWC buffer to NCHW [1, 3, 640, 640]
      final Float32List chwData = hwcToChw(hwcBuffer);

      // 2. Create OrtValueTensor
      final inputOrt = OrtValueTensor.createTensorWithDataList(
        chwData,
        [1, 3, 640, 640],
      );

      // 3. Execute inference
      final outputs = _session!.run(_runOptions!, {'images': inputOrt});
      inputOrt.release();

      stopwatch.stop();
      _lastLatencyMs = stopwatch.elapsedMilliseconds.toDouble();

      if (outputs.isEmpty || outputs[0] == null) {
        return [];
      }

      // 4. Output shape is [1, 8, 8400]
      final dynamic rawValue = outputs[0]!.value;
      outputs[0]!.release();

      if (rawValue is List && rawValue.isNotEmpty) {
        final List<List<double>> outputMatrix = (rawValue[0] as List)
            .map((row) => (row as List).map((v) => (v as num).toDouble()).toList())
            .toList();

        return decodeYoloOutput(
          outputMatrix,
          labels: _labels,
          confThreshold: confThreshold,
          iouThreshold: iouThreshold,
          roadRoiTop: roadRoiTop,
        );
      }

      return [];
    } catch (e) {
      stopwatch.stop();
      _lastLatencyMs = stopwatch.elapsedMilliseconds.toDouble();
      _lastError = e.toString();
      debugPrint('[OnnxEngine] Inference execution notice: $e');
      return []; // Strict zero-fabrication contract: return empty list on error
    }
  }

  /// Decodes raw YOLO11 tensor matrix [8, 8400] into bounding boxes and applies NMS.
  /// Handles both Ultralytics raw pixel coordinates [0, 640] and normalized [0, 1] bounds.
  static List<DetectionResult> decodeYoloOutput(
    List<List<double>> outputMatrix, {
    List<String> labels = authoritativeLabels,
    required double confThreshold,
    required double iouThreshold,
    required double roadRoiTop,
  }) {
    if (outputMatrix.length < 8) return [];

    final List<DetectionResult> candidates = [];
    final int numPredictions = outputMatrix[0].length; // 8400

    for (int i = 0; i < numPredictions; i++) {
      double rawCx = outputMatrix[0][i];
      double rawCy = outputMatrix[1][i];
      double rawW = outputMatrix[2][i];
      double rawH = outputMatrix[3][i];

      // Convert from pixel space [0, 640] to normalized [0, 1] if needed
      final double cx = (rawCx > 1.0 || rawCy > 1.0 || rawW > 1.0 || rawH > 1.0) ? (rawCx / 640.0) : rawCx;
      final double cy = (rawCx > 1.0 || rawCy > 1.0 || rawW > 1.0 || rawH > 1.0) ? (rawCy / 640.0) : rawCy;
      final double w = (rawCx > 1.0 || rawCy > 1.0 || rawW > 1.0 || rawH > 1.0) ? (rawW / 640.0) : rawW;
      final double h = (rawCx > 1.0 || rawCy > 1.0 || rawW > 1.0 || rawH > 1.0) ? (rawH / 640.0) : rawH;

      // Road ROI Filter: Suppress detections whose center is above the road horizon (top 35% is sky/ceiling)
      if (cy < roadRoiTop) {
        continue;
      }

      // Find highest class confidence among the 4 authoritative damage classes
      double maxScore = -1.0;
      int bestClassId = -1;

      for (int c = 0; c < 4; c++) {
        final double score = outputMatrix[4 + c][i];
        if (score > maxScore) {
          maxScore = score;
          bestClassId = c;
        }
      }

      if (maxScore >= confThreshold && bestClassId >= 0) {
        final double left = (cx - (w / 2.0)).clamp(0.0, 1.0);
        final double top = (cy - (h / 2.0)).clamp(0.0, 1.0);
        final double right = (cx + (w / 2.0)).clamp(0.0, 1.0);
        final double bottom = (cy + (h / 2.0)).clamp(0.0, 1.0);

        final className = bestClassId < labels.length ? labels[bestClassId] : 'Hazard #$bestClassId';

        candidates.add(
          DetectionResult(
            classId: bestClassId,
            className: className,
            confidence: maxScore,
            normalizedRect: Rect.fromLTRB(left, top, right, bottom),
          ),
        );
      }
    }

    // Apply Non-Maximum Suppression
    return NmsUtils.performNMS(
      candidates,
      iouThreshold: iouThreshold,
      confThreshold: confThreshold,
    );
  }

  void dispose() {
    _session?.release();
    _session = null;
    _runOptions?.release();
    _runOptions = null;
    _isInitialized = false;
  }
}
