import 'package:flutter/material.dart';

import 'shadow_colors.dart';
import 'shadow_typography.dart';

/// Complete theme configuration for Shadow Studio desktop application.
class ShadowTheme {
  static ThemeData dark() {
    const colors = ShadowColors.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: colors.surface0,
      canvasColor: colors.surface1,
      cardColor: colors.surface1,
      dividerColor: colors.border,
      primaryColor: colors.accent,
      colorScheme: ColorScheme.dark(
        primary: colors.accent,
        onPrimary: colors.onAccent,
        surface: colors.surface1,
        onSurface: colors.textPrimary,
        error: colors.danger,
      ),
      textTheme: TextTheme(
        headlineLarge: ShadowTypography.display.copyWith(color: colors.textPrimary),
        titleMedium: ShadowTypography.title.copyWith(color: colors.textPrimary),
        bodyMedium: ShadowTypography.body.copyWith(color: colors.textPrimary),
        bodySmall: ShadowTypography.caption.copyWith(color: colors.textSecondary),
        labelSmall: ShadowTypography.numeric.copyWith(color: colors.textPrimary),
      ),
      extensions: const [colors],
    );
  }

  static ThemeData light() {
    const colors = ShadowColors.light;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: colors.surface0,
      canvasColor: colors.surface1,
      cardColor: colors.surface1,
      dividerColor: colors.border,
      primaryColor: colors.accent,
      colorScheme: ColorScheme.light(
        primary: colors.accent,
        onPrimary: colors.onAccent,
        surface: colors.surface1,
        onSurface: colors.textPrimary,
        error: colors.danger,
      ),
      textTheme: TextTheme(
        headlineLarge: ShadowTypography.display.copyWith(color: colors.textPrimary),
        titleMedium: ShadowTypography.title.copyWith(color: colors.textPrimary),
        bodyMedium: ShadowTypography.body.copyWith(color: colors.textPrimary),
        bodySmall: ShadowTypography.caption.copyWith(color: colors.textSecondary),
        labelSmall: ShadowTypography.numeric.copyWith(color: colors.textPrimary),
      ),
      extensions: const [colors],
    );
  }
}
