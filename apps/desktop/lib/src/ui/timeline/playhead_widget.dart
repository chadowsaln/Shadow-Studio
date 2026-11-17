import 'package:flutter/material.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';
import '../../utils/timecode_formatter.dart';

/// Playhead indicator line with timecode flag badge and interactive scrubbing handle.
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
      left: x - 35,
      top: 0,
      bottom: 0,
      width: 70,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          final deltaSeconds = details.delta.dx / pps;
          final deltaTicks = (deltaSeconds * 1000000).round();
          final candidateTicks = (controller.playheadTicks + deltaTicks).clamp(0, 1000000000);
          final snappedTicks = controller.snapTick(candidateTicks);
          controller.seek(snappedTicks);
        },
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            // Vertical Red Line spanning the entire timeline
            Positioned(
              left: 34.25,
              top: 22,
              bottom: 0,
              width: 1.5,
              child: Container(
                decoration: BoxDecoration(
                  color: colors.playhead,
                  boxShadow: [
                    BoxShadow(
                      color: colors.playhead.withOpacity(0.6),
                      blurRadius: 4,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
              ),
            ),

            // Top Playhead Scrubber Flag Badge with Timecode
            Positioned(
              top: 1,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: colors.playhead,
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      TimecodeFormatter.format(controller.playheadTicks),
                      style: ShadowTypography.numeric.copyWith(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  CustomPaint(
                    size: const Size(8, 4),
                    painter: _FlagPointerPainter(color: colors.playhead),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlagPointerPainter extends CustomPainter {
  final Color color;

  _FlagPointerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FlagPointerPainter oldDelegate) =>
      oldDelegate.color != color;
}
