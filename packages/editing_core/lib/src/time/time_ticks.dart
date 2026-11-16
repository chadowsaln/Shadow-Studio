/// Time and tick calculations for the video editor.
///
/// Hard constraints:
/// - 1 tick = 1/1,000,000 s (integer ticks).
/// - Never use double for time values.
/// - Tick <-> frame conversion follows spec section 0:
///     tick -> frame: floor(tick * fps_num / (1e6 * fps_den))
///     frame -> tick: ceil(frame * 1e6 * fps_den / fps_num)
/// - Frame-boundary rounding happens in Editing Core only.
abstract final class TimeTicks {
  /// Number of integer ticks in one second.
  static const int ticksPerSecond = 1000000;

  /// Converts integer [ticks] to a frame index using floor division.
  ///
  /// Formula: floor(tick * fps_num / (1e6 * fps_den))
  static int ticksToFrame({
    required int ticks,
    required int fpsNum,
    required int fpsDen,
  }) {
    RangeError.checkNotNegative(ticks, 'ticks');
    if (fpsNum <= 0) {
      throw ArgumentError.value(fpsNum, 'fpsNum', 'Must be positive');
    }
    if (fpsDen <= 0) {
      throw ArgumentError.value(fpsDen, 'fpsDen', 'Must be positive');
    }

    final numerator = ticks * fpsNum;
    final denominator = ticksPerSecond * fpsDen;
    return numerator ~/ denominator;
  }

  /// Converts a [frame] index to integer ticks using ceiling division.
  ///
  /// Formula: ceil(frame * 1e6 * fps_den / fps_num)
  static int frameToTicks({
    required int frame,
    required int fpsNum,
    required int fpsDen,
  }) {
    RangeError.checkNotNegative(frame, 'frame');
    if (fpsNum <= 0) {
      throw ArgumentError.value(fpsNum, 'fpsNum', 'Must be positive');
    }
    if (fpsDen <= 0) {
      throw ArgumentError.value(fpsDen, 'fpsDen', 'Must be positive');
    }

    if (frame == 0) return 0;

    final numerator = frame * ticksPerSecond * fpsDen;
    return (numerator + fpsNum - 1) ~/ fpsNum;
  }

  /// Quantizes an arbitrary tick position down to the current frame boundary (floor).
  static int quantizeToFrameFloor({
    required int ticks,
    required int fpsNum,
    required int fpsDen,
  }) {
    final frame = ticksToFrame(ticks: ticks, fpsNum: fpsNum, fpsDen: fpsDen);
    return frameToTicks(frame: frame, fpsNum: fpsNum, fpsDen: fpsDen);
  }

  /// Quantizes an arbitrary tick position to the nearest frame boundary (half-up).
  static int quantizeToFrameNearest({
    required int ticks,
    required int fpsNum,
    required int fpsDen,
  }) {
    RangeError.checkNotNegative(ticks, 'ticks');
    if (fpsNum <= 0) {
      throw ArgumentError.value(fpsNum, 'fpsNum', 'Must be positive');
    }
    if (fpsDen <= 0) {
      throw ArgumentError.value(fpsDen, 'fpsDen', 'Must be positive');
    }

    final denominator = ticksPerSecond * fpsDen;
    // (ticks * fpsNum / denominator) rounded half-up:
    // (ticks * fpsNum * 2 + denominator) ~/ (2 * denominator)
    final frame = (ticks * fpsNum * 2 + denominator) ~/ (2 * denominator);
    return frameToTicks(frame: frame, fpsNum: fpsNum, fpsDen: fpsDen);
  }

  /// Converts seconds and microseconds to integer ticks without double arithmetic.
  static int fromSecondsAndMicroseconds({
    required int seconds,
    int microseconds = 0,
  }) {
    RangeError.checkNotNegative(seconds, 'seconds');
    RangeError.checkNotNegative(microseconds, 'microseconds');
    return seconds * ticksPerSecond + microseconds;
  }
}
