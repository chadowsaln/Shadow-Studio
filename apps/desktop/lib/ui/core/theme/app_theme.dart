import 'package:flutter/material.dart';

import 'tokens.dart';

/// Cairo first for Arabic, then the platform UI faces. No font files are
/// bundled yet, so the fallback chain is what renders (see README).
const _uiFallback = <String>[
  'Cairo',
  'Noto Sans Arabic',
  'Noto Sans',
  'Segoe UI',
  'Tahoma',
];

const _numFallback = <String>[
  'IBM Plex Mono',
  'JetBrains Mono',
  'DejaVu Sans Mono',
  'Segoe UI',
];

TextTheme _textTheme(ShadowTokens t) {
  TextStyle style(double size, FontWeight weight, Color color) => TextStyle(
    fontFamilyFallback: _uiFallback,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: 1.55,
  );

  return TextTheme(
    // 13px is the app's body size; the chrome around it is 11–12px.
    bodyLarge: style(14, FontWeight.w400, t.textPrimary),
    bodyMedium: style(13, FontWeight.w400, t.textPrimary),
    bodySmall: style(11, FontWeight.w400, t.textSecondary),
    labelLarge: style(12, FontWeight.w600, t.textPrimary),
    labelMedium: style(11, FontWeight.w400, t.textSecondary),
    labelSmall: style(10, FontWeight.w400, t.textMuted),
    titleMedium: style(13, FontWeight.w600, t.textPrimary),
    titleSmall: style(12, FontWeight.w600, t.textPrimary),
  );
}

ThemeData buildShadowTheme(Brightness brightness) {
  final t = brightness == Brightness.dark
      ? ShadowTokens.dark
      : ShadowTokens.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.accent,
    onPrimary: t.onAccent,
    secondary: t.selection,
    onSecondary: t.surface0,
    error: t.danger,
    onError: t.onAccent,
    surface: t.surface1,
    onSurface: t.textPrimary,
    surfaceContainerHighest: t.surface2,
    outline: t.border,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.surface0,
    canvasColor: t.surface1,
    dividerColor: t.border,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textTheme: _textTheme(t),
    extensions: <ThemeExtension<dynamic>>[t],
    dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: TextStyle(
        fontFamilyFallback: _uiFallback,
        fontSize: 11,
        color: t.surface0,
      ),
      decoration: BoxDecoration(
        color: t.textPrimary,
        borderRadius: BorderRadius.circular(4),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.textSecondary,
        minimumSize: const Size(Metrics.controlMinSize, Metrics.controlMinSize),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        minimumSize: const Size(Metrics.controlMinSize, Metrics.controlMinSize),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        textStyle: const TextStyle(
          fontFamilyFallback: _uiFallback,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
  );
}

/// Monospaced digits for timecodes and any numeric readout (§2.1).
TextStyle numericStyle(
  BuildContext context, {
  double size = 11,
  Color? color,
  FontWeight weight = FontWeight.w400,
}) {
  final t = Theme.of(context).extension<ShadowTokens>()!;
  return TextStyle(
    fontFamilyFallback: _numFallback,
    fontSize: size,
    fontWeight: weight,
    color: color ?? t.textSecondary,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}
