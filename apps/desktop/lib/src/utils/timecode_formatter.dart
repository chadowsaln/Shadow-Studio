import 'package:editing_core/editing_core.dart';

/// Formats integer ticks into standard SMPTE timecode (HH:MM:SS:FF).
///
/// Strictly uses integer math and embeds Unicode LTR isolation markers
/// (\u2066 ... \u2069) to protect timecode digits from RTL reversal (Spec §2.2).
class TimecodeFormatter {
  /// Formats [ticks] at given [fpsNumerator] / [fpsDenominator] (default 30 fps).
  static String format(
    int ticks, {
    int fpsNumerator = 30000,
    int fpsDenominator = 1001,
    bool isolateLtr = true,
  }) {
    final safeTicks = ticks < 0 ? 0 : ticks;
    final frame = TimeTicks.ticksToFrame(
      ticks: safeTicks,
      fpsNum: fpsNumerator,
      fpsDen: fpsDenominator,
    );

    final fps = (fpsNumerator / fpsDenominator).round().clamp(1, 120);
    final totalSeconds = frame ~/ fps;
    final f = frame % fps;

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    final hStr = hours.toString().padLeft(2, '0');
    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');
    final fStr = f.toString().padLeft(2, '0');

    final code = '$hStr:$mStr:$sStr:$fStr';
    if (isolateLtr) {
      // U+2066 Left-to-Right Isolate, U+2069 Pop Directional Isolate
      return '\u2066$code\u2069';
    }
    return code;
  }
}
