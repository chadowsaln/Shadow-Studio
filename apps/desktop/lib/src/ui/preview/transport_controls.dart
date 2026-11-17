import 'package:flutter/material.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';
import '../../utils/timecode_formatter.dart';

/// Transport Controls bar for Preview playback, frame stepping, and scrubber.
class TransportControls extends StatelessWidget {
  final EditorController controller;

  const TransportControls({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);
    final totalTicks = controller.totalDurationTicks;
    final currentTicks = controller.playheadTicks.clamp(0, totalTicks);

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: colors.surface1,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Jump to Start
          IconButton(
            icon: const Icon(Icons.skip_previous, size: 20),
            color: colors.textSecondary,
            tooltip: 'Jump to Start (Home)',
            onPressed: () => controller.seek(0),
          ),

          // Step Back 1 Frame
          IconButton(
            icon: const Icon(Icons.arrow_left, size: 22),
            color: colors.textSecondary,
            tooltip: 'Previous Frame (Left Arrow)',
            onPressed: () => controller.stepFrame(-1),
          ),

          // Play / Pause Toggle
          IconButton(
            icon: Icon(controller.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 30),
            color: colors.accent,
            tooltip: 'Play / Pause (Space)',
            onPressed: controller.togglePlayPause,
          ),

          // Step Forward 1 Frame
          IconButton(
            icon: const Icon(Icons.arrow_right, size: 22),
            color: colors.textSecondary,
            tooltip: 'Next Frame (Right Arrow)',
            onPressed: () => controller.stepFrame(1),
          ),

          // Jump to End
          IconButton(
            icon: const Icon(Icons.skip_next, size: 20),
            color: colors.textSecondary,
            tooltip: 'Jump to End (End)',
            onPressed: () => controller.seek(totalTicks),
          ),

          const SizedBox(width: 12),

          // Current Timecode vs Total Duration
          Text(
            '${TimecodeFormatter.format(currentTicks)} / ${TimecodeFormatter.format(totalTicks)}',
            style: ShadowTypography.numeric.copyWith(color: colors.textPrimary, fontSize: 12),
          ),

          const SizedBox(width: 16),

          // Scrub Slider
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                activeTrackColor: colors.accent,
                inactiveTrackColor: colors.surface2,
                thumbColor: colors.playhead,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: currentTicks.toDouble(),
                min: 0.0,
                max: totalTicks > 0 ? totalTicks.toDouble() : 1.0,
                onChanged: (val) => controller.seek(val.round()),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Safe Area Toggle Button
          IconButton(
            icon: Icon(Icons.aspect_ratio, size: 18, color: controller.showSafeArea ? colors.accent : colors.textMuted),
            tooltip: 'Toggle Safe Area Guides',
            onPressed: controller.toggleSafeArea,
          ),
        ],
      ),
    );
  }
}
