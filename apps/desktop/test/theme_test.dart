import 'package:desktop/src/theme/shadow_colors.dart';
import 'package:desktop/src/theme/shadow_theme.dart';
import 'package:desktop/src/theme/shadow_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShadowTheme and Tokens', () {
    test('Dark theme tokens match Spec §2.1', () {
      const darkColors = ShadowColors.dark;
      expect(darkColors.surface0, equals(const Color(0xFF0E0F12)));
      expect(darkColors.surface1, equals(const Color(0xFF16181D)));
      expect(darkColors.surface2, equals(const Color(0xFF1E2229)));
      expect(darkColors.border, equals(const Color(0xFF2A2F38)));
      expect(darkColors.accent, equals(const Color(0xFF6A4DFF)));
      expect(darkColors.playhead, equals(const Color(0xFFFF4D4D)));
      expect(darkColors.selection, equals(const Color(0xFF8FC3FF)));
    });

    test('Light theme tokens match Spec §2.1', () {
      const lightColors = ShadowColors.light;
      expect(lightColors.surface0, equals(const Color(0xFFFAFAFB)));
      expect(lightColors.surface1, equals(const Color(0xFFFFFFFF)));
      expect(lightColors.border, equals(const Color(0xFFD8DBE0)));
      expect(lightColors.accent, equals(const Color(0xFF5B3DE6)));
    });

    test('ThemeData construction for Dark and Light modes', () {
      final darkTheme = ShadowTheme.dark();
      expect(darkTheme.brightness, equals(Brightness.dark));
      expect(darkTheme.scaffoldBackgroundColor, equals(const Color(0xFF0E0F12)));

      final lightTheme = ShadowTheme.light();
      expect(lightTheme.brightness, equals(Brightness.light));
      expect(lightTheme.scaffoldBackgroundColor, equals(const Color(0xFFFAFAFB)));
    });

    test('Typography uses Cairo and IBM Plex Mono fonts', () {
      expect(ShadowTypography.title.fontFamily, equals('Cairo'));
      expect(ShadowTypography.body.fontFamily, equals('Cairo'));
      expect(ShadowTypography.numeric.fontFamily, equals('IBMPlexMono'));
      expect(ShadowTypography.numeric.fontFamilyFallback, contains('monospace'));
    });
  });
}
