import 'package:meta/meta.dart';

/// Transition between two adjacent clips on the same track.
///
/// Follows RenderGraph Transition schema:
/// - at_ticks must match the cut point (from_clip.end == to_clip.start).
/// - duration_ticks must be <= half the shorter clip's duration.
@immutable
class Transition {
  final String id;
  final String kind; // 'crossfade', 'dissolve', 'wipe_left', 'wipe_right', 'fade_black'
  final int atTicks;
  final int durationTicks;
  final String fromClipId;
  final String toClipId;

  const Transition({
    required this.id,
    required this.kind,
    required this.atTicks,
    required this.durationTicks,
    required this.fromClipId,
    required this.toClipId,
  })  : assert(atTicks >= 0, 'atTicks must be non-negative'),
        assert(durationTicks >= 1, 'durationTicks must be positive');

  Transition copyWith({
    String? id,
    String? kind,
    int? atTicks,
    int? durationTicks,
    String? fromClipId,
    String? toClipId,
  }) {
    return Transition(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      atTicks: atTicks ?? this.atTicks,
      durationTicks: durationTicks ?? this.durationTicks,
      fromClipId: fromClipId ?? this.fromClipId,
      toClipId: toClipId ?? this.toClipId,
    );
  }

  Map<String, Object> toJson() => {
        'id': id,
        'kind': kind,
        'at_ticks': atTicks,
        'duration_ticks': durationTicks,
        'from_clip_id': fromClipId,
        'to_clip_id': toClipId,
      };

  factory Transition.fromJson(Map<String, Object?> json) {
    return Transition(
      id: json['id'] as String,
      kind: json['kind'] as String,
      atTicks: json['at_ticks'] as int,
      durationTicks: json['duration_ticks'] as int,
      fromClipId: json['from_clip_id'] as String,
      toClipId: json['to_clip_id'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Transition &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          kind == other.kind &&
          atTicks == other.atTicks &&
          durationTicks == other.durationTicks &&
          fromClipId == other.fromClipId &&
          toClipId == other.toClipId;

  @override
  int get hashCode =>
      Object.hash(id, kind, atTicks, durationTicks, fromClipId, toClipId);

  @override
  String toString() =>
      'Transition(id: $id, kind: $kind, at: $atTicks, duration: $durationTicks, from: $fromClipId, to: $toClipId)';
}
