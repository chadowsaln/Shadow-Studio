import 'package:flutter/material.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';

/// Professional stereo audio VU peak meter with dual L/R channels and dB labels.
class AudioVuMeter extends StatelessWidget {
  final EditorController controller;
  final double height;

  const AudioVuMeter({
    super.key,
    required this.controller,
    this.height = 160.0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);
    final levels = controller.audioLevels;
    final leftLevel = levels.isNotEmpty ? levels[0] : 0.0;
    final rightLevel = levels.length > 1 ? levels[1] : 0.0;

    return Container(
      width: 38,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface1,
        border: Border(left: BorderSide(color: colors.border.withOpacity(0.6))),
      ),
      child: Column(
        children: [
          Text(
            'VU',
            style: ShadowTypography.caption.copyWith(
              color: colors.textMuted,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildChannelBar('L', leftLevel, colors),
                const SizedBox(width: 4),
                _buildChannelBar('R', rightLevel, colors),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'dB',
            style: ShadowTypography.caption.copyWith(
              color: colors.textMuted,
              fontSize: 7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelBar(String label, double level, ShadowColors colors) {
    return Column(
      children: [
        Expanded(
          child: Container(
            width: 8,
            decoration: BoxDecoration(
              color: colors.surface0,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: colors.border.withOpacity(0.5), width: 0.5),
            ),
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: level.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1.5),
                  gradient: const LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0xFF10B981), // Green
                      Color(0xFFFBBF24), // Yellow
                      Color(0xFFEF4444), // Red
                    ],
                    stops: [0.65, 0.88, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}
