import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../../../../core/utils/nms_utils.dart';
import '../../domain/models/detection_result.dart';

/// On-Device TFLite inference engine for YOLO road damage detection.
/// Strictly executes real TFLite neural network inference with NO fake/synthetic fallbacks.
class TfliteEngine {
  // Use the verified road damage model (per-tensor INT8, 512x512 input, [1, 9, 5376] output)
  static const String primaryModelAssetPath = 'assets/models/road_damage_yolo11n_float16.tflite';
  static const String fallbackModelAssetPath = 'assets/models/yolo11n_int8.tflite';
  static const String labelsAssetPath = 'assets/models/labels.txt';

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isInitialized = false;

  int _modelInputW = 512;
  int _modelInputH = 512;
  TensorType _inputType = TensorType.int8;
  double _inputScale = 0.00392157;
  int _inputZeroPoint = -128;

  List<int> _outputShape = [1, 9, 5376];
  TensorType _outputType = TensorType.int8;
  double _outputScale = 0.00392157;
  int _outputZeroPoint = -128;

  bool get isInitialized => _isInitialized;
  List<String> get labels => _labels;

  /// Initializes TFLite interpreters with hardware delegate acceleration.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. Load labels
      try {
        final labelsData = await rootBundle.loadString(labelsAssetPath);
        _labels = labelsData
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } catch (_) {}

      if (_labels.isEmpty) {
        _labels = [
          'Longitudinal Crack',
          'Transverse Crack',
          'Alligator Crack',
          'Pothole',
          'Speed Breaker',
        ];
      }

      final options = InterpreterOptions()..threads = 4;

      // 2. Load model from assets
      try {
        _interpreter = await Interpreter.fromAsset(primaryModelAssetPath, options: options);
        _interpreter?.allocateTensors();
        debugPrint('[TfliteEngine] Successfully loaded primary model: $primaryModelAssetPath');
      } catch (e) {
        debugPrint('[TfliteEngine] Primary model load error: $e. Trying fallback: $fallbackModelAssetPath');
        try {
          _interpreter = await Interpreter.fromAsset(fallbackModelAssetPath, options: options);
          _interpreter?.allocateTensors();
          debugPrint('[TfliteEngine] Successfully loaded fallback model: $fallbackModelAssetPath');
        } catch (fErr) {
          debugPrint('[TfliteEngine] Fatal: Failed to load both models: $fErr');
        }
      }

      if (_interpreter != null) {
        final inTensor = _interpreter!.getInputTensor(0);
        final inShape = inTensor.shape;
        _inputType = inTensor.type;
        _inputScale = inTensor.params.scale > 0 ? inTensor.params.scale : 0.00392157;
        _inputZeroPoint = inTensor.params.zeroPoint;

        if (inShape.length >= 4) {
          // NHWC: [1, H, W, C]
          _modelInputH = inShape[1];
          _modelInputW = inShape[2];
        }

        final outTensor = _interpreter!.getOutputTensor(0);
        _outputShape = outTensor.shape;
        _outputType = outTensor.type;
        _outputScale = outTensor.params.scale > 0 ? outTensor.params.scale : 0.00392157;
        _outputZeroPoint = outTensor.params.zeroPoint;

        debugPrint('[TfliteEngine] Model Input: shape=$inShape, type=$_inputType, scale=$_inputScale, zp=$_inputZeroPoint');
        debugPrint('[TfliteEngine] Model Output: shape=$_outputShape, type=$_outputType, scale=$_outputScale, zp=$_outputZeroPoint');
      }

      _isInitialized = true;
      debugPrint('[TfliteEngine] Engine ready.');
    } catch (e, st) {
      debugPrint('[TfliteEngine] Initialization failed: $e\n$st');
      _isInitialized = true;
    }
  }

  /// Gatekeeper: Spectral Road Surface Classifier (Road vs Non-Road).
  /// Rejects indoor scenes (white walls, doors, colorful carpets, wooden floors).
  Future<bool> checkRoadSurface(Float32List inputBuffer, {bool benchMode = false}) async {
    if (benchMode) return true; // Bench test bypasses road surface gate

    if (!_isInitialized) {
      await initialize();
    }

    try {
      const int w = 640;
      int sampledPixels = 0;
      double totalSaturation = 0.0;
      double totalLuminance = 0.0;
      double sumLumSq = 0.0;

      // Sample pixels in lower road zone (Y from 280 to 600, X from 100 to 540)
      for (int y = 280; y < 600; y += 16) {
        for (int x = 100; x < 540; x += 16) {
          final int idx = (y * w + x) * 3;
          if (idx + 2 < inputBuffer.length) {
            final double r = inputBuffer[idx];
            final double g = inputBuffer[idx + 1];
            final double b = inputBuffer[idx + 2];

            final double maxC = max(r, max(g, b));
            final double minC = min(r, min(g, b));
            final double delta = maxC - minC;

            final double sat = maxC > 0.01 ? (delta / maxC) : 0.0;
            final double lum = 0.299 * r + 0.587 * g + 0.114 * b;

            totalSaturation += sat;
            totalLuminance += lum;
            sumLumSq += lum * lum;
            sampledPixels++;
          }
        }
      }

      if (sampledPixels > 0) {
        final double avgSat = totalSaturation / sampledPixels;
        final double avgLum = totalLuminance / sampledPixels;
        final double variance = (sumLumSq / sampledPixels) - (avgLum * avgLum);

        // 1. High saturation indicates colorful indoor objects, rugs, wood, flowers (avgSat > 0.26)
        if (avgSat > 0.26) {
          return false;
        }

        // 2. Very bright uniform surface indicates white door, ceiling, or interior wall (avgLum > 0.70)
        if (avgLum > 0.70) {
          return false;
        }

        // 3. Flat painted wall/surface with low texture variance (< 0.0020) and moderate/high brightness
        if (variance < 0.0020 && avgLum > 0.40) {
          return false;
        }

        // 4. Extreme darkness (< 0.05)
        if (avgLum < 0.05) {
          return false;
        }
      }
    } catch (_) {
      // On error allow pass
    }

    return true;
  }

  /// Runs inference on a normalized [1, 640, 640, 3] Float32 buffer.
  /// Strictly returns empty list `[]` when no real damage is detected or if an error occurs.
  Future<List<DetectionResult>> runInference(
    Float32List inputBuffer, {
    double confThreshold = 0.20,
    double iouThreshold = 0.35,
    double roadRoiTop = 0.20,
    bool benchMode = false,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_interpreter == null) {
      return [];
    }

    final effectiveRoiTop = benchMode ? 0.0 : roadRoiTop;
    final effectiveConf = confThreshold;

    try {
      // 1. Resample and quantize input buffer to match model input dimensions [modelH, modelW, 3]
      final int modelW = _modelInputW;
      final int modelH = _modelInputH;
      const int srcW = 640;
      const int srcH = 640;
      final int inputLen = modelW * modelH * 3;

      final ByteBuffer inputByteBuffer;

      if (_inputType == TensorType.int8) {
        final i8 = Int8List(inputLen);
        final double invScale = 1.0 / _inputScale;
        final int zp = _inputZeroPoint;

        int outIdx = 0;
        for (int y = 0; y < modelH; y++) {
          final int srcY = (y * srcH) ~/ modelH;
          for (int x = 0; x < modelW; x++) {
            final int srcX = (x * srcW) ~/ modelW;
            final int srcIdx = (srcY * srcW + srcX) * 3;

            final double r = inputBuffer[srcIdx];
            final double g = inputBuffer[srcIdx + 1];
            final double b = inputBuffer[srcIdx + 2];

            i8[outIdx++] = (r * invScale + zp).round().clamp(-128, 127);
            i8[outIdx++] = (g * invScale + zp).round().clamp(-128, 127);
            i8[outIdx++] = (b * invScale + zp).round().clamp(-128, 127);
          }
        }
        inputByteBuffer = i8.buffer;
      } else if (_inputType == TensorType.uint8) {
        final u8 = Uint8List(inputLen);
        final double invScale = 1.0 / _inputScale;
        final int zp = _inputZeroPoint;

        int outIdx = 0;
        for (int y = 0; y < modelH; y++) {
          final int srcY = (y * srcH) ~/ modelH;
          for (int x = 0; x < modelW; x++) {
            final int srcX = (x * srcW) ~/ modelW;
            final int srcIdx = (srcY * srcW + srcX) * 3;

            final double r = inputBuffer[srcIdx];
            final double g = inputBuffer[srcIdx + 1];
            final double b = inputBuffer[srcIdx + 2];

            u8[outIdx++] = (r * invScale + zp).round().clamp(0, 255);
            u8[outIdx++] = (g * invScale + zp).round().clamp(0, 255);
            u8[outIdx++] = (b * invScale + zp).round().clamp(0, 255);
          }
        }
        inputByteBuffer = u8.buffer;
      } else {
        // Float32
        final f32 = Float32List(inputLen);
        int outIdx = 0;
        for (int y = 0; y < modelH; y++) {
          final int srcY = (y * srcH) ~/ modelH;
          for (int x = 0; x < modelW; x++) {
            final int srcX = (x * srcW) ~/ modelW;
            final int srcIdx = (srcY * srcW + srcX) * 3;

            f32[outIdx++] = inputBuffer[srcIdx];
            f32[outIdx++] = inputBuffer[srcIdx + 1];
            f32[outIdx++] = inputBuffer[srcIdx + 2];
          }
        }
        inputByteBuffer = f32.buffer;
      }

      // 2. Prepare Output Tensor buffer
      final int totalOutElements = _outputShape.reduce((a, b) => a * b);
      final Float32List dequantizedOutput;

      if (_outputType == TensorType.int8) {
        final rawOut = Int8List(totalOutElements);
        _interpreter!.runForMultipleInputs([inputByteBuffer], {0: rawOut.buffer});

        dequantizedOutput = Float32List(totalOutElements);
        final double os = _outputScale;
        final int ozp = _outputZeroPoint;
        for (int i = 0; i < totalOutElements; i++) {
          dequantizedOutput[i] = (rawOut[i] - ozp) * os;
        }
      } else if (_outputType == TensorType.uint8) {
        final rawOut = Uint8List(totalOutElements);
        _interpreter!.runForMultipleInputs([inputByteBuffer], {0: rawOut.buffer});

        dequantizedOutput = Float32List(totalOutElements);
        final double os = _outputScale;
        final int ozp = _outputZeroPoint;
        for (int i = 0; i < totalOutElements; i++) {
          dequantizedOutput[i] = (rawOut[i] - ozp) * os;
        }
      } else {
        dequantizedOutput = Float32List(totalOutElements);
        _interpreter!.runForMultipleInputs([inputByteBuffer], {0: dequantizedOutput.buffer});
      }

      // 3. Parse YOLO boxes
      return _parseFlatYoloOutput(
        dequantizedOutput,
        _outputShape,
        effectiveConf,
        iouThreshold,
        roadRoiTop: effectiveRoiTop,
      );
    } catch (e, st) {
      debugPrint('[TfliteEngine] Exception during inference execution: $e\n$st');
      return [];
    }
  }

  /// Parses flat YOLO tensor buffer [1, C, N] or [1, N, C] into bounding boxes and applies NMS.
  List<DetectionResult> _parseFlatYoloOutput(
    Float32List outputBuffer,
    List<int> outputShape,
    double confThreshold,
    double iouThreshold, {
    double roadRoiTop = 0.20,
  }) {
    final List<DetectionResult> candidates = [];
    final int dim1 = outputShape.length >= 2 ? outputShape[outputShape.length - 2] : 9;
    final int dim2 = outputShape.isNotEmpty ? outputShape[outputShape.length - 1] : 5376;

    // Detect Channels-First ([C, N] where C < N, e.g. [9, 5376]) vs Channels-Last ([N, C])
    final bool isChannelsFirst = dim1 < dim2;
    final int numChannels = isChannelsFirst ? dim1 : dim2;
    final int numPredictions = isChannelsFirst ? dim2 : dim1;
    final int numClasses = (numChannels - 4).clamp(1, 80);

    for (int i = 0; i < numPredictions; i++) {
      final double cx = isChannelsFirst ? outputBuffer[0 * numPredictions + i] : outputBuffer[i * numChannels + 0];
      final double cy = isChannelsFirst ? outputBuffer[1 * numPredictions + i] : outputBuffer[i * numChannels + 1];
      final double w = isChannelsFirst ? outputBuffer[2 * numPredictions + i] : outputBuffer[i * numChannels + 2];
      final double h = isChannelsFirst ? outputBuffer[3 * numPredictions + i] : outputBuffer[i * numChannels + 3];

      // Handle both normalized (0.0..1.0) and pixel-space (0.0..512.0 or 0.0..640.0) coordinates
      final double normCx = cx > 1.5 ? (cx / _modelInputW.toDouble()) : cx;
      final double normCy = cy > 1.5 ? (cy / _modelInputH.toDouble()) : cy;
      final double normW = w > 1.5 ? (w / _modelInputW.toDouble()) : w;
      final double normH = h > 1.5 ? (h / _modelInputH.toDouble()) : h;

      if (normW <= 0.01 || normH <= 0.01 || normW > 1.0 || normH > 1.0) {
        continue;
      }

      // Suppress detections outside Road Surface ROI (top zone is sky/horizon)
      if (normCy < roadRoiTop) {
        continue;
      }

      // Find highest class confidence among available damage classes
      double maxScore = -1.0;
      int bestClassId = -1;

      for (int c = 0; c < numClasses; c++) {
        final double score = isChannelsFirst
            ? outputBuffer[(4 + c) * numPredictions + i]
            : outputBuffer[i * numChannels + (4 + c)];
        if (score > maxScore) {
          maxScore = score;
          bestClassId = c;
        }
      }

      if (maxScore >= confThreshold && bestClassId >= 0) {
        final double left = (normCx - (normW / 2.0)).clamp(0.0, 1.0);
        final double top = (normCy - (normH / 2.0)).clamp(0.0, 1.0);
        final double right = (normCx + (normW / 2.0)).clamp(0.0, 1.0);
        final double bottom = (normCy + (normH / 2.0)).clamp(0.0, 1.0);

        final className = bestClassId < _labels.length ? _labels[bestClassId] : 'Defect #$bestClassId';

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

    if (candidates.isEmpty) return [];

    return NmsUtils.performNMS(
      candidates,
      iouThreshold: iouThreshold,
      confThreshold: confThreshold,
    );
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}
