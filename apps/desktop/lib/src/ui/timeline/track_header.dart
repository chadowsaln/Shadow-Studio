import 'package:editing_core/editing_core.dart' as core;
import 'package:flutter/material.dart';

import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';

/// Left-hand track control header displaying track label, kind, and mute/solo controls.
class TrackHeader extends StatelessWidget {
  final core.Track track;
  final double height;

  const TrackHeader({
    super.key,
    required this.track,
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
          bottom: BorderSide(color: colors.border),
          right: BorderSide(color: colors.border),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Track Kind Icon
          Icon(
            isVideo
                ? Icons.videocam_outlined
                : isAudio
                    ? Icons.audiotrack_outlined
                    : Icons.title,
            size: 16,
            color: colors.textSecondary,
          ),
          const SizedBox(width: 6),

          // Track Name / Label
          Expanded(
            child: Text(
              track.name.isNotEmpty ? track.name : track.id,
              style: ShadowTypography.caption.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Mute / Eye Indicator
          Icon(
            track.enabled ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: 14,
            color: track.enabled ? colors.textSecondary : colors.textMuted,
          ),
          const SizedBox(width: 4),

          // Lock Indicator
          Icon(
            Icons.lock_open_outlined,
            size: 14,
            color: colors.textMuted,
          ),
        ],
      ),
    );
  }
}
