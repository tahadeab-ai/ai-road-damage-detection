import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../domain/models/detection_result.dart';

/// Renders neon, corner-bracketed bounding boxes and confidence tags over live camera streams.
class BBoxOverlayPainter extends CustomPainter {
  final List<DetectionResult> detections;
  final double animationValue;

  BBoxOverlayPainter({
    required this.detections,
    this.animationValue = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    for (final detection in detections) {
      final rect = detection.toPixelRect(size);
      final Color defectColor = AppColors.getColorForDefect(detection.classId);

      // 1. Draw Semi-transparent Fill
      final fillPaint = Paint()
        ..color = defectColor.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), fillPaint);

      // 2. Draw Subtle Border Line
      final borderPaint = Paint()
        ..color = defectColor.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), borderPaint);

      // 3. Draw Cyberpunk Corner Brackets
      final cornerPaint = Paint()
        ..color = defectColor
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

      // 4. Critical Pulsing Halo Indicator for Potholes (D40)
      if (detection.classId == 3) {
        final double pulseOffset = sin(animationValue * pi * 2) * 4.0;
        final pulsePaint = Paint()
          ..color = AppColors.d40Pothole.withValues(alpha: 0.3)
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

      // 5. Draw Label Badge with Confidence Score
      final String labelText = '${detection.className.toUpperCase()} ${(detection.confidence * 100).toStringAsFixed(0)}%';
      _drawBadge(canvas, labelText, rect.topLeft, defectColor);
    }
  }

  void _drawBadge(Canvas canvas, String text, Offset position, Color color) {
    const textStyle = TextStyle(
      color: Colors.black,
      fontSize: 11,
      fontWeight: FontWeight.w900,
      letterSpacing: 0.5,
    );

    final textSpan = TextSpan(text: text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
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
    canvas.drawRRect(RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)), bgPaint);

    textPainter.paint(
      canvas,
      Offset(badgeRect.left + 6.0, badgeRect.top + 3.0),
    );
  }

  @override
  bool shouldRepaint(covariant BBoxOverlayPainter oldDelegate) {
    return oldDelegate.detections != detections || oldDelegate.animationValue != animationValue;
  }
}
