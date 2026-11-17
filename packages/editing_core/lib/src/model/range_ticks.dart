import 'package:meta/meta.dart';

/// Timeline tick range [startTicks, startTicks + durationTicks).
///
/// Follows RenderGraph Range definition:
/// start_ticks (>= 0), duration_ticks (>= 1, maximum 21,600,000,000 = 6 hours).
@immutable
class RangeTicks {
  final int startTicks;
  final int durationTicks;

  const RangeTicks({
    required this.startTicks,
    required this.durationTicks,
  })  : assert(startTicks >= 0, 'startTicks must be non-negative'),
        assert(durationTicks >= 1, 'durationTicks must be positive');

  int get endTicks => startTicks + durationTicks;

  bool containsTick(int tick) => tick >= startTicks && tick < endTicks;

  bool overlaps(RangeTicks other) {
    return startTicks < other.endTicks && other.startTicks < endTicks;
  }

  Map<String, int> toJson() => {
        'start_ticks': startTicks,
        'duration_ticks': durationTicks,
      };

  factory RangeTicks.fromJson(Map<String, Object?> json) {
    return RangeTicks(
      startTicks: json['start_ticks'] as int,
      durationTicks: json['duration_ticks'] as int,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RangeTicks &&
          runtimeType == other.runtimeType &&
          startTicks == other.startTicks &&
          durationTicks == other.durationTicks;

  @override
  int get hashCode => Object.hash(startTicks, durationTicks);

  @override
  String toString() => 'RangeTicks([$startTicks, $endTicks), duration: $durationTicks)';
}
