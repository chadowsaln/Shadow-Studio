import 'package:flutter/material.dart';

import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';

/// Modal dialog displaying comprehensive desktop keyboard shortcuts.
class ShortcutsDialog extends StatelessWidget {
  const ShortcutsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);

    final shortcuts = [
      {'key': 'Space', 'desc': 'Toggle Playback / Pause'},
      {'key': 'V', 'desc': 'Selection Tool'},
      {'key': 'C', 'desc': 'Razor / Split Tool'},
      {'key': 'S', 'desc': 'Toggle Magnetic Snapping'},
      {'key': 'Delete / Backspace', 'desc': 'Remove Selected Clip'},
      {'key': 'Ctrl + Z', 'desc': 'Undo Last Transaction'},
      {'key': 'Ctrl + Y / Ctrl+Shift+Z', 'desc': 'Redo Last Transaction'},
      {'key': 'Ctrl + S', 'desc': 'Save Project Atomically'},
      {'key': 'Left / Right Arrow', 'desc': 'Step 1 Frame Back / Forward'},
      {'key': 'Shift + Left / Right', 'desc': 'Step 1 Second Back / Forward'},
      {'key': 'Home / End', 'desc': 'Jump to Timeline Start / End'},
      {'key': '+ / -', 'desc': 'Zoom In / Out Timeline'},
      {'key': 'F', 'desc': 'Fit Timeline to Viewport'},
    ];

    return Dialog(
      backgroundColor: colors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      ),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.keyboard, color: colors.accent, size: 22),
                const SizedBox(width: 10),
                Text(
                  'Keyboard Shortcuts',
                  style: ShadowTypography.title.copyWith(color: colors.textPrimary, fontSize: 16),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: colors.textSecondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: shortcuts.length,
                separatorBuilder: (_, __) => Divider(color: colors.border.withOpacity(0.4), height: 1),
                itemBuilder: (context, index) {
                  final item = shortcuts[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: colors.surface0,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: colors.border),
                          ),
                          child: Text(
                            item['key']!,
                            style: ShadowTypography.numeric.copyWith(
                              color: colors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            item['desc']!,
                            style: ShadowTypography.body.copyWith(
                              color: colors.textPrimary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
