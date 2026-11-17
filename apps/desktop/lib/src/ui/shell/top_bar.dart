import 'package:flutter/material.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';
import '../../utils/timecode_formatter.dart';
import 'shortcuts_dialog.dart';

/// Top Bar conforming to MVP UI/UX Design Spec §3.1 (Height 48px).
///
/// Features workspace mode tabs, master timecode display, editable project title,
/// atomic save with dirty indicator, undo/redo, shortcuts guide, export trigger,
/// and dark/light theme switch.
class TopBar extends StatelessWidget {
  final EditorController controller;
  final VoidCallback onExportPressed;
  final VoidCallback onThemeToggle;
  final bool isDarkMode;

  const TopBar({
    super.key,
    required this.controller,
    required this.onExportPressed,
    required this.onThemeToggle,
    required this.isDarkMode,
  });

  void _showRenameDialog(BuildContext context, ShadowColors colors) {
    final textController = TextEditingController(text: controller.projectName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface1,
        title: Text('Rename Project', style: ShadowTypography.title.copyWith(color: colors.textPrimary)),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Enter project name',
            fillColor: colors.surface0,
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.accent),
            onPressed: () {
              if (textController.text.trim().isNotEmpty) {
                controller.setProjectName(textController.text.trim());
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: colors.surface1,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // 1. Logo & Name
          Icon(Icons.movie_filter, color: colors.accent, size: 20),
          const SizedBox(width: 8),
          Text(
            'Shadow Studio',
            style: ShadowTypography.title.copyWith(color: colors.textPrimary, fontSize: 14),
          ),
          const SizedBox(width: 14),
          Container(width: 1, height: 18, color: colors.border),
          const SizedBox(width: 14),

          // 2. Project Name Badge (Clickable to Rename)
          Tooltip(
            message: 'Click to rename project',
            child: InkWell(
              onTap: () => _showRenameDialog(context, colors),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.folder_open, size: 15, color: colors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      controller.projectName,
                      style: ShadowTypography.body.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.edit, size: 11, color: colors.textMuted),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // 3. Workspace Mode Switcher Tabs (Media, Edit, Color, Audio, Deliver)
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildModeTab('الوسائط', false, colors),
                  const SizedBox(width: 2),
                  _buildModeTab('المونتاج', true, colors),
                  const SizedBox(width: 2),
                  _buildModeTab('الألوان', false, colors),
                  const SizedBox(width: 2),
                  _buildModeTab('الصوت', false, colors),
                  const SizedBox(width: 2),
                  _buildModeTab('التسليم', false, colors, onTap: onExportPressed),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // 4. Center Master Sequence Timecode
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colors.surface0,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: colors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  TimecodeFormatter.format(controller.playheadTicks),
                  style: ShadowTypography.numeric.copyWith(
                    color: colors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // 5. Save Indicator Button
          Tooltip(
            message: controller.isDirty ? 'Unsaved changes (Click or Ctrl+S to save)' : 'Project saved to disk',
            child: InkWell(
              onTap: controller.isSaving ? null : () => controller.saveProject(),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: controller.isDirty ? colors.warning.withOpacity(0.5) : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      controller.isSaving
                          ? Icons.sync
                          : controller.isDirty
                              ? Icons.circle
                              : Icons.check_circle_outline,
                      size: controller.isDirty ? 9 : 13,
                      color: controller.isSaving
                          ? colors.warning
                          : controller.isDirty
                              ? colors.warning
                              : colors.success,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      controller.isSaving
                          ? 'جاري الحفظ...'
                          : controller.isDirty
                              ? 'حفظ *'
                              : 'حفظ تلقائي ✓',
                      style: ShadowTypography.caption.copyWith(
                        color: controller.isDirty ? colors.warning : colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // 6. Keyboard Shortcuts Dialog Button
          IconButton(
            icon: const Icon(Icons.help_outline, size: 18),
            color: colors.textSecondary,
            tooltip: 'Keyboard Shortcuts Help',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => const ShortcutsDialog(),
              );
            },
          ),

          // 7. Undo / Redo
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

          const SizedBox(width: 8),
          Container(width: 1, height: 18, color: colors.border),
          const SizedBox(width: 8),

          // 8. Theme Switch
          IconButton(
            icon: Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode, size: 18),
            color: colors.textSecondary,
            tooltip: isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            onPressed: onThemeToggle,
          ),

          const SizedBox(width: 8),

          // 9. Export Button
          FilledButton.icon(
            onPressed: onExportPressed,
            icon: const Icon(Icons.file_upload, size: 15),
            label: const Text('Export'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.onAccent,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
              textStyle: ShadowTypography.body.copyWith(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab(String label, bool isActive, ShadowColors colors, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isActive ? colors.surface0 : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? colors.border : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: ShadowTypography.caption.copyWith(
            color: isActive ? colors.textPrimary : colors.textMuted,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}
