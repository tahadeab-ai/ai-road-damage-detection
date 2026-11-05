import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/constants/colors.dart';
import '../bloc/detection_bloc.dart';
import '../bloc/detection_event.dart';
import '../bloc/detection_state.dart';
import '../widgets/bbox_painter.dart';
import '../widgets/camera_hud_overlay.dart';
import '../../../history/presentation/pages/hazard_log_screen.dart';

class DrivingDetectorScreen extends StatefulWidget {
  const DrivingDetectorScreen({super.key});

  @override
  State<DrivingDetectorScreen> createState() => _DrivingDetectorScreenState();
}

class _DrivingDetectorScreenState extends State<DrivingDetectorScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    _initializeCameraAndPermissions();
  }

  Future<void> _initializeCameraAndPermissions() async {
    // 1. Request camera and location permissions
    await [
      Permission.camera,
      Permission.locationWhenInUse,
    ].request();

    // 2. Discover devices
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _isCameraReady = false);
        return;
      }

      // Select back-facing camera
      final backCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      if (!mounted) return;

      // Start stream
      await _cameraController!.startImageStream((CameraImage image) {
        if (mounted) {
          context.read<DetectionBloc>().add(ProcessCameraFrame(image));
        }
      });

      setState(() => _isCameraReady = true);
    } catch (e) {
      debugPrint('[DrivingDetectorScreen] Camera init notice: $e');
      setState(() => _isCameraReady = false);
    }
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: BlocBuilder<DetectionBloc, DetectionState>(
        builder: (context, state) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Camera Viewport or Fallback Simulator Background
              if (_isCameraReady && _cameraController != null)
                Center(
                  child: AspectRatio(
                    aspectRatio: _cameraController!.value.aspectRatio,
                    child: CameraPreview(_cameraController!),
                  ),
                )
              else
                _buildSimulationCameraViewport(),

              // 2. Bounding Box Custom Painter Overlay
              AnimatedBuilder(
                animation: _animController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: BBoxOverlayPainter(
                      detections: state.isStreaming ? state.detections : [],
                      animationValue: _animController.value,
                    ),
                  );
                },
              ),

              // 3. Cyberpunk Heads-Up Display (HUD)
              CameraHudOverlay(
                state: state,
                onToggleStreaming: () {
                  context
                      .read<DetectionBloc>()
                      .add(ToggleDetectionStreaming(!state.isStreaming));
                },
                onOpenHistory: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const HazardLogScreen(),
                    ),
                  );
                },
                onOpenAnalytics: () => _showAnalyticsBottomSheet(context, state),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSimulationCameraViewport() {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.2,
          colors: [Color(0xFF1E293B), Color(0xFF090D16)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_outlined, size: 64, color: AppColors.cyanAccent.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              'LIVE ROADWAY SIMULATOR ACTIVE',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Hardware vision pipeline connected to virtual camera stream',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  void _showAnalyticsBottomSheet(BuildContext context, DetectionState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'EDGE AI DIAGNOSTICS',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.0),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 24),
              _buildMetricTile('Runtime Acceleration', 'Android NNAPI (GPU Delegate)'),
              _buildMetricTile('Input Tensor Shape', '[1, 640, 640, 3] Float32'),
              _buildMetricTile('Current Latency', '${state.inferenceLatencyMs} ms'),
              _buildMetricTile('Framerate Output', '${state.fps} FPS (Thermal Guarded)'),
              _buildMetricTile('Total Logged Hazards', '${state.totalLoggedCount} Incidents'),
              _buildMetricTile('Active Location', state.gpsData.address),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}
