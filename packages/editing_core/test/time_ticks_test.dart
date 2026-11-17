import 'package:editing_core/editing_core.dart';
import 'package:test/test.dart';

void main() {
  group('TimeTicks', () {
    test('round-trips tick/frame at NTSC 30000/1001 perfectly for 10,000 frames', () {
      const fpsNum = 30000;
      const fpsDen = 1001;

      for (var frame = 0; frame < 10000; frame++) {
        final ticks = TimeTicks.frameToTicks(
          frame: frame,
          fpsNum: fpsNum,
          fpsDen: fpsDen,
        );
        final roundTripFrame = TimeTicks.ticksToFrame(
          ticks: ticks,
          fpsNum: fpsNum,
          fpsDen: fpsDen,
        );
        expect(roundTripFrame, equals(frame),
            reason: 'Frame $frame did not round-trip at ticks=$ticks');
      }
    });

    test('round-trips tick/frame at 30 fps (30/1)', () {
      for (var frame = 0; frame < 1000; frame++) {
        final ticks = TimeTicks.frameToTicks(frame: frame, fpsNum: 30, fpsDen: 1);
        final roundTrip = TimeTicks.ticksToFrame(ticks: ticks, fpsNum: 30, fpsDen: 1);
        expect(roundTrip, equals(frame));
      }
    });

    test('round-trips tick/frame at 60 fps (60/1)', () {
      for (var frame = 0; frame < 1000; frame++) {
        final ticks = TimeTicks.frameToTicks(frame: frame, fpsNum: 60, fpsDen: 1);
        final roundTrip = TimeTicks.ticksToFrame(ticks: ticks, fpsNum: 60, fpsDen: 1);
        expect(roundTrip, equals(frame));
      }
    });

    test('round-trips tick/frame at 24 fps (24/1)', () {
      for (var frame = 0; frame < 1000; frame++) {
        final ticks = TimeTicks.frameToTicks(frame: frame, fpsNum: 24, fpsDen: 1);
        final roundTrip = TimeTicks.ticksToFrame(ticks: ticks, fpsNum: 24, fpsDen: 1);
        expect(roundTrip, equals(frame));
      }
    });

    test('spec section 0 exact formula check', () {
      // Frame 0 is always 0 ticks
      expect(TimeTicks.frameToTicks(frame: 0, fpsNum: 30000, fpsDen: 1001), equals(0));
      expect(TimeTicks.ticksToFrame(ticks: 0, fpsNum: 30000, fpsDen: 1001), equals(0));

      // Frame 1 at 30000/1001:
      // ceil(1 * 1e6 * 1001 / 30000) = ceil(1001000000 / 30000) = 33367 ticks
      final frame1Ticks = TimeTicks.frameToTicks(frame: 1, fpsNum: 30000, fpsDen: 1001);
      expect(frame1Ticks, equals(33367));

      // floor(33367 * 30000 / (1e6 * 1001)) = floor(1001010000 / 1001000000) = 1 frame
      final backToFrame1 = TimeTicks.ticksToFrame(ticks: frame1Ticks, fpsNum: 30000, fpsDen: 1001);
      expect(backToFrame1, equals(1));

      // Tick 33366 should floor to frame 0
      expect(TimeTicks.ticksToFrame(ticks: 33366, fpsNum: 30000, fpsDen: 1001), equals(0));
    });

    test('quantizes to frame floor and nearest', () {
      const fpsNum = 30;
      const fpsDen = 1;
      // 1 frame = 33334 ticks at 30fps (ceil(1000000/30) = 33334)
      // Frame 0: 0 ticks
      // Frame 1: 33334 ticks
      // Frame 2: 66667 ticks
      final arbitraryTick = 50000; // Between frame 1 (33334) and frame 2 (66667)

      final floorQuantized = TimeTicks.quantizeToFrameFloor(
        ticks: arbitraryTick,
        fpsNum: fpsNum,
        fpsDen: fpsDen,
      );
      expect(floorQuantized, equals(TimeTicks.frameToTicks(frame: 1, fpsNum: fpsNum, fpsDen: fpsDen)));

      final nearestQuantized = TimeTicks.quantizeToFrameNearest(
        ticks: arbitraryTick,
        fpsNum: fpsNum,
        fpsDen: fpsDen,
      );
      // 50000 is halfway between 33334 and 66667 (distance 16666 vs 16667) -> round to frame 2
      expect(nearestQuantized, equals(TimeTicks.frameToTicks(frame: 2, fpsNum: fpsNum, fpsDen: fpsDen)));
    });

    test('rejects negative ticks or frames with RangeError', () {
      expect(
        () => TimeTicks.ticksToFrame(ticks: -1, fpsNum: 30, fpsDen: 1),
        throwsRangeError,
      );
      expect(
        () => TimeTicks.frameToTicks(frame: -1, fpsNum: 30, fpsDen: 1),
        throwsRangeError,
      );
    });
  });
}
