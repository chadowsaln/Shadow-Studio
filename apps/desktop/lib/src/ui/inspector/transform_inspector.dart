import 'package:flutter/material.dart';

import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';

/// Transform properties inspector for adjusting X, Y, Scale, and Opacity.
class TransformInspector extends StatefulWidget {
  final double initialX;
  final double initialY;
  final double initialScale;
  final double initialOpacity;
  final ValueChanged<double>? onOpacityChanged;

  const TransformInspector({
    super.key,
    this.initialX = 0.0,
    this.initialY = 0.0,
    this.initialScale = 1.0,
    this.initialOpacity = 1.0,
    this.onOpacityChanged,
  });

  @override
  State<TransformInspector> createState() => _TransformInspectorState();
}

class _TransformInspectorState extends State<TransformInspector> {
  late double _opacity;
  late double _scale;

  @override
  void initState() {
    super.initState();
    _opacity = widget.initialOpacity;
    _scale = widget.initialScale;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TRANSFORM',
          style: ShadowTypography.caption.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),

        // Position X & Y
        Row(
          children: [
            Expanded(
              child: _NumberField(
                label: 'Position X',
                value: widget.initialX.toStringAsFixed(0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NumberField(
                label: 'Position Y',
                value: widget.initialY.toStringAsFixed(0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Scale
        Row(
          children: [
            Text('Scale', style: ShadowTypography.body.copyWith(color: colors.textPrimary, fontSize: 12)),
            const Spacer(),
            Text('${(_scale * 100).round()}%', style: ShadowTypography.numeric.copyWith(color: colors.textSecondary)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            activeTrackColor: colors.accent,
            inactiveTrackColor: colors.surface2,
            thumbColor: colors.accent,
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            value: _scale,
            min: 0.1,
            max: 3.0,
            onChanged: (val) => setState(() => _scale = val),
          ),
        ),
        const SizedBox(height: 8),

        // Opacity
        Row(
          children: [
            Text('Opacity', style: ShadowTypography.body.copyWith(color: colors.textPrimary, fontSize: 12)),
            const Spacer(),
            Text('${(_opacity * 100).round()}%', style: ShadowTypography.numeric.copyWith(color: colors.textSecondary)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            activeTrackColor: colors.accent,
            inactiveTrackColor: colors.surface2,
            thumbColor: colors.accent,
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            value: _opacity,
            min: 0.0,
            max: 1.0,
            onChanged: (val) {
              setState(() => _opacity = val);
              widget.onOpacityChanged?.call(val);
            },
          ),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final String value;

  const _NumberField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surface0,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: ShadowTypography.caption.copyWith(color: colors.textMuted, fontSize: 10)),
          const SizedBox(height: 2),
          Text(value, style: ShadowTypography.numeric.copyWith(color: colors.textPrimary, fontSize: 12)),
        ],
      ),
    );
  }
}
