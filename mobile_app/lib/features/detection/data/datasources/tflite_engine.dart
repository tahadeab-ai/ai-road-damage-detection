import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../../../../core/utils/detection_filter.dart';
import '../../../../core/utils/nms_utils.dart';
import '../../../../core/utils/yuv_converter.dart';
import '../../domain/models/detection_result.dart';

/// Enum representing the active hardware delegate tier.
enum TfliteHardwareDelegate {
  gpuV2,
  nnapi,
  xnnpack,
  cpu,
  mockFallback,
}

/// Profiled inference timing breakdown.
class TfliteTimings {
  final int resizeMs;
  final int inferenceMs;
  final int nmsMs;
  final int filterMs;
  final String delegateName;

  const TfliteTimings({
    this.resizeMs = 0,
    this.inferenceMs = 0,
    this.nmsMs = 0,
    this.filterMs = 0,
    this.delegateName = 'unknown',
  });

  int get totalMs => resizeMs + inferenceMs + nmsMs + filterMs;
}

/// Metadata extracted from the loaded TFLite model tensors.
class TfliteModelMeta {
  final int inputSize;
  final int numAnchors;
  final int numClasses;
  final bool channelMajor;
  final double inputScale;
  final int inputZeroPoint;
  final double outputScale;
  final int outputZeroPoint;

  const TfliteModelMeta({
    required this.inputSize,
    required this.numAnchors,
    required this.numClasses,
    required this.channelMajor,
    required this.inputScale,
    required this.inputZeroPoint,
    required this.outputScale,
    required this.outputZeroPoint,
  });
}

/// Production On-Device TFLite Inference Engine for RoadGuard AI V1.2.
///
/// Implements a 4-tier hardware acceleration delegate ladder:
/// - Tier 1: GpuDelegateV2 with dynamic warmup benchmark (rejects if > 1.2x XNNPack)
/// - Tier 2: NnApiDelegate (Android Neural Networks API / NPU)
/// - Tier 3: XNNPackDelegate (4-thread ARM NEON SIMD)
/// - Tier 4: Plain CPU (4 threads)
///
/// Employs zero-allocation YUV-to-INT8 conversion, strict RDD2022 taxonomy filtering
/// (discards out-of-taxonomy classes like Speed Breakers), and geometric boundary filters.
class TfliteEngine {
  static const String defaultModelAssetPath = 'assets/models/best_full_integer_quant.tflite';
  static const String roadGateAssetPath = 'assets/models/road_gate.tflite';
  static const String labelsAssetPath = 'assets/models/labels.txt';

  final String modelAssetPath;
  Interpreter? _interpreter;
  Interpreter? _roadGateInterpreter;
  TfliteModelMeta? _modelMeta;
  TfliteHardwareDelegate _activeDelegate = TfliteHardwareDelegate.cpu;
  List<String> _labels = [];
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  bool get isModelLoaded => _interpreter != null;
  TfliteHardwareDelegate get activeDelegate => _activeDelegate;
  String get activeDelegateName => _activeDelegate.name;
  TfliteModelMeta? get modelMeta => _modelMeta;
  List<String> get labels => List.unmodifiable(_labels);

  TfliteEngine({this.modelAssetPath = defaultModelAssetPath});

  /// Initializes the TFLite inference engine via the 4-tier hardware delegate ladder.
  Future<void> initialize() async {
    if (_isInitialized && _interpreter != null) return;

    // 1. Load taxonomy labels
    try {
      final labelsData = await rootBundle.loadString(labelsAssetPath);
      _labels = labelsData
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {
      _labels = ['Longitudinal Crack', 'Transverse Crack', 'Alligator Crack', 'Pothole'];
    }

    if (_labels.length < 4) {
      _labels = ['Longitudinal Crack', 'Transverse Crack', 'Alligator Crack', 'Pothole'];
    }

    // 2. Load model binary from Flutter asset bundle
    Uint8List modelBytes;
    try {
      final byteData = await rootBundle.load(modelAssetPath);
      modelBytes = byteData.buffer.asUint8List();
    } catch (e) {
      debugPrint('[TfliteEngine] Asset load notice for $modelAssetPath: $e');
      _isInitialized = true;
      return;
    }

    // 3. Execute 4-Tier Delegate Ladder
    bool loaded = false;

    // Tier 1: GPU Delegate V2 with warmup ratio benchmark
    if (Platform.isAndroid) {
      loaded = await _tryLoadGpu(modelBytes);
    }

    // Tier 2: NNAPI Delegate (Android NPU)
    if (!loaded && Platform.isAndroid) {
      loaded = await _tryLoadNnapi(modelBytes);
    }

    // Tier 3: XNNPack Delegate (4-thread ARM NEON SIMD)
    if (!loaded) {
      loaded = await _tryLoadXnnpack(modelBytes);
    }

    // Tier 4: Plain CPU (4 threads)
    if (!loaded) {
      loaded = await _tryLoadPlainCpu(modelBytes);
    }

    if (loaded && _interpreter != null) {
      _modelMeta = _extractMetadata(_interpreter!);
      debugPrint('[TfliteEngine] Successfully loaded via ${_activeDelegate.name} (Meta: inputSize=${_modelMeta?.inputSize}, anchors=${_modelMeta?.numAnchors}, classes=${_modelMeta?.numClasses})');
    }

    // 4. Initialize Road Surface Gatekeeper model (MobileNetV3 binary classifier)
    try {
      final gateByteData = await rootBundle.load(roadGateAssetPath);
      final gateBytes = gateByteData.buffer.asUint8List();
      final gateOpts = InterpreterOptions()..threads = 2;
      _roadGateInterpreter = Interpreter.fromBuffer(gateBytes, options: gateOpts);
      _roadGateInterpreter?.allocateTensors();
    } catch (e) {
      debugPrint('[TfliteEngine] Road gate initialization notice: $e');
    }

    _isInitialized = true;
  }

  Future<bool> _tryLoadGpu(Uint8List modelBytes) async {
    Interpreter? gpuCandidate;
    Interpreter? xnnCandidate;

    try {
      final gpuOpts = InterpreterOptions()..addDelegate(GpuDelegateV2());
      gpuCandidate = Interpreter.fromBuffer(modelBytes, options: gpuOpts);
      gpuCandidate.allocateTensors();

      final meta = _extractMetadata(gpuCandidate);

      // Load XNNPack candidate for dynamic benchmarking comparison
      final xnnOpts = InterpreterOptions()
        ..addDelegate(XNNPackDelegate(options: XNNPackDelegateOptions(numThreads: 4)));
      xnnCandidate = Interpreter.fromBuffer(modelBytes, options: xnnOpts);
      xnnCandidate.allocateTensors();

      // Benchmark single inference on dummy tensor
      final int gpuMs = _benchmarkInterpreter(gpuCandidate, meta);
      final int xnnMs = _benchmarkInterpreter(xnnCandidate, meta);
      debugPrint('[TfliteEngine] Benchmark: GPU=${gpuMs}ms vs XNNPack=${xnnMs}ms (ratio: ${(gpuMs / math.max(xnnMs, 1)).toStringAsFixed(2)})');

      // If GPU execution is slower than 1.2x XNNPack, reject GPU due to INT8 dequantization overhead
      if (gpuMs > xnnMs * 1.2) {
        debugPrint('[TfliteEngine] GPU exceeds XNNPack latency threshold. Retaining XNNPack.');
        gpuCandidate.close();
        _interpreter = xnnCandidate;
        _activeDelegate = TfliteHardwareDelegate.xnnpack;
        return true;
      }

      xnnCandidate.close();
      _interpreter = gpuCandidate;
      _activeDelegate = TfliteHardwareDelegate.gpuV2;
      return true;
    } catch (e) {
      debugPrint('[TfliteEngine] GPU Tier 1 failed: $e');
      gpuCandidate?.close();
      xnnCandidate?.close();
      return false;
    }
  }

  Future<bool> _tryLoadNnapi(Uint8List modelBytes) async {
    try {
      final opts = InterpreterOptions()
        ..useNnApiForAndroid = true
        ..threads = 4;
      final candidate = Interpreter.fromBuffer(modelBytes, options: opts);
      candidate.allocateTensors();
      _interpreter = candidate;
      _activeDelegate = TfliteHardwareDelegate.nnapi;
      return true;
    } catch (e) {
      debugPrint('[TfliteEngine] NNAPI Tier 2 failed: $e');
      return false;
    }
  }

  Future<bool> _tryLoadXnnpack(Uint8List modelBytes) async {
    try {
      final opts = InterpreterOptions()
        ..addDelegate(XNNPackDelegate(options: XNNPackDelegateOptions(numThreads: 4)));
      final candidate = Interpreter.fromBuffer(modelBytes, options: opts);
      candidate.allocateTensors();
      _interpreter = candidate;
      _activeDelegate = TfliteHardwareDelegate.xnnpack;
      return true;
    } catch (e) {
      debugPrint('[TfliteEngine] XNNPack Tier 3 failed: $e');
      return false;
    }
  }

  Future<bool> _tryLoadPlainCpu(Uint8List modelBytes) async {
    try {
      final opts = InterpreterOptions()..threads = 4;
      final candidate = Interpreter.fromBuffer(modelBytes, options: opts);
      candidate.allocateTensors();
      _interpreter = candidate;
      _activeDelegate = TfliteHardwareDelegate.cpu;
      return true;
    } catch (e) {
      debugPrint('[TfliteEngine] Plain CPU Tier 4 failed: $e');
      return false;
    }
  }

  int _benchmarkInterpreter(Interpreter interp, TfliteModelMeta meta) {
    try {
      final dummyInput = Int8List(meta.inputSize * meta.inputSize * 3);
      interp.getInputTensor(0).data.buffer.asUint8List().setAll(0, dummyInput.buffer.asUint8List());
      final sw = Stopwatch()..start();
      interp.invoke();
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return 9999;
    }
  }

  TfliteModelMeta _extractMetadata(Interpreter interp) {
    final inShape = interp.getInputTensor(0).shape;
    final inParams = interp.getInputTensor(0).params;
    final outShape = interp.getOutputTensor(0).shape;
    final outParams = interp.getOutputTensor(0).params;

    final int inputSize = inShape.length >= 3 ? inShape[1] : 640;
    final int dimA = outShape.length >= 3 ? outShape[1] : 9;
    final int dimB = outShape.length >= 3 ? outShape[2] : 8400;

    final bool channelMajor = dimA < dimB;
    final int numAnchors = channelMajor ? dimB : dimA;
    final int numClasses = (channelMajor ? dimA : dimB) - 4;

    return TfliteModelMeta(
      inputSize: inputSize,
      numAnchors: numAnchors,
      numClasses: numClasses,
      channelMajor: channelMajor,
      inputScale: inParams.scale > 0.0 ? inParams.scale : 0.003921568859368563,
      inputZeroPoint: inParams.zeroPoint,
      outputScale: outParams.scale > 0.0 ? outParams.scale : 1.0,
      outputZeroPoint: outParams.zeroPoint,
    );
  }

  /// Runs real-time inference on a raw YUV_420_888 camera frame with zero intermediate allocations.
  Future<(List<DetectionResult>, TfliteTimings)> runInferenceOnYuv({
    required Uint8List yPlane,
    required Uint8List uPlane,
    required Uint8List vPlane,
    required int srcWidth,
    required int srcHeight,
    required int uvRowStride,
    required int uvPixelStride,
    required int yRowStride,
    int sensorOrientation = 90,
    double confThreshold = 0.35,
    double iouThreshold = 0.35,
  }) async {
    if (_interpreter == null || _modelMeta == null) {
      await initialize();
      if (_interpreter == null || _modelMeta == null) {
        return (<DetectionResult>[], const TfliteTimings());
      }
    }

    final meta = _modelMeta!;
    final swResize = Stopwatch()..start();

    // 1. Zero-allocation in-place bilinear rotation and quantization
    final int8Input = YuvConverter.yuv420ToInt8(
      yPlane: yPlane,
      uPlane: uPlane,
      vPlane: vPlane,
      srcWidth: srcWidth,
      srcHeight: srcHeight,
      uvRowStride: uvRowStride,
      uvPixelStride: uvPixelStride,
      yRowStride: yRowStride,
      dstSize: meta.inputSize,
      inputScale: meta.inputScale,
      inputZeroPoint: meta.inputZeroPoint,
      sensorOrientation: sensorOrientation,
    );
    swResize.stop();

    // 2. Feed input tensor and invoke model
    final swInfer = Stopwatch()..start();
    _interpreter!.getInputTensor(0).data.buffer.asUint8List().setAll(0, int8Input.buffer.asUint8List());
    _interpreter!.invoke();
    swInfer.stop();

    // 3. Read output tensor
    final outputTensor = _interpreter!.getOutputTensor(0);
    final swDecode = Stopwatch()..start();

    final List<DetectionResult> candidates = decodeOutputTensor(
      outputTensor: outputTensor,
      meta: meta,
      confThreshold: confThreshold,
      labels: _labels,
    );
    swDecode.stop();

    // 4. Filter candidates via explicit detection safety filters
    final swFilter = Stopwatch()..start();
    final trackingCandidates = DetectionFilter.filterForTracking(candidates);
    final filtered = NmsUtils.performNMS(trackingCandidates, iouThreshold: iouThreshold);
    swFilter.stop();

    final timings = TfliteTimings(
      resizeMs: swResize.elapsedMilliseconds,
      inferenceMs: swInfer.elapsedMilliseconds,
      nmsMs: swDecode.elapsedMilliseconds,
      filterMs: swFilter.elapsedMilliseconds,
      delegateName: _activeDelegate.name,
    );

    return (filtered, timings);
  }

  /// Decodes raw output tensor buffer into candidate [DetectionResult] instances.
  /// Handles both channel-major [1, C+4, N] and anchor-major [1, N, C+4] shapes.
  /// Strictly filters out non-RDD classes (e.g. Speed Breaker = 4).
  static List<DetectionResult> decodeOutputTensor({
    required Tensor outputTensor,
    required TfliteModelMeta meta,
    required double confThreshold,
    required List<String> labels,
  }) {
    final List<DetectionResult> candidates = [];
    final int numAnchors = meta.numAnchors;
    final int numClasses = meta.numClasses;
    final bool channelMajor = meta.channelMajor;
    final double outScale = meta.outputScale;
    final int outZeroPoint = meta.outputZeroPoint;

    // Check if output tensor is INT8 / UINT8 or dequantized Float32
    final isQuantized = outputTensor.type == TensorType.int8 || outputTensor.type == TensorType.uint8;
    final buffer = outputTensor.data.buffer;

    double getValue(int row, int col) {
      final int idx = channelMajor ? (row * numAnchors + col) : (col * (numClasses + 4) + row);
      if (isQuantized) {
        final int rawByte = buffer.asInt8List()[idx];
        return (rawByte - outZeroPoint) * outScale;
      } else {
        return buffer.asFloat32List()[idx];
      }
    }

    for (int a = 0; a < numAnchors; a++) {
      // Find highest class confidence
      int bestClassId = -1;
      double bestScore = 0.0;

      for (int c = 0; c < numClasses; c++) {
        // Enforce strict taxonomy: Discard any class >= 4 (e.g. Speed Breaker = 4)
        if (!DetectionFilter.allowedTaxonomyClasses.contains(c)) {
          continue;
        }

        final score = getValue(4 + c, a);
        if (score > bestScore) {
          bestScore = score;
          bestClassId = c;
        }
      }

      if (bestScore < confThreshold || bestClassId < 0) {
        continue;
      }

      final double cx = getValue(0, a) / meta.inputSize;
      final double cy = getValue(1, a) / meta.inputSize;
      final double w = getValue(2, a) / meta.inputSize;
      final double h = getValue(3, a) / meta.inputSize;

      final double left = (cx - w / 2.0).clamp(0.0, 1.0);
      final double top = (cy - h / 2.0).clamp(0.0, 1.0);
      final double right = (cx + w / 2.0).clamp(0.0, 1.0);
      final double bottom = (cy + h / 2.0).clamp(0.0, 1.0);

      if (right <= left || bottom <= top) continue;

      final className = bestClassId < labels.length ? labels[bestClassId] : 'Road Damage';

      candidates.add(DetectionResult(
        classId: bestClassId,
        className: className,
        confidence: bestScore,
        normalizedRect: Rect.fromLTRB(left, top, right, bottom),
      ));
    }

    return candidates;
  }

  /// Gatekeeper: Binary Road Surface Classifier (Road vs Non-Road).
  Future<bool> checkRoadSurface(Float32List inputBuffer) async {
    if (_roadGateInterpreter != null) {
      try {
        final output = List.generate(1, (_) => List.filled(2, 0.0));
        _roadGateInterpreter!.run(inputBuffer, output);
        final roadProb = output[0][1];
        if (roadProb < 0.50) return false;
      } catch (_) {}
    }
    // Spectral Chrominance check on Road ROI (lower 65% of frame)
    int sampledPixels = 0;
    double totalSaturation = 0.0;
    const int w = 640;
    for (int y = 224; y < 640; y += 16) {
      for (int x = 64; x < 576; x += 16) {
        final int idx = (y * w + x) * 3;
        final double r = inputBuffer[idx];
        final double g = inputBuffer[idx + 1];
        final double b = inputBuffer[idx + 2];
        final double maxC = math.max(r, math.max(g, b));
        final double minC = math.min(r, math.min(g, b));
        final double sat = maxC > 0.001 ? (maxC - minC) / maxC : 0.0;
        totalSaturation += sat;
        sampledPixels++;
      }
    }
    if (sampledPixels == 0) return true;
    final double avgSat = totalSaturation / sampledPixels;
    return avgSat <= 0.45; // Asphalt has low saturation (grey/black)
  }

  void close() {
    _interpreter?.close();
    _roadGateInterpreter?.close();
    _interpreter = null;
    _roadGateInterpreter = null;
    _isInitialized = false;
  }
}
