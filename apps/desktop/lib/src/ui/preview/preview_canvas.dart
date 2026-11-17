import 'package:flutter/material.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';
import '../../utils/timecode_formatter.dart';

/// Viewport Canvas for video preview with dynamic aspect ratio and safe area overlays.
class PreviewCanvas extends StatelessWidget {
  final EditorController controller;

  const PreviewCanvas({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);

    // Find active clip at current playhead position
    String? activeClipLabel;
    String? activeTrackKind;
    for (final track in controller.document.tracks) {
      for (final clip in track.clips) {
        if (controller.playheadTicks >= clip.timelineStartTicks &&
            controller.playheadTicks < clip.timelineEndTicks) {
          activeClipLabel = clip.label ?? clip.id;
          activeTrackKind = track.kind.name;
          break;
        }
      }
      if (activeClipLabel != null) break;
    }

    return Container(
      color: colors.surface0,
      padding: const EdgeInsets.all(12),
      child: Center(
        child: AspectRatio(
          aspectRatio: controller.aspectRatio,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: colors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // Rendered Canvas Content / Mock Viewer
                Center(
                  child: activeClipLabel != null
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              activeTrackKind == 'video'
                                  ? Icons.movie_outlined
                                  : activeTrackKind == 'audio'
                                      ? Icons.graphic_eq
                                      : Icons.title,
                              size: 44,
                              color: colors.accent,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              activeClipLabel,
                              style: ShadowTypography.title.copyWith(color: Colors.white, fontSize: 15),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: colors.surface2.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                'Track: $activeTrackKind',
                                style: ShadowTypography.caption.copyWith(color: colors.accent, fontSize: 10),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.tv_off, size: 36, color: colors.textMuted.withOpacity(0.5)),
                            const SizedBox(height: 8),
                            Text(
                              'No media at playhead',
                              style: ShadowTypography.body.copyWith(color: colors.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                ),

                // Safe Areas Overlay (Spec S2)
                if (controller.showSafeArea)
                  CustomPaint(
                    size: Size.infinite,
                    painter: _SafeAreaPainter(borderColor: colors.border.withOpacity(0.5)),
                  ),

                // Timecode Overlay in Bottom Right
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Text(
                      TimecodeFormatter.format(controller.playheadTicks),
                      style: ShadowTypography.numeric.copyWith(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // Resolution badge in Top Left
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${controller.document.profile.width}x${controller.document.profile.height}',
                      style: ShadowTypography.numeric.copyWith(color: colors.textSecondary, fontSize: 9),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SafeAreaPainter extends CustomPainter {
  final Color borderColor;

  _SafeAreaPainter({required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Action Safe: 90% of viewport
    final actionSafe = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.90,
      height: size.height * 0.90,
    );
    canvas.drawRect(actionSafe, paint);

    // Title Safe: 80% of viewport
    final titleSafe = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.80,
      height: size.height * 0.80,
    );
    canvas.drawRect(titleSafe, paint);

    // Center Crosshair
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawLine(Offset(center.dx - 8, center.dy), Offset(center.dx + 8, center.dy), paint);
    canvas.drawLine(Offset(center.dx, center.dy - 8), Offset(center.dx, center.dy + 8), paint);
  }

  @override
  bool shouldRepaint(covariant _SafeAreaPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor;
  }
}
