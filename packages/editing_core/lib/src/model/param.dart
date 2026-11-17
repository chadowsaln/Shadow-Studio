import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'keyframe.dart';

/// Param entity aligned with RenderGraph Param definition.
@immutable
class Param {
  final String name;
  final String type; // 'int', 'ppm', 'color', 'enum', 'string', 'bool'
  final Object value;
  final List<Keyframe> keyframes;

  const Param({
    required this.name,
    required this.type,
    required this.value,
    this.keyframes = const [],
  })  : assert(
          type == 'int' ||
              type == 'ppm' ||
              type == 'color' ||
              type == 'enum' ||
              type == 'string' ||
              type == 'bool',
          'type must be int, ppm, color, enum, string, or bool',
        );

  Map<String, Object?> toJson() => {
        'name': name,
        'type': type,
        'value': value,
        'keyframes': keyframes.map((k) => k.toJson()).toList(),
      };

  factory Param.fromJson(Map<String, Object?> json) {
    final rawKeyframes = (json['keyframes'] as List<dynamic>?) ?? const [];
    return Param(
      name: json['name'] as String,
      type: json['type'] as String,
      value: json['value'] as Object,
      keyframes: rawKeyframes
          .map((k) => Keyframe.fromJson((k as Map).cast<String, Object?>()))
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Param &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          type == other.type &&
          value == other.value &&
          const ListEquality<Keyframe>().equals(keyframes, other.keyframes);

  @override
  int get hashCode => Object.hash(
        name,
        type,
        value,
        const ListEquality<Keyframe>().hash(keyframes),
      );

  @override
  String toString() => 'Param(name: $name, type: $type, val: $value, kfs: ${keyframes.length})';
}
