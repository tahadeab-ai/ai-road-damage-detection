import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/temporal_filter.dart';
import '../../domain/models/detection_result.dart';

/// Automotive-grade ADAS Bounding Box Painter.
/// Renders localized Arabic defect badges with explicit integer confidence percentages,
/// suppresses noisy unconfirmed candidate tags, and caps on-screen overlays to top-3 hazards.
class BBoxOverlayPainter extends CustomPainter {
  final List<TrackedDetection> trackedDetections;
  final List<DetectionResult>? fallbackDetections;
  final double animationValue;
  final double? cameraAspectRatio;
  final double roadRoiTop;

  BBoxOverlayPainter({
    required this.trackedDetections,
    this.fallbackDetections,
    this.animationValue = 1.0,
    this.cameraAspectRatio,
    this.roadRoiTop = 0.35,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 1. Draw subtle Automotive Road ROI guide line
    _drawRoadRoiHorizon(canvas, size);

    // 2. Render top 3 highest-confidence defects
    if (trackedDetections.isNotEmpty) {
      final sorted = List<TrackedDetection>.from(trackedDetections)
        ..sort((a, b) => b.confidence.compareTo(a.confidence));
      final top3 = sorted.take(3).toList();

      for (final track in top3) {
        _paintTrackedBox(canvas, size, track);
      }
    } else if (fallbackDetections != null && fallbackDetections!.isNotEmpty) {
      final sortedFallback = List<DetectionResult>.from(fallbackDetections!)
        ..sort((a, b) => b.confidence.compareTo(a.confidence));
      final top3 = sortedFallback.take(3).toList();

      for (final det in top3) {
        _paintFallbackBox(canvas, size, det);
      }
    }
  }

  void _drawRoadRoiHorizon(Canvas canvas, Size size) {
    final roiY = _mapY(roadRoiTop, size);
    if (roiY < 0 || roiY > size.height) return;

    final linePaint = Paint()
      ..color = AppColors.cyanAccent.withValues(alpha: 0.18)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Dashed guide line
    const dashWidth = 8.0;
    const dashSpace = 8.0;
    double startX = 24.0;
    final endX = size.width - 24.0;

    while (startX < endX) {
      canvas.drawLine(
        Offset(startX, roiY),
        Offset(min(startX + dashWidth, endX), roiY),
        linePaint,
      );
      startX += dashWidth + dashSpace;
    }

    // Edge HUD tick marks
    final tickPaint = Paint()
      ..color = AppColors.cyanAccent.withValues(alpha: 0.35)
      ..strokeWidth = 2.0;

    canvas.drawLine(Offset(16, roiY - 6), Offset(16, roiY + 6), tickPaint);
    canvas.drawLine(Offset(size.width - 16, roiY - 6), Offset(size.width - 16, roiY + 6), tickPaint);
  }

  void _paintTrackedBox(Canvas canvas, Size size, TrackedDetection track) {
    final rect = _mapRect(track.smoothedRect, size);
    final Color defectColor = AppColors.getColorForDefect(track.classId);
    final double alphaFactor = track.opacity.clamp(0.0, 1.0);

    if (!track.isConfirmed) {
      // Unconfirmed Candidate (< 3 frames):
      // Draw ONLY faint, subtle dashed brackets with zero obstructive text badge
      final faintBracketPaint = Paint()
        ..color = defectColor.withValues(alpha: 0.30 * alphaFactor)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;

      final double cornerLen = min(14.0, min(rect.width, rect.height) / 4.0);

      // Top-Left
      canvas.drawLine(Offset(rect.left, rect.top + cornerLen), Offset(rect.left, rect.top), faintBracketPaint);
      canvas.drawLine(Offset(rect.left, rect.top), Offset(rect.left + cornerLen, rect.top), faintBracketPaint);
      // Top-Right
      canvas.drawLine(Offset(rect.right - cornerLen, rect.top), Offset(rect.right, rect.top), faintBracketPaint);
      canvas.drawLine(Offset(rect.right, rect.top), Offset(rect.right, rect.top + cornerLen), faintBracketPaint);
      // Bottom-Left
      canvas.drawLine(Offset(rect.left, rect.bottom - cornerLen), Offset(rect.left, rect.bottom), faintBracketPaint);
      canvas.drawLine(Offset(rect.left, rect.bottom), Offset(rect.left + cornerLen, rect.bottom), faintBracketPaint);
      // Bottom-Right
      canvas.drawLine(Offset(rect.right - cornerLen, rect.bottom), Offset(rect.right, rect.bottom), faintBracketPaint);
      canvas.drawLine(Offset(rect.right, rect.bottom), Offset(rect.right, rect.bottom - cornerLen), faintBracketPaint);
      return;
    }

    // Confirmed Hazard: Full Automotive Visual Presentation
    // 1. Semi-transparent neon fill
    final fillPaint = Paint()
      ..color = defectColor.withValues(alpha: 0.12 * alphaFactor)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), fillPaint);

    // 2. Subtle border
    final borderPaint = Paint()
      ..color = defectColor.withValues(alpha: 0.50 * alphaFactor)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), borderPaint);

    // 3. Precision Corner Brackets
    final cornerPaint = Paint()
      ..color = defectColor.withValues(alpha: alphaFactor)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final double cornerLen = min(20.0, min(rect.width, rect.height) / 4.0);

    // Top-Left
    canvas.drawLine(Offset(rect.left, rect.top + cornerLen), Offset(rect.left, rect.top), cornerPaint);
    canvas.drawLine(Offset(rect.left, rect.top), Offset(rect.left + cornerLen, rect.top), cornerPaint);
    // Top-Right
    canvas.drawLine(Offset(rect.right - cornerLen, rect.top), Offset(rect.right, rect.top), cornerPaint);
    canvas.drawLine(Offset(rect.right, rect.top), Offset(rect.right, rect.top + cornerLen), cornerPaint);
    // Bottom-Left
    canvas.drawLine(Offset(rect.left, rect.bottom - cornerLen), Offset(rect.left, rect.bottom), cornerPaint);
    canvas.drawLine(Offset(rect.left, rect.bottom), Offset(rect.left + cornerLen, rect.bottom), cornerPaint);
    // Bottom-Right
    canvas.drawLine(Offset(rect.right - cornerLen, rect.bottom), Offset(rect.right, rect.bottom), cornerPaint);
    canvas.drawLine(Offset(rect.right, rect.bottom), Offset(rect.right, rect.bottom - cornerLen), cornerPaint);

    // 4. Critical Pulsing Halo Indicator for confirmed Potholes (D40)
    if (track.classId == 3) {
      final double pulseOffset = sin(animationValue * pi * 2) * 5.0;
      final pulsePaint = Paint()
        ..color = AppColors.d40Pothole.withValues(alpha: 0.35 * alphaFactor)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.inflate(pulseOffset.abs()),
          const Radius.circular(10),
        ),
        pulsePaint,
      );
    }

    // 5. Draw Localized Badge Tag with Explicit Percentage (e.g. "حفرة 84%")
    final String labelText = AppStrings.getDefectBadge(track.classId, track.confidence);
    _drawBadge(
      canvas,
      labelText,
      rect.topLeft,
      defectColor.withValues(alpha: alphaFactor),
    );
  }

  void _paintFallbackBox(Canvas canvas, Size size, DetectionResult det) {
    final rect = _mapRect(det.normalizedRect, size);
    final Color defectColor = AppColors.getColorForDefect(det.classId);

    final borderPaint = Paint()
      ..color = defectColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), borderPaint);

    final String labelText = AppStrings.getDefectBadge(det.classId, det.confidence);
    _drawBadge(canvas, labelText, rect.topLeft, defectColor);
  }

  Rect _mapRect(Rect normRect, Size size) {
    if (cameraAspectRatio == null || cameraAspectRatio! <= 0) {
      return Rect.fromLTRB(
        normRect.left * size.width,
        normRect.top * size.height,
        normRect.right * size.width,
        normRect.bottom * size.height,
      );
    }

    final screenAspect = size.width / size.height;
    double renderW = size.width;
    double renderH = size.height;
    double offsetX = 0.0;
    double offsetY = 0.0;

    if (screenAspect > cameraAspectRatio!) {
      renderH = size.width / cameraAspectRatio!;
      offsetY = (renderH - size.height) / 2.0;
    } else {
      renderW = size.height * cameraAspectRatio!;
      offsetX = (renderW - size.width) / 2.0;
    }

    return Rect.fromLTRB(
      normRect.left * renderW - offsetX,
      normRect.top * renderH - offsetY,
      normRect.right * renderW - offsetX,
      normRect.bottom * renderH - offsetY,
    );
  }

  double _mapY(double normY, Size size) {
    if (cameraAspectRatio == null || cameraAspectRatio! <= 0) {
      return normY * size.height;
    }
    final screenAspect = size.width / size.height;
    if (screenAspect > cameraAspectRatio!) {
      final renderH = size.width / cameraAspectRatio!;
      final offsetY = (renderH - size.height) / 2.0;
      return normY * renderH - offsetY;
    } else {
      return normY * size.height;
    }
  }

  void _drawBadge(Canvas canvas, String text, Offset position, Color color) {
    const textStyle = TextStyle(
      color: Colors.black,
      fontSize: 11,
      fontWeight: FontWeight.w900,
      letterSpacing: 0.3,
    );

    final textSpan = TextSpan(text: text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: AppStrings.direction,
    )..layout();

    final badgeHeight = textPainter.height + 6.0;
    final badgeWidth = textPainter.width + 12.0;
    final badgeRect = Rect.fromLTWH(
      position.dx,
      position.dy - badgeHeight - 4.0 >= 0 ? position.dy - badgeHeight - 4.0 : position.dy + 4.0,
      badgeWidth,
      badgeHeight,
    );

    final bgPaint = Paint()..color = color;
    canvas.drawRRect(RRect.fromRectAndRadius(badgeRect, const Radius.circular(5)), bgPaint);

    textPainter.paint(
      canvas,
      Offset(badgeRect.left + 6.0, badgeRect.top + 3.0),
    );
  }

  @override
  bool shouldRepaint(covariant BBoxOverlayPainter oldDelegate) {
    return oldDelegate.trackedDetections != trackedDetections ||
        oldDelegate.fallbackDetections != fallbackDetections ||
        oldDelegate.animationValue != animationValue ||
        oldDelegate.cameraAspectRatio != cameraAspectRatio;
  }
}
