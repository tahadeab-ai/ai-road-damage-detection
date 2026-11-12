import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/constants/app_theme.dart';
import 'core/constants/colors.dart';
import 'features/detection/data/datasources/tflite_engine.dart';
import 'features/detection/presentation/bloc/detection_bloc.dart';
import 'features/detection/presentation/bloc/detection_event.dart';
import 'features/detection/presentation/pages/driving_detector_screen.dart';
import 'features/history/data/repositories/hazard_repository.dart';
import 'features/telemetry/services/gps_service.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Global error listener
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('[VeloPath Startup Error] ${details.exceptionAsString()}');
    };

    // Resilient Cyber Dark HUD Error Boundary Screen
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 56),
                    const SizedBox(height: 16),
                    const Text(
                      'VeloPath AI Diagnostic Halt',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      details.exceptionAsString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    };

    // Set system UI styling for seamless in-car cyber-automotive dark HUD
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    // Initialize Hive offline storage safely
    try {
      await Hive.initFlutter();
    } catch (e) {
      debugPrint('[VeloPath] Hive initialization deferred: $e');
    }

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
  }, (error, stackTrace) {
    debugPrint('[VeloPath Unhandled Root Exception] $error\n$stackTrace');
  });
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
