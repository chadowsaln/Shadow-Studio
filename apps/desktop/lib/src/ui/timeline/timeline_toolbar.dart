import 'package:editing_core/editing_core.dart';
import 'package:flutter/material.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';

/// Toolbar above the timeline tracks providing tool selection, magnetic snapping,
/// track management, and zoom controls.
class TimelineToolbar extends StatelessWidget {
  final EditorController controller;
  final VoidCallback onFitPressed;

  const TimelineToolbar({
    super.key,
    required this.controller,
    required this.onFitPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: colors.surface2,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Select Tool (V)
          _ToolButton(
            icon: Icons.navigation_outlined,
            label: 'Select (V)',
            isActive: controller.toolMode == ToolMode.select,
            onPressed: () => controller.setToolMode(ToolMode.select),
          ),
          const SizedBox(width: 4),

          // Razor Tool (C)
          _ToolButton(
            icon: Icons.content_cut,
            label: 'Razor (C)',
            isActive: controller.toolMode == ToolMode.razor,
            onPressed: () => controller.setToolMode(ToolMode.razor),
          ),
          const SizedBox(width: 4),

          // Magnetic Snapping Toggle (S)
          _ToolButton(
            icon: Icons.straighten,
            label: 'Snap',
            isActive: controller.snappingEnabled,
            onPressed: controller.toggleSnapping,
          ),

          const SizedBox(width: 8),
          Container(width: 1, height: 16, color: colors.border),
          const SizedBox(width: 8),

          // Split At Playhead
          IconButton(
            icon: const Icon(Icons.splitscreen, size: 16),
            color: controller.selectedClipId != null ? colors.textPrimary : colors.textMuted,
            tooltip: 'Split Selected Clip at Playhead',
            onPressed: controller.selectedClipId != null && controller.selectedTrackId != null
                ? () => controller.splitClipAtPlayhead(
                      controller.selectedTrackId!,
                      controller.selectedClipId!,
                    )
                : null,
          ),

          // Delete Selected Clip
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            color: controller.selectedClipId != null ? colors.danger : colors.textMuted,
            tooltip: 'Delete Selected Clip (Delete/Backspace)',
            onPressed: controller.selectedClipId != null ? controller.deleteSelectedClip : null,
          ),

          const SizedBox(width: 8),
          Container(width: 1, height: 16, color: colors.border),
          const SizedBox(width: 8),

          // Add Track Popup Menu
          PopupMenuButton<TrackKind>(
            tooltip: 'Add Track',
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 14, color: colors.textSecondary),
                const SizedBox(width: 2),
                Text(
                  'Track',
                  style: ShadowTypography.caption.copyWith(color: colors.textSecondary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            padding: EdgeInsets.zero,
            color: colors.surface2,
            onSelected: (kind) => controller.addTrack(kind),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: TrackKind.video,
                child: Row(
                  children: [
                    Icon(Icons.videocam, size: 16, color: colors.trackVideo),
                    const SizedBox(width: 8),
                    const Text('Video Track'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: TrackKind.audio,
                child: Row(
                  children: [
                    Icon(Icons.audiotrack, size: 16, color: colors.trackAudio),
                    const SizedBox(width: 8),
                    const Text('Audio Track'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: TrackKind.overlay,
                child: Row(
                  children: [
                    Icon(Icons.title, size: 16, color: colors.trackOverlay),
                    const SizedBox(width: 8),
                    const Text('Overlay / Text Track'),
                  ],
                ),
              ),
            ],
          ),

          // Track Height Selector
          PopupMenuButton<double>(
            tooltip: 'Track Height',
            icon: Icon(Icons.table_rows_outlined, size: 16, color: colors.textSecondary),
            color: colors.surface2,
            onSelected: (h) => controller.setTrackHeight(h),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 36.0, child: Text('Compact (36px)')),
              const PopupMenuItem(value: 48.0, child: Text('Normal (48px)')),
              const PopupMenuItem(value: 64.0, child: Text('Expanded (64px)')),
            ],
          ),

          const Spacer(),

          // Fit to timeline
          TextButton.icon(
            onPressed: onFitPressed,
            icon: const Icon(Icons.fullscreen, size: 14),
            label: const Text('Fit'),
            style: TextButton.styleFrom(
              foregroundColor: colors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              textStyle: ShadowTypography.caption.copyWith(fontWeight: FontWeight.w600),
            ),
          ),

          const SizedBox(width: 6),

          // Zoom Out (-)
          IconButton(
            icon: const Icon(Icons.remove, size: 16),
            color: colors.textSecondary,
            tooltip: 'Zoom Out (Ctrl+-)',
            onPressed: controller.zoomOut,
          ),

          // Zoom Level Indicator
          Text(
            '${controller.pixelsPerSecond.round()} px/s',
            style: ShadowTypography.caption.copyWith(color: colors.textMuted, fontSize: 10),
          ),

          // Zoom In (+)
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            color: colors.textSecondary,
            tooltip: 'Zoom In (Ctrl+=)',
            onPressed: controller.zoomIn,
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onPressed;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? colors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isActive ? colors.onAccent : colors.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: ShadowTypography.caption.copyWith(
                color: isActive ? colors.onAccent : colors.textSecondary,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
