import 'package:editing_core/editing_core.dart' as core;
import 'package:flutter/material.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';

/// Left-hand track control header displaying track label, kind, and mute/solo controls.
class TrackHeader extends StatelessWidget {
  final core.Track track;
  final EditorController? controller;
  final double height;

  const TrackHeader({
    super.key,
    required this.track,
    this.controller,
    this.height = 48.0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);
    final isVideo = track.kind == core.TrackKind.video;
    final isAudio = track.kind == core.TrackKind.audio;

    return Container(
      height: height,
      width: 140,
      decoration: BoxDecoration(
        color: colors.surface2,
        border: Border(
          bottom: BorderSide(color: colors.border.withOpacity(0.5)),
          right: BorderSide(color: colors.border),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Track Kind Icon with color
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: isVideo
                  ? colors.trackVideo.withOpacity(0.3)
                  : isAudio
                      ? colors.trackAudio.withOpacity(0.3)
                      : colors.trackOverlay.withOpacity(0.3),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Icon(
              isVideo
                  ? Icons.videocam
                  : isAudio
                      ? Icons.audiotrack
                      : Icons.title,
              size: 13,
              color: isVideo
                  ? colors.trackVideo
                  : isAudio
                      ? colors.trackAudio
                      : colors.trackOverlay,
            ),
          ),
          const SizedBox(width: 6),

          // Track Name / Label
          Expanded(
            child: Text(
              track.name.isNotEmpty ? track.name : track.id,
              style: ShadowTypography.caption.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Mute / Visibility Toggle
          Tooltip(
            message: track.enabled ? 'Mute/Disable' : 'Unmute/Enable',
            child: InkWell(
              onTap: () {
                // Future toggle state
              },
              child: Icon(
                track.enabled ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 14,
                color: track.enabled ? colors.textSecondary : colors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 4),

          // Delete Track (if more than 1 track)
          if (controller != null && controller!.document.tracks.length > 1)
            Tooltip(
              message: 'Remove Track',
              child: InkWell(
                onTap: () => controller!.removeTrack(track.id),
                child: Icon(
                  Icons.close,
                  size: 13,
                  color: colors.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
