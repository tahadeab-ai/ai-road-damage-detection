import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/constants/app_theme.dart';
import 'core/ffi/velopath_rust_bridge.dart';
import 'features/detection/data/datasources/tflite_engine.dart';
import 'features/detection/presentation/bloc/detection_bloc.dart';
import 'features/detection/presentation/bloc/detection_event.dart';
import 'features/detection/presentation/pages/driving_detector_screen.dart';
import 'features/history/data/repositories/hazard_repository.dart';
import 'features/telemetry/services/gps_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize VeloPath Rust FFI engine (with automatic self-contained diagnostic fallback)
  VeloPathRustBridge.instance;

  // Initialize Hive offline storage
  await Hive.initFlutter();

  // Set system UI styling for seamless in-car cyber-automotive dark HUD
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
    VeloPathMobileApp(
      tfliteEngine: tfliteEngine,
      gpsService: gpsService,
      hazardRepository: hazardRepository,
    ),
  );
}

class VeloPathMobileApp extends StatelessWidget {
  final TfliteEngine tfliteEngine;
  final GpsService gpsService;
  final HazardRepository hazardRepository;

  const VeloPathMobileApp({
    super.key,
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
            gpsService: gpsService,
            hazardRepository: hazardRepository,
          )..add(InitializeDetectionSystem()),
        ),
      ],
      child: MaterialApp(
        title: 'VeloPath AI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const DrivingDetectorScreen(),
      ),
    );
  }
}
