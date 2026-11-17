import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'render_graph_clip.dart';
import 'text_layer.dart';
import 'track.dart';
import 'transition.dart';

/// Resolved Track entity aligned strictly with RenderGraph schema (#/$defs/Track).
/// Closed object schema: no extraneous fields.
@immutable
class RenderGraphTrack {
  final String id;
  final TrackKind kind;
  final int position;
  final String name;
  final bool enabled;
  final int? gainMb;
  final int? panPpm;
  final List<RenderGraphVideoClip>? clips;
  final List<RenderGraphAudioClip>? audioClips;
  final List<TextLayer>? textLayers;
  final List<Transition>? transitions;

  const RenderGraphTrack({
    required this.id,
    required this.kind,
    required this.position,
    required this.name,
    this.enabled = true,
    this.gainMb,
    this.panPpm,
    this.clips,
    this.audioClips,
    this.textLayers,
    this.transitions,
  }) : assert(position >= 0, 'position must be >= 0');

  Map<String, Object?> toJson() {
    final map = <String, Object?>{
      'id': id,
      'kind': kind.wireName,
      'position': position,
      'name': name,
      'enabled': enabled,
    };

    if (kind == TrackKind.video) {
      map['clips'] = clips?.map((c) => c.toJson()).toList() ?? const [];
      if (transitions != null && transitions!.isNotEmpty) {
        map['transitions'] = transitions!.map((t) => t.toJson()).toList();
      }
    } else if (kind == TrackKind.audio) {
      map['gain_mb'] = gainMb ?? 0;
      map['pan_ppm'] = panPpm ?? 0;
      map['audio_clips'] =
          audioClips?.map((c) => c.toJson()).toList() ?? const [];
    } else if (kind == TrackKind.overlay) {
      map['text_layers'] =
          textLayers?.map((t) => t.toJson()).toList() ?? const [];
    }

    return map;
  }

  factory RenderGraphTrack.fromJson(Map<String, Object?> json) {
    final kind = TrackKind.fromWireName(json['kind'] as String);

    List<RenderGraphVideoClip>? clips;
    if (json.containsKey('clips') && json['clips'] != null) {
      final raw = json['clips'] as List<dynamic>;
      clips = raw
          .map((c) => RenderGraphVideoClip.fromJson((c as Map).cast<String, Object?>()))
          .toList();
    }

    List<RenderGraphAudioClip>? audioClips;
    if (json.containsKey('audio_clips') && json['audio_clips'] != null) {
      final raw = json['audio_clips'] as List<dynamic>;
      audioClips = raw
          .map((c) => RenderGraphAudioClip.fromJson((c as Map).cast<String, Object?>()))
          .toList();
    }

    List<TextLayer>? textLayers;
    if (json.containsKey('text_layers') && json['text_layers'] != null) {
      final raw = json['text_layers'] as List<dynamic>;
      textLayers = raw
          .map((t) => TextLayer.fromJson((t as Map).cast<String, Object?>()))
          .toList();
    }

    List<Transition>? transitions;
    if (json.containsKey('transitions') && json['transitions'] != null) {
      final raw = json['transitions'] as List<dynamic>;
      transitions = raw
          .map((t) => Transition.fromJson((t as Map).cast<String, Object?>()))
          .toList();
    }

    return RenderGraphTrack(
      id: json['id'] as String,
      kind: kind,
      position: json['position'] as int,
      name: json['name'] as String,
      enabled: (json['enabled'] as bool?) ?? true,
      gainMb: json['gain_mb'] as int?,
      panPpm: json['pan_ppm'] as int?,
      clips: clips,
      audioClips: audioClips,
      textLayers: textLayers,
      transitions: transitions,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RenderGraphTrack &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          kind == other.kind &&
          position == other.position &&
          name == other.name &&
          enabled == other.enabled &&
          gainMb == other.gainMb &&
          panPpm == other.panPpm &&
          const DeepCollectionEquality().equals(clips, other.clips) &&
          const DeepCollectionEquality().equals(audioClips, other.audioClips) &&
          const DeepCollectionEquality().equals(textLayers, other.textLayers) &&
          const DeepCollectionEquality().equals(transitions, other.transitions);

  @override
  int get hashCode => Object.hash(
        id,
        kind,
        position,
        name,
        enabled,
        gainMb,
        panPpm,
        const DeepCollectionEquality().hash(clips),
        const DeepCollectionEquality().hash(audioClips),
        const DeepCollectionEquality().hash(textLayers),
        const DeepCollectionEquality().hash(transitions),
      );
}
