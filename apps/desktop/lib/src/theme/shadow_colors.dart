import 'package:flutter/material.dart';

/// Semantic color tokens conforming to MVP UI/UX Design Spec §2.1 (SS-UX-001).
///
/// Contrast ratios: WCAG AA compliant (>= 4.5:1 text, >= 3.0:1 graphical elements).
class ShadowColors extends ThemeExtension<ShadowColors> {
  final Color surface0;
  final Color surface1;
  final Color surface2;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color onAccent;
  final Color playhead;
  final Color selection;
  final Color danger;
  final Color warning;
  final Color success;
  final Color trackVideo;
  final Color trackAudio;
  final Color trackOverlay;

  const ShadowColors({
    required this.surface0,
    required this.surface1,
    required this.surface2,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.onAccent,
    required this.playhead,
    required this.selection,
    required this.danger,
    required this.warning,
    required this.success,
    required this.trackVideo,
    required this.trackAudio,
    required this.trackOverlay,
  });

  /// Default dark palette (Spec §2.1).
  static const dark = ShadowColors(
    surface0: Color(0xFF0E0F12),
    surface1: Color(0xFF16181D),
    surface2: Color(0xFF1E2229),
    border: Color(0xFF2A2F38),
    textPrimary: Color(0xFFECEDEF),
    textSecondary: Color(0xFFAEB6C2),
    textMuted: Color(0xFF7C8696),
    accent: Color(0xFF6A4DFF),
    onAccent: Color(0xFFFFFFFF),
    playhead: Color(0xFFFF4D4D),
    selection: Color(0xFF8FC3FF),
    danger: Color(0xFFFF6B6B),
    warning: Color(0xFFF5A524),
    success: Color(0xFF3DDC97),
    trackVideo: Color(0xFF2B3A55),
    trackAudio: Color(0xFF1F3B34),
    trackOverlay: Color(0xFF3A2E4D),
  );

  /// Light palette (Spec §2.1).
  static const light = ShadowColors(
    surface0: Color(0xFFFAFAFB),
    surface1: Color(0xFFFFFFFF),
    surface2: Color(0xFFF1F2F5),
    border: Color(0xFFD8DBE0),
    textPrimary: Color(0xFF14161A),
    textSecondary: Color(0xFF4A5361),
    textMuted: Color(0xFF6B7482),
    accent: Color(0xFF5B3DE6),
    onAccent: Color(0xFFFFFFFF),
    playhead: Color(0xFFD92B2B),
    selection: Color(0xFF2B6CB0),
    danger: Color(0xFFB42318),
    warning: Color(0xFF8A5A00),
    success: Color(0xFF137A4B),
    trackVideo: Color(0xFFDCE6F5),
    trackAudio: Color(0xFFD9EFE7),
    trackOverlay: Color(0xFFE6DEF4),
  );

  @override
  ThemeExtension<ShadowColors> copyWith({
    Color? surface0,
    Color? surface1,
    Color? surface2,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? onAccent,
    Color? playhead,
    Color? selection,
    Color? danger,
    Color? warning,
    Color? success,
    Color? trackVideo,
    Color? trackAudio,
    Color? trackOverlay,
  }) {
    return ShadowColors(
      surface0: surface0 ?? this.surface0,
      surface1: surface1 ?? this.surface1,
      surface2: surface2 ?? this.surface2,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      playhead: playhead ?? this.playhead,
      selection: selection ?? this.selection,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      success: success ?? this.success,
      trackVideo: trackVideo ?? this.trackVideo,
      trackAudio: trackAudio ?? this.trackAudio,
      trackOverlay: trackOverlay ?? this.trackOverlay,
    );
  }

  @override
  ThemeExtension<ShadowColors> lerp(ThemeExtension<ShadowColors>? other, double t) {
    if (other is! ShadowColors) return this;
    return ShadowColors(
      surface0: Color.lerp(surface0, other.surface0, t)!,
      surface1: Color.lerp(surface1, other.surface1, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      playhead: Color.lerp(playhead, other.playhead, t)!,
      selection: Color.lerp(selection, other.selection, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
      trackVideo: Color.lerp(trackVideo, other.trackVideo, t)!,
      trackAudio: Color.lerp(trackAudio, other.trackAudio, t)!,
      trackOverlay: Color.lerp(trackOverlay, other.trackOverlay, t)!,
    );
  }

  static ShadowColors of(BuildContext context) {
    return Theme.of(context).extension<ShadowColors>() ?? dark;
  }
}
