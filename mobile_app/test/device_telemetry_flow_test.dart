import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_guard_mobile/core/utils/camera_occlusion_detector.dart';
import 'package:road_guard_mobile/core/utils/road_surface_gate.dart';
import 'package:road_guard_mobile/features/detection/data/datasources/onnx_inference_engine.dart';
import 'package:road_guard_mobile/features/detection/domain/models/detection_result.dart';

void main() {
  group('Device Telemetry & Positive Detection Proof Tests', () {
    test('1. Camera Occlusion: Pitch black or covered lens triggers Camera Obstructed', () {
      // 640x640x3 buffer filled with near-zero luminance (covered lens in pocket or with tape/finger)
      final darkCoveredBuffer = Float32List(640 * 640 * 3); // all zeros

      final occlusion = CameraOcclusionDetector.checkOcclusion(darkCoveredBuffer);
      expect(occlusion.isOccluded, isTrue);
      expect(occlusion.reason, contains('Lens physically covered'));

      final gate = RoadSurfaceGate(historySize: 1);
      final roadEval = gate.evaluateSurface(darkCoveredBuffer, occlusion: occlusion);
      expect(roadEval.status, RoadSurfaceStatus.cameraObstructed);
      expect(roadEval.status.isTraversableRoad, isFalse);
    });

    test('2. Road Surface Gate: Non-road carpet / indoor wood triggers Non-Road Surface rejection', () {
      // Create high-saturation synthetic carpet buffer (vibrant red: R=0.9, G=0.1, B=0.1 -> Saturation ~ 0.88)
      final carpetBuffer = Float32List(640 * 640 * 3);
      for (int i = 0; i < 640 * 640; i++) {
        carpetBuffer[i * 3] = 0.90;     // R
        carpetBuffer[i * 3 + 1] = 0.10; // G
        carpetBuffer[i * 3 + 2] = 0.10; // B
      }

      final occlusion = CameraOcclusionDetector.checkOcclusion(carpetBuffer);
      expect(occlusion.isOccluded, isFalse); // Not occluded by finger/cover

      final gate = RoadSurfaceGate(historySize: 1);
      final roadEval = gate.evaluateSurface(carpetBuffer, occlusion: occlusion);
      expect(roadEval.status, RoadSurfaceStatus.nonRoad);
      expect(roadEval.status.isTraversableRoad, isFalse);
      expect(roadEval.rejectionReason, contains('carpet/rug'));
    });

    test('3. Positive Real-Detection Proof: Decodes D00, D10, D20, D40 with non-empty bounding box geometry', () {
      // Construct a valid model output tensor [8, 8400] containing 4 distinct real damage classes
      final outputMatrix = List.generate(8, (_) => List.filled(4, 0.0));

      // Defect 1: D00 Longitudinal Crack at [200, 400], w=60, h=180
      outputMatrix[0][0] = 200.0;
      outputMatrix[1][0] = 400.0;
      outputMatrix[2][0] = 60.0;
      outputMatrix[3][0] = 180.0;
      outputMatrix[4][0] = 0.91; // D00

      // Defect 2: D10 Transverse Crack at [450, 420], w=140, h=40
      outputMatrix[0][1] = 450.0;
      outputMatrix[1][1] = 420.0;
      outputMatrix[2][1] = 140.0;
      outputMatrix[3][1] = 40.0;
      outputMatrix[5][1] = 0.88; // D10

      // Defect 3: D20 Alligator Crack at [320, 520], w=120, h=100
      outputMatrix[0][2] = 320.0;
      outputMatrix[1][2] = 520.0;
      outputMatrix[2][2] = 120.0;
      outputMatrix[3][2] = 100.0;
      outputMatrix[6][2] = 0.86; // D20

      // Defect 4: D40 Pothole at [300, 380], w=90, h=70
      outputMatrix[0][3] = 300.0;
      outputMatrix[1][3] = 380.0;
      outputMatrix[2][3] = 90.0;
      outputMatrix[3][3] = 70.0;
      outputMatrix[7][3] = 0.94; // D40

      final decoded = OnnxInferenceEngine.decodeYoloOutput(
        outputMatrix,
        confThreshold: 0.50,
        iouThreshold: 0.35,
        roadRoiTop: 0.35,
      );

      expect(decoded.length, 4);

      // Verify D40 Pothole
      final pothole = decoded.firstWhere((d) => d.classId == 3);
      expect(pothole.className, 'Pothole');
      expect(pothole.confidence, closeTo(0.94, 1e-3));
      expect(pothole.normalizedRect.left, closeTo((300.0 - 45.0) / 640.0, 1e-3));
      expect(pothole.normalizedRect.right, closeTo((300.0 + 45.0) / 640.0, 1e-3));
      expect(pothole.normalizedRect.top, closeTo((380.0 - 35.0) / 640.0, 1e-3));
      expect(pothole.normalizedRect.bottom, closeTo((380.0 + 35.0) / 640.0, 1e-3));

      // Verify D00 Longitudinal Crack
      final d00 = decoded.firstWhere((d) => d.classId == 0);
      expect(d00.className, 'Longitudinal Crack');
      expect(d00.confidence, closeTo(0.91, 1e-3));

      // Verify D10 Transverse Crack
      final d10 = decoded.firstWhere((d) => d.classId == 1);
      expect(d10.className, 'Transverse Crack');
      expect(d10.confidence, closeTo(0.88, 1e-3));

      // Verify D20 Alligator Crack
      final d20 = decoded.firstWhere((d) => d.classId == 2);
      expect(d20.className, 'Alligator Crack');
      expect(d20.confidence, closeTo(0.86, 1e-3));
    });
  });
}
