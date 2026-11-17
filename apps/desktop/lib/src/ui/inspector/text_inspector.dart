import 'package:flutter/material.dart';

import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';

/// Text layer inspector supporting Arabic RTL text input and styling (Spec §2.2).
class TextInspector extends StatefulWidget {
  final String initialText;
  final ValueChanged<String>? onTextChanged;

  const TextInspector({
    super.key,
    this.initialText = 'عنوان تجريبي',
    this.onTextChanged,
  });

  @override
  State<TextInspector> createState() => _TextInspectorState();
}

class _TextInspectorState extends State<TextInspector> {
  late final TextEditingController _textController;
  double _fontSize = 36.0;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TEXT LAYER (العربية)',
          style: ShadowTypography.caption.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),

        // Arabic RTL Text Field
        Directionality(
          textDirection: TextDirection.rtl,
          child: TextField(
            controller: _textController,
            style: ShadowTypography.body.copyWith(
              color: colors.textPrimary,
              fontSize: 14,
              fontFamily: ShadowTypography.fontCairo,
            ),
            decoration: InputDecoration(
              hintText: 'اكتب نص العنوان هنا...',
              hintStyle: ShadowTypography.body.copyWith(color: colors.textMuted),
              filled: true,
              fillColor: colors.surface0,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: colors.accent),
              ),
            ),
            onChanged: widget.onTextChanged,
          ),
        ),
        const SizedBox(height: 12),

        // Font Size Slider
        Row(
          children: [
            Text('Font Size', style: ShadowTypography.body.copyWith(color: colors.textPrimary, fontSize: 12)),
            const Spacer(),
            Text('${_fontSize.round()} pt', style: ShadowTypography.numeric.copyWith(color: colors.textSecondary)),
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
            value: _fontSize,
            min: 12.0,
            max: 96.0,
            onChanged: (val) => setState(() => _fontSize = val),
          ),
        ),
      ],
    );
  }
}
