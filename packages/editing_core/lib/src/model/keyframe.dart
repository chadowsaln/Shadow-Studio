import 'package:meta/meta.dart';

/// Keyframe entity aligned with RenderGraph Keyframe definition.
@immutable
class Keyframe {
  final int atTicks;
  final Object value; // int, bool, or String
  final String easing; // 'linear', 'ease_in', 'ease_out', 'ease_in_out', 'step'

  const Keyframe({
    required this.atTicks,
    required this.value,
    this.easing = 'linear',
  })  : assert(atTicks >= 0, 'atTicks must be >= 0'),
        assert(
          easing == 'linear' ||
              easing == 'ease_in' ||
              easing == 'ease_out' ||
              easing == 'ease_in_out' ||
              easing == 'step',
          'easing must be linear, ease_in, ease_out, ease_in_out, or step',
        );

  Map<String, Object?> toJson() => {
        'at_ticks': atTicks,
        'value': value,
        'easing': easing,
      };

  factory Keyframe.fromJson(Map<String, Object?> json) {
    return Keyframe(
      atTicks: json['at_ticks'] as int,
      value: json['value'] as Object,
      easing: (json['easing'] as String?) ?? 'linear',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Keyframe &&
          runtimeType == other.runtimeType &&
          atTicks == other.atTicks &&
          value == other.value &&
          easing == other.easing;

  @override
  int get hashCode => Object.hash(atTicks, value, easing);

  @override
  String toString() => 'Keyframe(at: $atTicks, val: $value, easing: $easing)';
}
