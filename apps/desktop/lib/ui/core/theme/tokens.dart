import 'package:flutter/material.dart';

/// Design tokens measured in SS-UX-001 §2.1.
///
/// Component code must not use raw colours: it reads these tokens through
/// [ThemeData.colorScheme] / [ShadowTokens] so the light theme stays a
/// single swap.
@immutable
class ShadowTokens extends ThemeExtension<ShadowTokens> {
  const ShadowTokens({
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

  static const dark = ShadowTokens(
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

  static const light = ShadowTokens(
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
  ShadowTokens copyWith({
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
    return ShadowTokens(
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
  ShadowTokens lerp(ThemeExtension<ShadowTokens>? other, double t) {
    if (other is! ShadowTokens) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return ShadowTokens(
      surface0: mix(surface0, other.surface0),
      surface1: mix(surface1, other.surface1),
      surface2: mix(surface2, other.surface2),
      border: mix(border, other.border),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textMuted: mix(textMuted, other.textMuted),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      playhead: mix(playhead, other.playhead),
      selection: mix(selection, other.selection),
      danger: mix(danger, other.danger),
      warning: mix(warning, other.warning),
      success: mix(success, other.success),
      trackVideo: mix(trackVideo, other.trackVideo),
      trackAudio: mix(trackAudio, other.trackAudio),
      trackOverlay: mix(trackOverlay, other.trackOverlay),
    );
  }
}

/// Fixed chrome metrics from SS-UX-001 §3.1.
abstract final class Metrics {
  static const double topBarHeight = 48;
  static const double statusBarHeight = 28;
  static const double mediaBinWidth = 280;
  static const double mediaBinMin = 220;
  static const double mediaBinMax = 420;
  static const double inspectorWidth = 300;
  static const double inspectorMin = 260;
  static const double inspectorMax = 420;
  static const double trackRowHeight = 56;
  static const double rulerHeight = 28;
  static const double timelineMinHeight = 180;
  static const double controlMinSize = 32;
  static const double minWindowWidth = 1024;
  static const double minWindowHeight = 640;
}

/// Window breakpoints from SS-UX-001 §3.1.
abstract final class Breakpoints {
  /// At or below this width the media bin folds into a drawer.
  static const double foldMediaBin = 1280;

  /// At or below this width the inspector becomes a drawer over the content.
  static const double inspectorDrawer = 1100;
}

extension ShadowThemeAccess on BuildContext {
  ShadowTokens get tokens => Theme.of(this).extension<ShadowTokens>()!;
}
