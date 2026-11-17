import 'package:flutter/material.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';

/// Top Bar conforming to MVP UI/UX Design Spec §3.1 (Height 48px).
///
/// Features project title, atomic save indicator, undo/redo, export trigger,
/// settings trigger, and dark/light theme switch.
class TopBar extends StatelessWidget {
  final EditorController controller;
  final VoidCallback onExportPressed;
  final VoidCallback onThemeToggle;
  final VoidCallback onAiPressed;
  final bool isDarkMode;
  final bool isAiActive;

  const TopBar({
    super.key,
    required this.controller,
    required this.onExportPressed,
    required this.onThemeToggle,
    required this.onAiPressed,
    required this.isDarkMode,
    required this.isAiActive,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);
    final projectName =
        controller.currentProjectPath?.split('/').last ?? 'Untitled.ssproj';

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: colors.surface1,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Logo & Name
          Icon(Icons.movie_filter, color: colors.accent, size: 20),
          const SizedBox(width: 8),
          Text(
            'Shadow Studio',
            style: ShadowTypography.title
                .copyWith(color: colors.textPrimary, fontSize: 14),
          ),
          const SizedBox(width: 16),
          Container(width: 1, height: 18, color: colors.border),
          const SizedBox(width: 16),

          // Project Name Badge
          Icon(Icons.folder_open, size: 16, color: colors.textSecondary),
          const SizedBox(width: 6),
          Text(
            projectName,
            style: ShadowTypography.body.copyWith(
                color: colors.textSecondary, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 16),

          // Save Indicator
          InkWell(
            onTap: controller.isSaving ? null : () => controller.saveProject(),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(
                    controller.isSaving
                        ? Icons.sync
                        : Icons.check_circle_outline,
                    size: 14,
                    color:
                        controller.isSaving ? colors.warning : colors.success,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    controller.isSaving ? 'Saving...' : 'Saved ✓',
                    style: ShadowTypography.caption
                        .copyWith(color: colors.textPrimary),
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // Undo / Redo
          IconButton(
            icon: const Icon(Icons.undo, size: 18),
            color: controller.canUndo ? colors.textPrimary : colors.textMuted,
            tooltip: 'Undo (Ctrl+Z)',
            onPressed: controller.canUndo ? controller.undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo, size: 18),
            color: controller.canRedo ? colors.textPrimary : colors.textMuted,
            tooltip: 'Redo (Ctrl+Y)',
            onPressed: controller.canRedo ? controller.redo : null,
          ),

          const SizedBox(width: 12),
          Container(width: 1, height: 18, color: colors.border),
          const SizedBox(width: 8),

          // AI Agent dock toggle
          TextButton.icon(
            onPressed: onAiPressed,
            icon: Icon(Icons.auto_awesome,
                size: 16,
                color: isAiActive ? colors.accent : colors.textSecondary),
            label: Text(
              'AI',
              style: ShadowTypography.caption.copyWith(
                color: isAiActive ? colors.accent : colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: TextButton.styleFrom(
              backgroundColor:
                  isAiActive ? colors.accent.withValues(alpha: 0.12) : null,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),

          const SizedBox(width: 8),

          // Theme Switch
          IconButton(
            icon:
                Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode, size: 18),
            color: colors.textSecondary,
            tooltip:
                isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            onPressed: onThemeToggle,
          ),

          const SizedBox(width: 8),

          // Export Button
          FilledButton.icon(
            onPressed: onExportPressed,
            icon: const Icon(Icons.file_upload, size: 16),
            label: const Text('Export'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.onAccent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              textStyle:
                  ShadowTypography.body.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
