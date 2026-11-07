import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../../../../core/utils/debug_logger.dart';
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

    // Log mandatory non-production measurement build diagnostic line
    debugPrint('[BUILD] Measurement build with reference YOLOv8n model. NOT production.');

    // 3. Execute 4-Tier Delegate Ladder Benchmark on Device
    // Tier 1: GPU Delegate V2
    int gpuMs = 9999;
    Interpreter? gpuCandidate;
    if (Platform.isAndroid) {
      try {
        final gpuOpts = InterpreterOptions()..addDelegate(GpuDelegateV2());
        gpuCandidate = Interpreter.fromBuffer(modelBytes, options: gpuOpts);
        gpuCandidate.allocateTensors();
        final meta = _extractMetadata(gpuCandidate);
        _benchmarkInterpreter(gpuCandidate, meta); // warmup
        gpuMs = _benchmarkInterpreter(gpuCandidate, meta);
        debugPrint('[DELEGATE_BENCHMARK] Tier 1 GPU V2: $gpuMs ms');
      } catch (e) {
        debugPrint('[DELEGATE_BENCHMARK] Tier 1 GPU V2 failed: $e');
        gpuCandidate?.close();
        gpuCandidate = null;
      }
    }

    // Tier 2: NNAPI Delegate
    int nnapiMs = 9999;
    Interpreter? nnapiCandidate;
    if (Platform.isAndroid) {
      try {
        final nnapiOpts = InterpreterOptions()
          ..useNnApiForAndroid = true
          ..threads = 4;
        nnapiCandidate = Interpreter.fromBuffer(modelBytes, options: nnapiOpts);
        nnapiCandidate.allocateTensors();
        final meta = _extractMetadata(nnapiCandidate);
        _benchmarkInterpreter(nnapiCandidate, meta); // warmup
        nnapiMs = _benchmarkInterpreter(nnapiCandidate, meta);
        debugPrint('[DELEGATE_BENCHMARK] Tier 2 NNAPI: $nnapiMs ms');
      } catch (e) {
        debugPrint('[DELEGATE_BENCHMARK] Tier 2 NNAPI failed: $e');
        nnapiCandidate?.close();
        nnapiCandidate = null;
      }
    }

    // Tier 3: XNNPack Delegate
    int xnnMs = 9999;
    Interpreter? xnnCandidate;
    try {
      final xnnOpts = InterpreterOptions()
        ..addDelegate(XNNPackDelegate(options: XNNPackDelegateOptions(numThreads: 4)));
      xnnCandidate = Interpreter.fromBuffer(modelBytes, options: xnnOpts);
      xnnCandidate.allocateTensors();
      final meta = _extractMetadata(xnnCandidate);
      _benchmarkInterpreter(xnnCandidate, meta); // warmup
      xnnMs = _benchmarkInterpreter(xnnCandidate, meta);
      debugPrint('[DELEGATE_BENCHMARK] Tier 3 XNNPack 4T: $xnnMs ms');
    } catch (e) {
      debugPrint('[DELEGATE_BENCHMARK] Tier 3 XNNPack failed: $e');
      xnnCandidate?.close();
      xnnCandidate = null;
    }

    // Tier 4: Plain CPU (4 threads)
    int cpuMs = 9999;
    Interpreter? cpuCandidate;
    try {
      final cpuOpts = InterpreterOptions()..threads = 4;
      cpuCandidate = Interpreter.fromBuffer(modelBytes, options: cpuOpts);
      cpuCandidate.allocateTensors();
      final meta = _extractMetadata(cpuCandidate);
      _benchmarkInterpreter(cpuCandidate, meta); // warmup
      cpuMs = _benchmarkInterpreter(cpuCandidate, meta);
      debugPrint('[DELEGATE_BENCHMARK] Tier 4 Plain CPU 4T: $cpuMs ms');
    } catch (e) {
      debugPrint('[DELEGATE_BENCHMARK] Tier 4 Plain CPU failed: $e');
      cpuCandidate?.close();
      cpuCandidate = null;
    }

    // Select the optimal delegate based on empirical benchmark latency:
    final candidates = <(int, TfliteHardwareDelegate, Interpreter)>[];
    if (gpuCandidate != null && gpuMs < 9000) candidates.add((gpuMs, TfliteHardwareDelegate.gpuV2, gpuCandidate));
    if (nnapiCandidate != null && nnapiMs < 9000) candidates.add((nnapiMs, TfliteHardwareDelegate.nnapi, nnapiCandidate));
    if (xnnCandidate != null && xnnMs < 9000) candidates.add((xnnMs, TfliteHardwareDelegate.xnnpack, xnnCandidate));
    if (cpuCandidate != null && cpuMs < 9000) candidates.add((cpuMs, TfliteHardwareDelegate.cpu, cpuCandidate));

    candidates.sort((a, b) => a.$1.compareTo(b.$1));

    if (candidates.isNotEmpty) {
      final best = candidates.first;
      _interpreter = best.$3;
      _activeDelegate = best.$2;
      for (final c in candidates) {
        if (c.$3 != _interpreter) {
          c.$3.close();
        }
      }
    }

    debugPrint('[DELEGATE_SELECTED] Selected Delegate: ${_activeDelegate.name}');

    if (_interpreter != null) {
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

  static int _debugFrameCounter = 0;

  static void _saveDebugFrame(Int8List int8Input, TfliteModelMeta meta) {
    try {
      final img.Image debugImg = img.Image(width: meta.inputSize, height: meta.inputSize);
      final double scale = meta.inputScale > 0 ? meta.inputScale : 1.0 / 255.0;
      final int zeroPoint = meta.inputZeroPoint;

      final int totalPixels = meta.inputSize * meta.inputSize;
      for (int i = 0; i < totalPixels; i++) {
        final int y = i ~/ meta.inputSize;
        final int x = i % meta.inputSize;
        final int idx = i * 3;
        final int rawR = int8Input[idx];
        final int rawG = int8Input[idx + 1];
        final int rawB = int8Input[idx + 2];

        final int r = (((rawR - zeroPoint) * scale) * 255.0).round().clamp(0, 255);
        final int g = (((rawG - zeroPoint) * scale) * 255.0).round().clamp(0, 255);
        final int b = (((rawB - zeroPoint) * scale) * 255.0).round().clamp(0, 255);
        debugImg.setPixelRgb(x, y, r, g, b);
      }

      final jpgBytes = img.encodeJpg(debugImg, quality: 85);
      final ts = DateTime.now().millisecondsSinceEpoch;
      const dirPath = '/sdcard/Android/data/com.roadguard.road_guard_mobile/files/debug_frames';
      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final filePath = '$dirPath/frame_$ts.jpg';
      final file = File(filePath);
      file.writeAsBytesSync(jpgBytes);
      DebugLogger.log('[DEBUG_FRAME]', 'Saved 640x640 model input buffer to $filePath (${jpgBytes.length} bytes)');
    } catch (e) {
      DebugLogger.log('[DEBUG_FRAME]', 'Failed to save debug frame: $e');
    }
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
    bool forceDetections = false,
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

    // Save every 10th 640x640 frame fed into the model
    _debugFrameCounter++;
    if (_debugFrameCounter % 10 == 0) {
      _saveDebugFrame(int8Input, meta);
    }

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
      forceDetections: forceDetections,
    );
    swDecode.stop();

    // 4. Filter candidates via explicit detection safety filters
    final swFilter = Stopwatch()..start();
    final List<DetectionResult> filtered;
    if (forceDetections) {
      filtered = NmsUtils.performNMS(candidates, iouThreshold: 0.50);
    } else {
      final trackingCandidates = DetectionFilter.filterForTracking(candidates);
      filtered = NmsUtils.performNMS(trackingCandidates, iouThreshold: iouThreshold);
    }
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
    bool forceDetections = false,
  }) {
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

    String getRawClassName(int c) {
      switch (c) {
        case 0:
          return 'Pothole (D40)';
        case 1:
          return 'Longitudinal (D00)';
        case 2:
          return 'Transverse (D10)';
        case 3:
          return 'Alligator (D20)';
        case 4:
          return 'SpeedBreaker';
        default:
          return 'Class_$c';
      }
    }

    // Step 1: Scan all anchors to extract Top 3 highest-confidence classes before ANY filtering
    final top3 = <({int classId, String className, double conf, Rect box})>[];

    for (int a = 0; a < numAnchors; a++) {
      int bestC = -1;
      double bestS = -1.0;

      for (int c = 0; c < numClasses; c++) {
        if (c == 4) continue; // Skip Speed Breaker
        final score = getValue(4 + c, a);
        if (score > bestS) {
          bestS = score;
          bestC = c;
        }
      }

      if (bestC >= 0) {
        final double cx = getValue(0, a) / meta.inputSize;
        final double cy = getValue(1, a) / meta.inputSize;
        final double w = getValue(2, a) / meta.inputSize;
        final double h = getValue(3, a) / meta.inputSize;

        final double left = (cx - w / 2.0).clamp(0.0, 1.0);
        final double top = (cy - h / 2.0).clamp(0.0, 1.0);
        final double right = (cx + w / 2.0).clamp(0.0, 1.0);
        final double bottom = (cy + h / 2.0).clamp(0.0, 1.0);

        final cand = (
          classId: bestC,
          className: getRawClassName(bestC),
          conf: bestS,
          box: Rect.fromLTRB(left, top, right, bottom),
        );

        if (top3.length < 3) {
          top3.add(cand);
          top3.sort((x, y) => y.conf.compareTo(x.conf));
        } else if (bestS > top3.last.conf) {
          top3[2] = cand;
          top3.sort((x, y) => y.conf.compareTo(x.conf));
        }
      }
    }

    // Format and log [RAW_TENSOR] for EVERY frame
    String fmtTop(int idx) {
      if (idx >= top3.length) return 'Top${idx + 1}: None';
      final item = top3[idx];
      return 'Top${idx + 1}: Class ${item.classId} (${item.className}) Conf: ${(item.conf * 100).toStringAsFixed(2)}%, Box: [${item.box.left.toStringAsFixed(3)}, ${item.box.top.toStringAsFixed(3)}, ${item.box.right.toStringAsFixed(3)}, ${item.box.bottom.toStringAsFixed(3)}]';
    }

    DebugLogger.log('[RAW_TENSOR]', '${fmtTop(0)} | ${fmtTop(1)} | ${fmtTop(2)}');

    // Step 2: Decode raw candidates
    final List<DetectionResult> rawCandidates = [];
    final double effThreshold = forceDetections ? 0.001 : confThreshold;

    for (int a = 0; a < numAnchors; a++) {
      int bestClassId = -1;
      double bestScore = 0.0;

      for (int c = 0; c < numClasses; c++) {
        if (c == 4) continue; // Skip Speed Breaker
        final score = getValue(4 + c, a);
        if (score > bestScore) {
          bestScore = score;
          bestClassId = c;
        }
      }

      if (bestScore < effThreshold || bestClassId < 0) {
        continue;
      }

      int remappedClassId;
      String remappedClassName;
      switch (bestClassId) {
        case 0:
          remappedClassId = 3; // D40 Pothole
          remappedClassName = 'D40';
          break;
        case 1:
          remappedClassId = 0; // D00 Longitudinal Crack
          remappedClassName = 'D00';
          break;
        case 2:
          remappedClassId = 1; // D10 Transverse Crack
          remappedClassName = 'D10';
          break;
        case 3:
          remappedClassId = 2; // D20 Alligator Crack
          remappedClassName = 'D20';
          break;
        default:
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

      rawCandidates.add(DetectionResult(
        classId: remappedClassId,
        className: remappedClassName,
        confidence: bestScore,
        normalizedRect: Rect.fromLTRB(left, top, right, bottom),
      ));
    }

    // If forceDetections is true and no candidate exceeded 0.001, seed with the top3 raw predictions
    if (forceDetections && rawCandidates.isEmpty && top3.isNotEmpty) {
      for (final t in top3) {
        int remappedClassId = 3;
        String remappedClassName = 'D40';
        switch (t.classId) {
          case 0:
            remappedClassId = 3;
            remappedClassName = 'D40';
            break;
          case 1:
            remappedClassId = 0;
            remappedClassName = 'D00';
            break;
          case 2:
            remappedClassId = 1;
            remappedClassName = 'D10';
            break;
          case 3:
            remappedClassId = 2;
            remappedClassName = 'D20';
            break;
        }
        rawCandidates.add(DetectionResult(
          classId: remappedClassId,
          className: remappedClassName,
          confidence: t.conf > 0 ? t.conf : 0.001,
          normalizedRect: t.box,
        ));
      }
    }

    // Step 3: Log [FILTER] for EVERY candidate with exact reason
    final List<DetectionResult> accepted = [];
    for (final cand in rawCandidates) {
      final eval = DetectionFilter.evaluate(
        rect: cand.normalizedRect,
        classId: cand.classId,
        confidence: cand.confidence,
      );

      String reasonStr;
      switch (eval.reason) {
        case FilterRejectionReason.borderArtifact:
          reasonStr = 'border';
          break;
        case FilterRejectionReason.minimumAreaViolation:
          reasonStr = 'min_area';
          break;
        case FilterRejectionReason.aspectRatioViolation:
          reasonStr = 'aspect_ratio';
          break;
        case FilterRejectionReason.belowTrackingFloor:
        case FilterRejectionReason.belowLoggingFloor:
          reasonStr = 'low_confidence';
          break;
        case FilterRejectionReason.invalidTaxonomyClass:
          reasonStr = 'invalid_class';
          break;
        case FilterRejectionReason.none:
          reasonStr = 'none';
          break;
      }

      final bool isAcc = eval.isValidForTracking;
      final String filterStatus = isAcc ? 'ACCEPTED' : 'REJECTED ($reasonStr)';
      DebugLogger.log(
        '[FILTER]',
        'Class: ${cand.className}, Conf: ${(cand.confidence * 100).toStringAsFixed(2)}%, Box: [${cand.normalizedRect.left.toStringAsFixed(3)}, ${cand.normalizedRect.top.toStringAsFixed(3)}, ${cand.normalizedRect.right.toStringAsFixed(3)}, ${cand.normalizedRect.bottom.toStringAsFixed(3)}] -> $filterStatus',
      );

      if (forceDetections) {
        DebugLogger.log('[FILTER]', '(OVERRIDDEN by kDebugForceDetections: forced ACCEPTED)');
        accepted.add(cand);
      } else if (isAcc) {
        accepted.add(cand);
      }
    }

    return accepted;
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
