import 'package:flutter/material.dart';

/// Typography definitions conforming to MVP UI/UX Design Spec §2.2 (SS-UX-001).
///
/// Uses Cairo for operational and Arabic text, and IBM Plex Mono (or fallback monospace)
/// for isolated LTR numeric timecode values.
class ShadowTypography {
  static const fontCairo = 'Cairo';
  static const fontMono = 'IBMPlexMono';

  static const display = TextStyle(
    fontFamily: fontCairo,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  static const title = TextStyle(
    fontFamily: fontCairo,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const body = TextStyle(
    fontFamily: fontCairo,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const numeric = TextStyle(
    fontFamily: fontMono,
    fontFamilyFallback: ['monospace', 'Courier', 'DejaVu Sans Mono'],
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const caption = TextStyle(
    fontFamily: fontCairo,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );
}
