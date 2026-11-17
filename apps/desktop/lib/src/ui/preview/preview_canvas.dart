import 'package:flutter/material.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';
import '../../utils/timecode_formatter.dart';

/// 16:9 Viewport Canvas for video preview and safe area overlays.
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
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(color: colors.border),
            ),
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
                              size: 48,
                              color: colors.accent,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              activeClipLabel,
                              style: ShadowTypography.title.copyWith(color: Colors.white, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Track: $activeTrackKind',
                              style: ShadowTypography.caption.copyWith(color: colors.textSecondary),
                            ),
                          ],
                        )
                      : Text(
                          'No Media at Current Time',
                          style: ShadowTypography.body.copyWith(color: colors.textMuted),
                        ),
                ),

                // Safe Areas Overlay (Spec S2)
                if (controller.showSafeArea)
                  CustomPaint(
                    size: Size.infinite,
                    painter: _SafeAreaPainter(borderColor: colors.border.withOpacity(0.4)),
                  ),

                // Timecode Overlay in Bottom Right
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      TimecodeFormatter.format(controller.playheadTicks),
                      style: ShadowTypography.numeric.copyWith(color: Colors.white, fontSize: 13),
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

    // Action Safe: 90% (5% margin)
    final actionSafe = Rect.fromLTWH(
      size.width * 0.05,
      size.height * 0.05,
      size.width * 0.90,
      size.height * 0.90,
    );
    canvas.drawRect(actionSafe, paint);

    // Title Safe: 80% (10% margin)
    final titleSafe = Rect.fromLTWH(
      size.width * 0.10,
      size.height * 0.10,
      size.width * 0.80,
      size.height * 0.80,
    );
    canvas.drawRect(titleSafe, paint);
  }

  @override
  bool shouldRepaint(covariant _SafeAreaPainter oldDelegate) =>
      oldDelegate.borderColor != borderColor;
}
