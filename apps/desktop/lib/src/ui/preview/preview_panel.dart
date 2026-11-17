import 'package:flutter/material.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';
import 'audio_vu_meter.dart';
import 'preview_canvas.dart';
import 'transport_controls.dart';

/// Center-top Preview panel combining the viewport canvas, stereo VU meters,
/// viewport toolbar (aspect ratio, safe areas, zoom), and transport bar.
class PreviewPanel extends StatelessWidget {
  final EditorController controller;

  const PreviewPanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);

    return Container(
      color: colors.surface0,
      child: Column(
        children: [
          // Preview Viewport Header Toolbar
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: colors.surface2,
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.monitor, size: 14, color: colors.accent),
                const SizedBox(width: 6),
                Text(
                  'Program Monitor',
                  style: ShadowTypography.caption.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),

                // Aspect Ratio Selector
                PopupMenuButton<double>(
                  tooltip: 'Aspect Ratio',
                  icon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.aspect_ratio, size: 14, color: colors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        controller.aspectRatio == 16 / 9
                            ? '16:9'
                            : controller.aspectRatio == 9 / 16
                                ? '9:16'
                                : controller.aspectRatio == 1.0
                                    ? '1:1'
                                    : '4:3',
                        style: ShadowTypography.numeric.copyWith(color: colors.textSecondary, fontSize: 10),
                      ),
                    ],
                  ),
                  color: colors.surface2,
                  onSelected: (ratio) => controller.setAspectRatio(ratio),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 16 / 9, child: Text('16:9 (Landscape)')),
                    const PopupMenuItem(value: 9 / 16, child: Text('9:16 (Shorts/Reels)')),
                    const PopupMenuItem(value: 1.0, child: Text('1:1 (Square)')),
                    const PopupMenuItem(value: 4 / 3, child: Text('4:3 (Classic SD)')),
                  ],
                ),

                const SizedBox(width: 6),

                // Safe Areas Toggle
                Tooltip(
                  message: controller.showSafeArea ? 'Hide Safe Margins' : 'Show Safe Margins (Action/Title)',
                  child: InkWell(
                    onTap: controller.toggleSafeArea,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Icon(
                        Icons.grid_on,
                        size: 14,
                        color: controller.showSafeArea ? colors.accent : colors.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Main Canvas with side Audio VU Meter
          Expanded(
            child: Row(
              children: [
                Expanded(child: PreviewCanvas(controller: controller)),
                AudioVuMeter(controller: controller),
              ],
            ),
          ),

          // Transport Controls Bar
          TransportControls(controller: controller),
        ],
      ),
    );
  }
}
