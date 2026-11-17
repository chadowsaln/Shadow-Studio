import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'clip.dart';
import 'effect.dart';
import 'transform_box.dart';

/// Resolved VideoClip entity aligned strictly with RenderGraph schema (#/$defs/VideoClip).
/// Closed object schema: no extraneous fields.
@immutable
class RenderGraphVideoClip {
  final String id;
  final String? assetId;
  final ClipKind kind;
  final String? sourceUri;
  final String? sourceHash;
  final int streamIndex;
  final int timelineStartTicks;
  final int durationTicks;
  final int sourceInTicks;
  final int speedNum;
  final int speedDen;
  final int opacityPpm;
  final bool enabled;
  final String? label;
  final TransformBox transform;
  final List<Effect> effects;

  const RenderGraphVideoClip({
    required this.id,
    this.assetId,
    required this.kind,
    this.sourceUri,
    this.sourceHash,
    this.streamIndex = 0,
    required this.timelineStartTicks,
    required this.durationTicks,
    this.sourceInTicks = 0,
    this.speedNum = 1,
    this.speedDen = 1,
    this.opacityPpm = 1000000,
    this.enabled = true,
    this.label,
    this.transform = const TransformBox.identity(),
    this.effects = const [],
  })  : assert(timelineStartTicks >= 0, 'timelineStartTicks must be >= 0'),
        assert(durationTicks >= 1, 'durationTicks must be >= 1'),
        assert(sourceInTicks >= 0, 'sourceInTicks must be >= 0'),
        assert(speedNum >= 1, 'speedNum must be >= 1'),
        assert(speedDen >= 1, 'speedDen must be >= 1'),
        assert(
          opacityPpm >= 0 && opacityPpm <= 1000000,
          'opacityPpm must be 0..1000000',
        );

  int get timelineEndTicks => timelineStartTicks + durationTicks;

  Map<String, Object?> toJson() => {
        'id': id,
        'asset_id': assetId,
        'kind': kind.wireName,
        'source_uri': sourceUri,
        'source_hash': sourceHash,
        'stream_index': streamIndex,
        'timeline_start_ticks': timelineStartTicks,
        'duration_ticks': durationTicks,
        'source_in_ticks': sourceInTicks,
        'speed_num': speedNum,
        'speed_den': speedDen,
        'opacity_ppm': opacityPpm,
        'enabled': enabled,
        if (label != null) 'label': label,
        'transform': transform.toJson(),
        'effects': effects.map((e) => e.toJson()).toList(),
      };

  factory RenderGraphVideoClip.fromJson(Map<String, Object?> json) {
    final rawEffects = (json['effects'] as List<dynamic>?) ?? const [];
    return RenderGraphVideoClip(
      id: json['id'] as String,
      assetId: json['asset_id'] as String?,
      kind: ClipKind.fromWireName(json['kind'] as String),
      sourceUri: json['source_uri'] as String?,
      sourceHash: json['source_hash'] as String?,
      streamIndex: (json['stream_index'] as int?) ?? 0,
      timelineStartTicks: json['timeline_start_ticks'] as int,
      durationTicks: json['duration_ticks'] as int,
      sourceInTicks: (json['source_in_ticks'] as int?) ?? 0,
      speedNum: (json['speed_num'] as int?) ?? 1,
      speedDen: (json['speed_den'] as int?) ?? 1,
      opacityPpm: (json['opacity_ppm'] as int?) ?? 1000000,
      enabled: (json['enabled'] as bool?) ?? true,
      label: json['label'] as String?,
      transform: json.containsKey('transform')
          ? TransformBox.fromJson(
              (json['transform'] as Map).cast<String, Object?>(),
            )
          : const TransformBox.identity(),
      effects: rawEffects
          .map((e) => Effect.fromJson((e as Map).cast<String, Object?>()))
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RenderGraphVideoClip &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          assetId == other.assetId &&
          kind == other.kind &&
          sourceUri == other.sourceUri &&
          sourceHash == other.sourceHash &&
          streamIndex == other.streamIndex &&
          timelineStartTicks == other.timelineStartTicks &&
          durationTicks == other.durationTicks &&
          sourceInTicks == other.sourceInTicks &&
          speedNum == other.speedNum &&
          speedDen == other.speedDen &&
          opacityPpm == other.opacityPpm &&
          enabled == other.enabled &&
          label == other.label &&
          transform == other.transform &&
          const ListEquality<Effect>().equals(effects, other.effects);

  @override
  int get hashCode => Object.hashAll([
        id,
        assetId,
        kind,
        sourceUri,
        sourceHash,
        streamIndex,
        timelineStartTicks,
        durationTicks,
        sourceInTicks,
        speedNum,
        speedDen,
        opacityPpm,
        enabled,
        label,
        transform,
        const ListEquality<Effect>().hash(effects),
      ]);
}

/// Resolved AudioClip entity aligned strictly with RenderGraph schema (#/$defs/AudioClip).
/// Closed object schema: no extraneous fields.
@immutable
class RenderGraphAudioClip {
  final String id;
  final String? assetId;
  final String? sourceUri;
  final String? sourceHash;
  final int streamIndex;
  final int timelineStartTicks;
  final int durationTicks;
  final int sourceInTicks;
  final int speedNum;
  final int speedDen;
  final int gainMb;
  final int fadeInTicks;
  final int fadeOutTicks;
  final bool enabled;

  const RenderGraphAudioClip({
    required this.id,
    this.assetId,
    this.sourceUri,
    this.sourceHash,
    this.streamIndex = 0,
    required this.timelineStartTicks,
    required this.durationTicks,
    this.sourceInTicks = 0,
    this.speedNum = 1,
    this.speedDen = 1,
    this.gainMb = 0,
    this.fadeInTicks = 0,
    this.fadeOutTicks = 0,
    this.enabled = true,
  })  : assert(timelineStartTicks >= 0, 'timelineStartTicks must be >= 0'),
        assert(durationTicks >= 1, 'durationTicks must be >= 1'),
        assert(sourceInTicks >= 0, 'sourceInTicks must be >= 0'),
        assert(speedNum >= 1, 'speedNum must be >= 1'),
        assert(speedDen >= 1, 'speedDen must be >= 1'),
        assert(
          gainMb >= -60000 && gainMb <= 24000,
          'gainMb must be -60000..24000',
        ),
        assert(fadeInTicks >= 0, 'fadeInTicks must be >= 0'),
        assert(fadeOutTicks >= 0, 'fadeOutTicks must be >= 0');

  int get timelineEndTicks => timelineStartTicks + durationTicks;

  Map<String, Object?> toJson() => {
        'id': id,
        'asset_id': assetId,
        'source_uri': sourceUri,
        'source_hash': sourceHash,
        'stream_index': streamIndex,
        'timeline_start_ticks': timelineStartTicks,
        'duration_ticks': durationTicks,
        'source_in_ticks': sourceInTicks,
        'speed_num': speedNum,
        'speed_den': speedDen,
        'gain_mb': gainMb,
        'fade_in_ticks': fadeInTicks,
        'fade_out_ticks': fadeOutTicks,
        'enabled': enabled,
      };

  factory RenderGraphAudioClip.fromJson(Map<String, Object?> json) {
    return RenderGraphAudioClip(
      id: json['id'] as String,
      assetId: json['asset_id'] as String?,
      sourceUri: json['source_uri'] as String?,
      sourceHash: json['source_hash'] as String?,
      streamIndex: (json['stream_index'] as int?) ?? 0,
      timelineStartTicks: json['timeline_start_ticks'] as int,
      durationTicks: json['duration_ticks'] as int,
      sourceInTicks: (json['source_in_ticks'] as int?) ?? 0,
      speedNum: (json['speed_num'] as int?) ?? 1,
      speedDen: (json['speed_den'] as int?) ?? 1,
      gainMb: (json['gain_mb'] as int?) ?? 0,
      fadeInTicks: (json['fade_in_ticks'] as int?) ?? 0,
      fadeOutTicks: (json['fade_out_ticks'] as int?) ?? 0,
      enabled: (json['enabled'] as bool?) ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RenderGraphAudioClip &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          assetId == other.assetId &&
          sourceUri == other.sourceUri &&
          sourceHash == other.sourceHash &&
          streamIndex == other.streamIndex &&
          timelineStartTicks == other.timelineStartTicks &&
          durationTicks == other.durationTicks &&
          sourceInTicks == other.sourceInTicks &&
          speedNum == other.speedNum &&
          speedDen == other.speedDen &&
          gainMb == other.gainMb &&
          fadeInTicks == other.fadeInTicks &&
          fadeOutTicks == other.fadeOutTicks &&
          enabled == other.enabled;

  @override
  int get hashCode => Object.hashAll([
        id,
        assetId,
        sourceUri,
        sourceHash,
        streamIndex,
        timelineStartTicks,
        durationTicks,
        sourceInTicks,
        speedNum,
        speedDen,
        gainMb,
        fadeInTicks,
        fadeOutTicks,
        enabled,
      ]);
}
