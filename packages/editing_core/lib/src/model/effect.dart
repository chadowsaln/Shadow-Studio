import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'param.dart';

/// Effect entity aligned with RenderGraph Effect definition.
@immutable
class Effect {
  final String id;
  final String effectKey;
  final bool enabled;
  final List<Param> params;

  const Effect({
    required this.id,
    required this.effectKey,
    this.enabled = true,
    this.params = const [],
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'effect_key': effectKey,
        'enabled': enabled,
        'params': params.map((p) => p.toJson()).toList(),
      };

  factory Effect.fromJson(Map<String, Object?> json) {
    final rawParams = (json['params'] as List<dynamic>?) ?? const [];
    return Effect(
      id: json['id'] as String,
      effectKey: json['effect_key'] as String,
      enabled: (json['enabled'] as bool?) ?? true,
      params: rawParams
          .map((p) => Param.fromJson((p as Map).cast<String, Object?>()))
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Effect &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          effectKey == other.effectKey &&
          enabled == other.enabled &&
          const ListEquality<Param>().equals(params, other.params);

  @override
  int get hashCode => Object.hash(
        id,
        effectKey,
        enabled,
        const ListEquality<Param>().hash(params),
      );

  @override
  String toString() => 'Effect(id: $id, key: $effectKey, params: ${params.length})';
}
