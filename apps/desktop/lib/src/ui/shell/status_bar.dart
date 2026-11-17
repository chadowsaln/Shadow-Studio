import 'package:flutter/material.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';
import '../../utils/timecode_formatter.dart';

/// Status Bar conforming to MVP UI/UX Design Spec §3.3 (Height 28px).
class StatusBar extends StatelessWidget {
  final EditorController controller;

  const StatusBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);
    final clipCount = controller.document.tracks.fold<int>(0, (sum, t) => sum + t.clips.length);
    final assetCount = controller.mediaLibrary.registry.count;

    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: colors.surface1,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Readiness Dot
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: colors.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Ready',
            style: ShadowTypography.caption.copyWith(color: colors.success, fontWeight: FontWeight.w600, fontSize: 11),
          ),
          const SizedBox(width: 14),
          Container(width: 1, height: 12, color: colors.border),
          const SizedBox(width: 14),

          // Revision Counter
          Text(
            'Rev ${controller.revision}',
            style: ShadowTypography.numeric.copyWith(color: colors.textSecondary, fontSize: 11),
          ),
          const SizedBox(width: 14),
          Container(width: 1, height: 12, color: colors.border),
          const SizedBox(width: 14),

          // Clip and Asset Counts
          Text(
            '$clipCount clips · $assetCount assets',
            style: ShadowTypography.caption.copyWith(color: colors.textSecondary, fontSize: 11),
          ),
          const SizedBox(width: 14),
          Container(width: 1, height: 12, color: colors.border),
          const SizedBox(width: 14),

          // Zoom Scale
          Text(
            '${controller.pixelsPerSecond.round()} px/s',
            style: ShadowTypography.caption.copyWith(color: colors.textSecondary, fontSize: 11),
          ),

          const Spacer(),

          // AI Agent Ready Badge
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 12, color: colors.accent),
              const SizedBox(width: 4),
              Text(
                'AI Ready',
                style: ShadowTypography.caption.copyWith(color: colors.accent, fontWeight: FontWeight.bold, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Container(width: 1, height: 12, color: colors.border),
          const SizedBox(width: 14),

          // Position Timecode
          Text(
            'TC: ${TimecodeFormatter.format(controller.playheadTicks)}',
            style: ShadowTypography.numeric.copyWith(color: colors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
