import 'package:flutter/material.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';

/// Playhead indicator line and draggable scrubber handle.
class PlayheadWidget extends StatelessWidget {
  final EditorController controller;
  final double totalHeight;

  const PlayheadWidget({
    super.key,
    required this.controller,
    required this.totalHeight,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);
    final pps = controller.pixelsPerSecond;
    final x = (controller.playheadTicks / 1000000.0) * pps;

    return Positioned(
      left: x - 6,
      top: 0,
      bottom: 0,
      width: 12,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          final deltaSeconds = details.delta.dx / pps;
          final deltaTicks = (deltaSeconds * 1000000).round();
          controller.seek(controller.playheadTicks + deltaTicks);
        },
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            // Vertical Line
            Positioned(
              left: 5.5,
              top: 14,
              bottom: 0,
              width: 1.5,
              child: Container(color: colors.playhead),
            ),

            // Top Scrubber Handle (Triangle head)
            CustomPaint(
              size: const Size(12, 14),
              painter: _PlayheadHandlePainter(color: colors.playhead),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayheadHandlePainter extends CustomPainter {
  final Color color;

  _PlayheadHandlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.6)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(0, size.height * 0.6)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PlayheadHandlePainter oldDelegate) =>
      oldDelegate.color != color;
}
