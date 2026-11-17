import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'clip.dart';
import 'transition.dart';

/// Track kind supported by the editor.
enum TrackKind {
  video,
  audio,
  overlay;

  String get wireName => name;

  static TrackKind fromWireName(String value) {
    return TrackKind.values.firstWhere(
      (k) => k.wireName == value,
      orElse: () => throw ArgumentError('Unknown track kind: $value'),
    );
  }
}

/// Track entity containing arranged clips and transitions.
///
/// Invariants:
/// - No overlapping clips.
/// - Clips are maintained in order by timelineStartTicks.
/// - Track positions are dense 0..n-1 across the document.
@immutable
class Track {
  final String id;
  final TrackKind kind;
  final int position;
  final String name;
  final bool enabled;
  final List<Clip> clips;
  final List<Transition> transitions;
  final int? gainMb;
  final int? panPpm;

  Track({
    required this.id,
    required this.kind,
    required this.position,
    required this.name,
    this.enabled = true,
    Iterable<Clip> clips = const [],
    Iterable<Transition> transitions = const [],
    this.gainMb,
    this.panPpm,
  })  : assert(position >= 0, 'position must be >= 0'),
        clips = _ensureSortedClips(clips),
        transitions = List.unmodifiable(transitions);

  static List<Clip> _ensureSortedClips(Iterable<Clip> clips) {
    if (clips is List<Clip>) {
      var isSorted = true;
      for (var i = 0; i < clips.length - 1; i++) {
        if (clips[i].timelineStartTicks > clips[i + 1].timelineStartTicks) {
          isSorted = false;
          break;
        }
      }
      if (isSorted) {
        return List.unmodifiable(clips);
      }
      final copy = List<Clip>.of(clips);
      copy.sort((a, b) => a.timelineStartTicks.compareTo(b.timelineStartTicks));
      return List.unmodifiable(copy);
    }
    final list = clips.toList();
    list.sort((a, b) => a.timelineStartTicks.compareTo(b.timelineStartTicks));
    return List.unmodifiable(list);
  }

  /// Returns the clip containing [tick], if any.
  Clip? clipAt(int tick) {
    for (final clip in clips) {
      if (tick >= clip.timelineStartTicks && tick < clip.timelineEndTicks) {
        return clip;
      }
    }
    return null;
  }

  /// Finds a clip by ID.
  Clip? findClip(String clipId) {
    for (final clip in clips) {
      if (clip.id == clipId) return clip;
    }
    return null;
  }

  /// Finds the index of a clip by ID, or -1 if not found.
  int findClipIndex(String clipId) {
    return clips.indexWhere((c) => c.id == clipId);
  }

  /// Clips on video tracks (empty on other track kinds).
  List<Clip> get videoClips => kind == TrackKind.video ? clips : const [];

  /// Clips on audio tracks (empty on other track kinds).
  List<Clip> get audioClips => kind == TrackKind.audio ? clips : const [];

  Track copyWith({
    String? id,
    TrackKind? kind,
    int? position,
    String? name,
    bool? enabled,
    List<Clip>? clips,
    List<Transition>? transitions,
    int? gainMb,
    int? panPpm,
  }) {
    return Track(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      position: position ?? this.position,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      clips: clips ?? this.clips,
      transitions: transitions ?? this.transitions,
      gainMb: gainMb ?? this.gainMb,
      panPpm: panPpm ?? this.panPpm,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.wireName,
        'position': position,
        'name': name,
        'enabled': enabled,
        if (kind == TrackKind.video) 'clips': clips.map((c) => c.toJson()).toList(),
        if (kind == TrackKind.audio) 'audio_clips': clips.map((c) => c.toJson()).toList(),
        if (kind == TrackKind.overlay) 'text_layers': const <Map<String, Object?>>[],
        if (kind == TrackKind.video && transitions.isNotEmpty)
          'transitions': transitions.map((t) => t.toJson()).toList(),
        if (gainMb != null) 'gain_mb': gainMb,
        if (panPpm != null) 'pan_ppm': panPpm,
      };

  /// Deserializes a [Track] from a JSON map.
  factory Track.fromJson(Map<String, Object?> json) {
    final kind = TrackKind.fromWireName(json['kind'] as String);
    final rawClips = (json['clips'] as List<dynamic>?) ??
        (json['audio_clips'] as List<dynamic>?) ??
        const [];
    final clips = rawClips
        .map((c) => Clip.fromJson((c as Map).cast<String, Object?>()))
        .toList();

    final rawTransitions = (json['transitions'] as List<dynamic>?) ?? const [];
    final transitions = rawTransitions
        .map((t) => Transition.fromJson((t as Map).cast<String, Object?>()))
        .toList();

    return Track(
      id: json['id'] as String,
      kind: kind,
      position: json['position'] as int,
      name: json['name'] as String,
      enabled: (json['enabled'] as bool?) ?? true,
      clips: clips,
      transitions: transitions,
      gainMb: json['gain_mb'] as int?,
      panPpm: json['pan_ppm'] as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Track &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          kind == other.kind &&
          position == other.position &&
          name == other.name &&
          enabled == other.enabled &&
          gainMb == other.gainMb &&
          panPpm == other.panPpm &&
          const ListEquality<Clip>().equals(clips, other.clips) &&
          const ListEquality<Transition>().equals(transitions, other.transitions);

  @override
  int get hashCode => Object.hash(
        id,
        kind,
        position,
        name,
        enabled,
        gainMb,
        panPpm,
        const ListEquality<Clip>().hash(clips),
        const ListEquality<Transition>().hash(transitions),
      );

  @override
  String toString() =>
      'Track(id: $id, kind: ${kind.name}, pos: $position, name: "$name", clips: ${clips.length})';
}
