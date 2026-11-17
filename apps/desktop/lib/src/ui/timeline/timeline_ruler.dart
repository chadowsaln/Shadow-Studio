import 'package:flutter/material.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';
import '../../utils/timecode_formatter.dart';

/// Horizontal SMPTE timecode ruler for the timeline.
class TimelineRuler extends StatelessWidget {
  final EditorController controller;
  final double totalWidth;

  const TimelineRuler({
    super.key,
    required this.controller,
    required this.totalWidth,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);
    final pps = controller.pixelsPerSecond;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        final clickedX = details.localPosition.dx;
        final targetSeconds = clickedX / pps;
        final targetTicks = (targetSeconds * 1000000).round();
        controller.seek(targetTicks);
      },
      onHorizontalDragUpdate: (details) {
        final clickedX = details.localPosition.dx;
        final targetSeconds = clickedX / pps;
        final targetTicks = (targetSeconds * 1000000).round();
        controller.seek(targetTicks);
      },
      child: Container(
        height: 24,
        width: totalWidth,
        decoration: BoxDecoration(
          color: colors.surface2,
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        child: CustomPaint(
          size: Size(totalWidth, 24),
          painter: _RulerPainter(
            pixelsPerSecond: pps,
            totalWidth: totalWidth,
            tickColor: colors.border,
            textColor: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  final double pixelsPerSecond;
  final double totalWidth;
  final Color tickColor;
  final Color textColor;

  _RulerPainter({
    required this.pixelsPerSecond,
    required this.totalWidth,
    required this.tickColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = tickColor
      ..strokeWidth = 1.0;

    // Determine interval spacing based on zoom level
    double secondStep = 1.0;
    if (pixelsPerSecond < 15) {
      secondStep = 10.0;
    } else if (pixelsPerSecond < 40) {
      secondStep = 5.0;
    } else if (pixelsPerSecond > 120) {
      secondStep = 0.5;
    }

    final totalSeconds = totalWidth / pixelsPerSecond;

    for (double sec = 0.0; sec <= totalSeconds; sec += secondStep) {
      final x = sec * pixelsPerSecond;
      // Major tick mark
      canvas.drawLine(Offset(x, size.height - 10), Offset(x, size.height), linePaint);

      // Label every major division
      final ticks = (sec * 1000000).round();
      final tc = TimecodeFormatter.format(ticks, isolateLtr: false);
      final textSpan = TextSpan(
        text: tc,
        style: ShadowTypography.numeric.copyWith(color: textColor, fontSize: 9),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(canvas, Offset(x + 4, 3));
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) =>
      oldDelegate.pixelsPerSecond != pixelsPerSecond || oldDelegate.totalWidth != totalWidth;
}
