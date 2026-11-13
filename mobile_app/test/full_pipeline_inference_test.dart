import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:road_guard_mobile/core/utils/image_processor.dart';
import 'package:road_guard_mobile/features/detection/data/datasources/tflite_engine.dart';
import 'package:road_guard_mobile/features/detection/presentation/bloc/detection_bloc.dart';
import 'package:road_guard_mobile/features/detection/presentation/bloc/detection_event.dart';
import 'package:road_guard_mobile/features/detection/presentation/bloc/detection_state.dart';
import 'package:road_guard_mobile/features/history/data/repositories/hazard_repository.dart';
import 'package:road_guard_mobile/features/telemetry/services/gps_service.dart';

class _FakeImageFormat extends Fake implements ImageFormat {
  @override
  final ImageFormatGroup group;
  @override
  final dynamic raw;

  _FakeImageFormat(this.group, {this.raw = 35});
}

class _FakePlane extends Fake implements Plane {
  @override
  final Uint8List bytes;
  @override
  final int bytesPerRow;
  @override
  final int? bytesPerPixel;

  _FakePlane({
    required this.bytes,
    required this.bytesPerRow,
    this.bytesPerPixel = 1,
  });
}

class _FakeCameraImage extends Fake implements CameraImage {
  @override
  final int width;
  @override
  final int height;
  @override
  final ImageFormat format;
  @override
  final List<Plane> planes;

  _FakeCameraImage({
    required this.width,
    required this.height,
    required this.format,
    required this.planes,
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tempDir = await Directory.systemTemp.createTemp('hive_test');
    Hive.init(tempDir.path);
  });

  group('VeloPath AI v2.2.1 Full Pipeline & Samsung YUV Resilience', () {
    test('ImageProcessor cameraImageToFloat32Array handles Samsung truncated semi-planar UV buffers without RangeError', () {
      const int w = 1280;
      const int h = 720;
      final int ySize = w * h;
      // Samsung semi-planar quirk: UV buffer length is (w * h / 2 - 1)
      final int uvTruncatedSize = (w * h ~/ 2) - 1;

      final yBytes = Uint8List(ySize);
      final uBytes = Uint8List(uvTruncatedSize);
      final vBytes = Uint8List(uvTruncatedSize);

      for (int i = 0; i < yBytes.length; i++) {
        yBytes[i] = (i % 256);
      }
      for (int i = 0; i < uBytes.length; i++) {
        uBytes[i] = 128;
        vBytes[i] = 128;
      }

      final fakeImage = _FakeCameraImage(
        width: w,
        height: h,
        format: _FakeImageFormat(ImageFormatGroup.yuv420, raw: 35),
        planes: [
          _FakePlane(bytes: yBytes, bytesPerRow: w, bytesPerPixel: 1),
          _FakePlane(bytes: uBytes, bytesPerRow: w, bytesPerPixel: 2),
          _FakePlane(bytes: vBytes, bytesPerRow: w, bytesPerPixel: 2),
        ],
      );

      expect(() {
        final tensor = ImageProcessor.cameraImageToFloat32Array(fakeImage);
        expect(tensor.length, equals(640 * 640 * 3));
        expect(tensor[0], inInclusiveRange(0.0, 1.0));
      }, returnsNormally);
    });

    test('ImageProcessor handles single-plane NV21 camera frames safely', () {
      const int w = 640;
      const int h = 480;
      final nv21Bytes = Uint8List(w * h * 3 ~/ 2);

      final fakeImage = _FakeCameraImage(
        width: w,
        height: h,
        format: _FakeImageFormat(ImageFormatGroup.yuv420, raw: 17),
        planes: [
          _FakePlane(bytes: nv21Bytes, bytesPerRow: w, bytesPerPixel: 1),
        ],
      );

      expect(() {
        final tensor = ImageProcessor.cameraImageToFloat32Array(fakeImage);
        expect(tensor.length, equals(640 * 640 * 3));
      }, returnsNormally);
    });

    test('model_manifest.json declares genuine RDD2022 4-class taxonomy and LiteRT shapes', () {
      final manifestFile = File('assets/models/model_manifest.json');
      expect(manifestFile.existsSync(), isTrue);

      final manifestJson = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      expect(manifestJson['version'], equals('2.2.0'));
      expect(manifestJson['classes'], equals(['D00', 'D10', 'D20', 'D40']));
      expect(manifestJson['output_shape'], equals([1, 8, 8400]));
      expect(manifestJson['tflite_sha256'], equals('c9e96a6c569aa28116ebd639bd7aa2d21f7239d84e74a717e3a0c08996a23595'));
    });

    test('DetectionState copyWith handles frameCount and lastPipelineError diagnostics', () {
      final initial = DetectionState.initial();
      expect(initial.frameCount, equals(0));
      expect(initial.lastPipelineError, isNull);
      expect(initial.isStreaming, isTrue);

      final updated = initial.copyWith(
        frameCount: 42,
        lastPipelineError: () => 'RangeError: Index out of range',
      );
      expect(updated.frameCount, equals(42));
      expect(updated.lastPipelineError, equals('RangeError: Index out of range'));

      final cleared = updated.copyWith(lastPipelineError: () => null);
      expect(cleared.lastPipelineError, isNull);
    });

    test('DetectionBloc initializes properly and processes camera frame with ticking FPS and frameCount', () async {
      final initial = DetectionState.initial();
      expect(initial.isStreaming, isTrue);

      final tflite = TfliteEngine();
      final gps = GpsService();
      final repo = HazardRepository();
      final bloc = DetectionBloc(
        tfliteEngine: tflite,
        gpsService: gps,
        hazardRepository: repo,
      );

      bloc.add(const InitializeDetectionSystem());
      await pumpEventQueue();

      expect(bloc.state.isStreaming, isTrue);

      const int w = 640;
      const int h = 480;
      final fakeImage = _FakeCameraImage(
        width: w,
        height: h,
        format: _FakeImageFormat(ImageFormatGroup.yuv420, raw: 17),
        planes: [
          _FakePlane(bytes: Uint8List(w * h * 3 ~/ 2), bytesPerRow: w, bytesPerPixel: 1),
        ],
      );

      bloc.add(ProcessCameraFrame(fakeImage));
      await pumpEventQueue(times: 5);

      expect(bloc.state.frameCount, greaterThanOrEqualTo(1));
      expect(bloc.state.fps, greaterThan(0.0));

      await bloc.close();
    });
  });
}
