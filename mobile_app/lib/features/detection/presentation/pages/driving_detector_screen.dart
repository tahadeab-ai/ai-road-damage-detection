import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/lifecycle/permission_state_machine.dart';
import '../../../../core/localization/app_localizations.dart';
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _cameraController;
  final PermissionStateMachine _permissionMachine = PermissionStateMachine();
  bool _isCameraReady = false;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    _permissionMachine.addListener(_onPermissionStateChanged);
    _verifyPermissionsAndSetupCamera();
  }

  void _onPermissionStateChanged() {
    if (mounted) {
      setState(() {});
      if (_permissionMachine.isReady && _cameraController == null) {
        _initializeCamera();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-verify sequential permissions before instantiating hardware controller
      _verifyPermissionsAndSetupCamera();
    } else if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _stopAndDisposeCamera();
    }
  }

  /// Verifies sequential permissions through PermissionStateMachine before instantiating hardware controller.
  Future<void> _verifyPermissionsAndSetupCamera() async {
    try {
      final granted = await _permissionMachine.requestSequentialPermissions();
      if (!mounted) return;

      if (granted) {
        await _initializeCamera();
      }
    } catch (e) {
      debugPrint('[DrivingDetectorScreen] Permission verification notice: $e');
    }
  }

  /// Explicitly requests sequential permissions upon user interaction.
  Future<void> _requestPermissions() async {
    final granted = await _permissionMachine.requestSequentialPermissions();
    if (!mounted) return;

    if (granted) {
      await _initializeCamera();
    } else if (_permissionMachine.currentStep == PermissionStep.permanentlyDenied) {
      _permissionMachine.openAppSettingsMenu();
    }
  }

  /// Disposes existing camera controller safely.
  Future<void> _stopAndDisposeCamera() async {
    try {
      if (_cameraController != null) {
        if (_cameraController!.value.isStreamingImages) {
          await _cameraController!.stopImageStream();
        }
        await _cameraController!.dispose();
        _cameraController = null;
      }
    } catch (e) {
      debugPrint('[DrivingDetectorScreen] Camera disposal notice: $e');
    } finally {
      if (mounted) {
        setState(() => _isCameraReady = false);
      }
    }
  }

  /// Cleanly instantiates and streams CameraController.
  Future<void> _initializeCamera() async {
    await _stopAndDisposeCamera();

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _isCameraReady = false);
        return;
      }

      // Select back-facing camera
      final backCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      _cameraController = controller;

      // Start live camera stream
      await _cameraController!.startImageStream((CameraImage image) {
        if (mounted) {
          context.read<DetectionBloc>().add(ProcessCameraFrame(image));
        }
      });

      if (mounted) {
        setState(() => _isCameraReady = true);
      }
    } catch (e) {
      debugPrint('[DrivingDetectorScreen] Camera initialization notice: $e');
      if (mounted) setState(() => _isCameraReady = false);
    }
  }

  double _getPreviewAspectRatio(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return 9.0 / 16.0;
    }
    final rawAspect = _cameraController!.value.aspectRatio;
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    if (isPortrait) {
      return rawAspect > 1.0 ? (1.0 / rawAspect) : rawAspect;
    } else {
      return rawAspect < 1.0 ? (1.0 / rawAspect) : rawAspect;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _permissionMachine.removeListener(_onPermissionStateChanged);
    _permissionMachine.dispose();
    _stopAndDisposeCamera();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: AppLanguageNotifier.instance,
      builder: (context, lang, child) {
        return Directionality(
          textDirection: AppStrings.direction,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: BlocConsumer<DetectionBloc, DetectionState>(
              listenWhen: (prev, curr) => prev.isTorchOn != curr.isTorchOn,
              listener: (context, state) async {
                if (_cameraController != null && _cameraController!.value.isInitialized) {
                  try {
                    await _cameraController!.setFlashMode(
                      state.isTorchOn ? FlashMode.torch : FlashMode.off,
                    );
                  } catch (e) {
                    debugPrint('[DrivingDetectorScreen] Flash mode toggle notice: $e');
                  }
                }
              },
              builder: (context, state) {
                final previewAspect = _getPreviewAspectRatio(context);

                // Permission Guard Overlay: displayed if sequential permissions are not yet ready
                if (!_permissionMachine.isReady) {
                  return _buildPermissionGuardOverlay();
                }

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // 1. Fullscreen Camera Viewport with BoxFit.cover
                    if (_isCameraReady && _cameraController != null)
                      ClipRect(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final screenAspect = constraints.maxWidth / constraints.maxHeight;
                            double scale = 1.0;
                            if (screenAspect > previewAspect) {
                              scale = screenAspect / previewAspect;
                            } else {
                              scale = previewAspect / screenAspect;
                            }

                            return Transform.scale(
                              scale: scale,
                              child: Center(
                                child: AspectRatio(
                                  aspectRatio: previewAspect,
                                  child: CameraPreview(_cameraController!),
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    else
                      _buildSimulationCameraViewport(),

                    // 2. Temporally Smoothed Bounding Box Overlay with Subpixel Geometry Alignment
                    AnimatedBuilder(
                      animation: _animController,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: BBoxOverlayPainter(
                            trackedDetections: state.isStreaming ? state.trackedDetections : [],
                            fallbackDetections: state.isStreaming ? state.detections : [],
                            animationValue: _animController.value,
                            cameraAspectRatio: previewAspect,
                            roadRoiTop: 0.35,
                            isRoadDetected: state.isRoadDetected,
                          ),
                        );
                      },
                    ),

                    // 3. Automotive Heads-Up Display (HUD)
                    CameraHudOverlay(
                      state: state,
                      onToggleStreaming: () {
                        context
                            .read<DetectionBloc>()
                            .add(ToggleDetectionStreaming(!state.isStreaming));
                      },
                      onToggleMute: () {
                        context.read<DetectionBloc>().add(ToggleMuteAudio());
                      },
                      onToggleTorch: () {
                        context.read<DetectionBloc>().add(ToggleTorchMode());
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
          ),
        );
      },
    );
  }

  /// High-aesthetic automotive permission guard screen.
  Widget _buildPermissionGuardOverlay() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.3,
          colors: [Color(0xFF1E293B), Color(0xFF0A0F1D)],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28.0),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.cyanAccent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.cyanAccent, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cyanAccent.withValues(alpha: 0.35),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: const Icon(Icons.security_rounded, size: 40, color: AppColors.cyanAccent),
              ),
              const SizedBox(height: 24),
              Text(
                AppStrings.permissionTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                AppStrings.permissionSubtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: _requestPermissions,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.cyanAccent, Color(0xFF0091EA)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.cyanAccent.withValues(alpha: 0.45),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      AppStrings.grantPermissions,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ).animate().shimmer(duration: 2000.ms),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => openAppSettings(),
                child: Text(
                  AppStrings.openSettings,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
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
        return Directionality(
          textDirection: AppStrings.direction,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppStrings.diagnostics,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _buildMetricTile(
                  AppStrings.isArabic ? 'تسريع المعالجة' : 'Runtime Acceleration',
                  'Android NNAPI (GPU Delegate)',
                ),
                _buildMetricTile(
                  AppStrings.isArabic ? 'أبعاد مصفوفة الإدخال' : 'Input Tensor Shape',
                  '[1, 640, 640, 3] Float32',
                ),
                _buildMetricTile(
                  AppStrings.isArabic ? 'زمن الاستجابة' : 'Inference Latency',
                  '${state.inferenceLatencyMs} ${AppStrings.msUnit}',
                ),
                _buildMetricTile(
                  AppStrings.isArabic ? 'معدل الإطارات' : 'Framerate Output',
                  '${state.fps} ${AppStrings.fpsUnit}',
                ),
                _buildMetricTile(
                  AppStrings.isArabic ? 'المسارات النشطة المؤكدة' : 'Confirmed Active Tracks',
                  '${state.trackedDetections.where((t) => t.isConfirmed).length}',
                ),
                _buildMetricTile(
                  AppStrings.isArabic ? 'حالة الحركة' : 'Vehicle Movement Gate',
                  state.isLowSpeed
                      ? AppStrings.standby
                      : (AppStrings.isArabic ? 'مراقبة نشطة' : 'ACTIVE MONITORING'),
                ),
                _buildMetricTile(
                  AppStrings.isArabic ? 'إجمالي الأضرار المسجلة' : 'Total Logged Hazards',
                  '${state.totalLoggedCount}',
                ),
                _buildMetricTile(
                  AppStrings.isArabic ? 'الموقع الحالي' : 'Active Location',
                  state.gpsData.address,
                ),
                const SizedBox(height: 16),
              ],
            ),
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
