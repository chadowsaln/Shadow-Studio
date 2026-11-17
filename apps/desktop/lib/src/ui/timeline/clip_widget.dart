import 'package:editing_core/editing_core.dart' as core;
import 'package:flutter/material.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';
import '../../utils/timecode_formatter.dart';

/// Interactive clip rectangle rendered within a track lane.
class ClipWidget extends StatelessWidget {
  final core.Clip clip;
  final core.Track track;
  final EditorController controller;
  final double height;

  const ClipWidget({
    super.key,
    required this.clip,
    required this.track,
    required this.controller,
    this.height = 40.0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);
    final pps = controller.pixelsPerSecond;

    final startSeconds = clip.timelineStartTicks / 1000000.0;
    final durationSeconds = clip.durationTicks / 1000000.0;

    final leftPos = startSeconds * pps;
    final width = (durationSeconds * pps).clamp(12.0, 50000.0);

    final isSelected = controller.selectedClipId == clip.id;
    final isVideo = track.kind == core.TrackKind.video;
    final isAudio = track.kind == core.TrackKind.audio;

    final bgColor = isVideo
        ? colors.trackVideo
        : isAudio
            ? colors.trackAudio
            : colors.trackOverlay;

    return Positioned(
      left: leftPos,
      top: 4,
      width: width,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          if (controller.toolMode == ToolMode.razor) {
            // Razor tool clicked: compute timeline tick from local tap X
            final localX = details.localPosition.dx;
            final tapSeconds = startSeconds + (localX / pps);
            final tapTicks = (tapSeconds * 1000000).round();
            controller.seek(tapTicks);
            controller.splitClipAtPlayhead(track.id, clip.id);
          } else {
            // Select tool: select clip
            controller.selectClip(clip.id, trackId: track.id);
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? colors.selection : colors.border,
              width: isSelected ? 2.0 : 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Clip Label and Duration text
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      clip.label ?? clip.id,
                      style: ShadowTypography.body.copyWith(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      TimecodeFormatter.format(clip.durationTicks),
                      style: ShadowTypography.numeric.copyWith(
                        color: colors.textSecondary,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),

              // Left Trim Handle
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 8,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: Container(
                    color: isSelected ? colors.selection.withOpacity(0.5) : Colors.transparent,
                  ),
                ),
              ),

              // Right Trim Handle
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 8,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: Container(
                    color: isSelected ? colors.selection.withOpacity(0.5) : Colors.transparent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
