import 'package:flutter/material.dart';

import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';

/// Contextual audio properties inspector for audio clips.
class AudioInspector extends StatefulWidget {
  const AudioInspector({super.key});

  @override
  State<AudioInspector> createState() => _AudioInspectorState();
}

class _AudioInspectorState extends State<AudioInspector> {
  double _volumeGainDb = 0.0;
  double _pan = 0.0;
  bool _mute = false;

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'AUDIO TRACK & GAIN',
              style: ShadowTypography.caption.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            InkWell(
              onTap: () {
                setState(() {
                  _volumeGainDb = 0.0;
                  _pan = 0.0;
                  _mute = false;
                });
              },
              child: Text(
                'Reset',
                style: ShadowTypography.caption.copyWith(color: colors.accent, fontSize: 10),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Volume Gain dB Slider
        Row(
          children: [
            SizedBox(
              width: 50,
              child: Text('Gain', style: ShadowTypography.body.copyWith(color: colors.textSecondary, fontSize: 11)),
            ),
            Expanded(
              child: Slider(
                value: _volumeGainDb,
                min: -24.0,
                max: 12.0,
                divisions: 36,
                activeColor: colors.accent,
                inactiveColor: colors.surface0,
                onChanged: (val) => setState(() => _volumeGainDb = val),
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(
                '${_volumeGainDb >= 0 ? '+' : ''}${_volumeGainDb.toStringAsFixed(1)} dB',
                style: ShadowTypography.numeric.copyWith(color: colors.textPrimary, fontSize: 10),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),

        // Pan Slider (-1.0 Left to +1.0 Right)
        Row(
          children: [
            SizedBox(
              width: 50,
              child: Text('Pan', style: ShadowTypography.body.copyWith(color: colors.textSecondary, fontSize: 11)),
            ),
            Expanded(
              child: Slider(
                value: _pan,
                min: -1.0,
                max: 1.0,
                divisions: 20,
                activeColor: colors.accent,
                inactiveColor: colors.surface0,
                onChanged: (val) => setState(() => _pan = val),
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(
                _pan == 0.0
                    ? 'Center'
                    : _pan < 0
                        ? 'L ${( -_pan * 100 ).round()}%'
                        : 'R ${( _pan * 100 ).round()}%',
                style: ShadowTypography.numeric.copyWith(color: colors.textPrimary, fontSize: 10),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),

        // Mute Channel Switch
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Mute Channel', style: ShadowTypography.body.copyWith(color: colors.textSecondary, fontSize: 11)),
            Transform.scale(
              scale: 0.75,
              child: Switch(
                value: _mute,
                activeColor: colors.warning,
                onChanged: (val) => setState(() => _mute = val),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
