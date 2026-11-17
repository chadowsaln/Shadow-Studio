import 'package:desktop/src/utils/timecode_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TimecodeFormatter', () {
    test('formats zero ticks with LTR isolate', () {
      final formatted = TimecodeFormatter.format(0);
      expect(formatted, equals('\u206600:00:00:00\u2069'));
    });

    test('formats zero ticks without LTR isolate when disabled', () {
      final formatted = TimecodeFormatter.format(0, isolateLtr: false);
      expect(formatted, equals('00:00:00:00'));
    });

    test('clamps negative ticks to 0', () {
      final formatted = TimecodeFormatter.format(-500000, isolateLtr: false);
      expect(formatted, equals('00:00:00:00'));
    });

    test('formats 1 second at 30fps (1,000,000 ticks)', () {
      final formatted = TimecodeFormatter.format(
        1000000,
        fpsNumerator: 30,
        fpsDenominator: 1,
        isolateLtr: false,
      );
      expect(formatted, equals('00:00:01:00'));
    });

    test('formats complex time (1 hour, 23 minutes, 45 seconds, 12 frames)', () {
      // At 30 fps:
      // total frames = (1 * 3600 + 23 * 60 + 45) * 30 + 12 = 5025 * 30 + 12 = 150762
      // ticks = 150762 * 1000000 ~/ 30 = 5025400000 ticks
      const totalFrames = (1 * 3600 + 23 * 60 + 45) * 30 + 12;
      const ticks = (totalFrames * 1000000) ~/ 30;
      final formatted = TimecodeFormatter.format(
        ticks,
        fpsNumerator: 30,
        fpsDenominator: 1,
        isolateLtr: false,
      );
      expect(formatted, equals('01:23:45:12'));
    });

    test('protects timecode from bidirectional text reordering', () {
      final raw = TimecodeFormatter.format(
        1000000,
        fpsNumerator: 30,
        fpsDenominator: 1,
        isolateLtr: true,
      );
      expect(raw.startsWith('\u2066'), isTrue);
      expect(raw.endsWith('\u2069'), isTrue);
      expect(raw.contains('00:00:01:00'), isTrue);
    });
  });
}
