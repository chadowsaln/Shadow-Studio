import 'package:flutter/material.dart';

import '../../agent/agent_session_controller.dart';
import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';
import '../../utils/timecode_formatter.dart';

/// Status Bar conforming to MVP UI/UX Design Spec §3.3 (Height 28px).
class StatusBar extends StatelessWidget {
  final EditorController controller;
  final AgentSessionController agentSession;

  const StatusBar({
    super.key,
    required this.controller,
    required this.agentSession,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);
    final clipCount = controller.document.tracks
        .fold<int>(0, (sum, t) => sum + t.clips.length);
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
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: colors.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Ready',
            style: ShadowTypography.caption.copyWith(
                color: colors.textPrimary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 16),
          Container(width: 1, height: 12, color: colors.border),
          const SizedBox(width: 16),

          // Revision Counter
          Text(
            'Rev ${controller.revision}',
            style:
                ShadowTypography.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(width: 16),
          Container(width: 1, height: 12, color: colors.border),
          const SizedBox(width: 16),

          // Clip and Asset Counts
          Text(
            '$clipCount clips · $assetCount assets',
            style:
                ShadowTypography.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(width: 16),
          Container(width: 1, height: 12, color: colors.border),
          const SizedBox(width: 16),

          // AI Agent Status
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _aiStatusColor(colors),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'AI: ${_aiStatusLabel()}',
            style: ShadowTypography.caption.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: 16),
          Container(width: 1, height: 12, color: colors.border),
          const SizedBox(width: 16),

          // Zoom Scale
          Text(
            '${controller.pixelsPerSecond.round()} px/s',
            style:
                ShadowTypography.caption.copyWith(color: colors.textSecondary),
          ),

          const Spacer(),

          // Position Timecode
          Text(
            'TC: ${TimecodeFormatter.format(controller.playheadTicks)}',
            style: ShadowTypography.numeric.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }

  String _aiStatusLabel() {
    return switch (agentSession.status) {
      AgentSessionStatus.unconfigured => 'Offline',
      AgentSessionStatus.idle => 'Ready',
      AgentSessionStatus.running => 'Running',
      AgentSessionStatus.succeeded => 'Done',
      AgentSessionStatus.failed => 'Error',
      AgentSessionStatus.cancelled => 'Cancelled',
    };
  }

  Color _aiStatusColor(ShadowColors colors) {
    return switch (agentSession.status) {
      AgentSessionStatus.unconfigured => colors.textMuted,
      AgentSessionStatus.idle => colors.success,
      AgentSessionStatus.running => colors.accent,
      AgentSessionStatus.succeeded => colors.success,
      AgentSessionStatus.failed => colors.danger,
      AgentSessionStatus.cancelled => colors.warning,
    };
  }
}
