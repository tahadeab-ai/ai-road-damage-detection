import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/constants/app_theme.dart';
import 'features/detection/data/datasources/onnx_inference_engine.dart';
import 'features/detection/data/datasources/tflite_engine.dart';
import 'features/detection/presentation/bloc/detection_bloc.dart';
import 'features/detection/presentation/bloc/detection_event.dart';
import 'features/detection/presentation/pages/driving_detector_screen.dart';
import 'features/history/data/repositories/hazard_repository.dart';
import 'features/telemetry/services/gps_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Log mandatory non-production measurement build diagnostic line
  debugPrint('[BUILD] Measurement build with reference YOLOv8n model. NOT production.');

  // Initialize Hive offline storage
  await Hive.initFlutter();

  // Set system UI styling for seamless in-car dark HUD
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final tfliteEngine = TfliteEngine();
  final gpsService = GpsService();
  final hazardRepository = HazardRepository();

  runApp(
    RoadGuardMobileApp(
      tfliteEngine: tfliteEngine,
      gpsService: gpsService,
      hazardRepository: hazardRepository,
    ),
  );
}

class RoadGuardMobileApp extends StatelessWidget {
  final OnnxInferenceEngine? debugOnnxEngine;
  final TfliteEngine tfliteEngine;
  final GpsService gpsService;
  final HazardRepository hazardRepository;

  const RoadGuardMobileApp({
    super.key,
    this.debugOnnxEngine,
    required this.tfliteEngine,
    required this.gpsService,
    required this.hazardRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<DetectionBloc>(
          create: (_) => DetectionBloc(
            tfliteEngine: tfliteEngine,
            debugOnnxEngine: debugOnnxEngine,
            gpsService: gpsService,
            hazardRepository: hazardRepository,
          )..add(InitializeDetectionSystem()),
        ),
      ],
      child: MaterialApp(
        title: 'RoadGuard Mobile',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const DrivingDetectorScreen(),
      ),
    );
  }
}
