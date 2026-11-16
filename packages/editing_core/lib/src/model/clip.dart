import 'package:meta/meta.dart';

/// Clip kinds supported by the editor.
enum ClipKind {
  video,
  audio,
  image,
  color,
  adjustment;

  String get wireName => name;

  static ClipKind fromWireName(String value) {
    return ClipKind.values.firstWhere(
      (k) => k.wireName == value,
      orElse: () => throw ArgumentError('Unknown clip kind: $value'),
    );
  }
}

/// Clip entity aligned with RenderGraph VideoClip / AudioClip schemas.
///
/// Immutable representation of an arranged timeline slice.
@immutable
class Clip {
  final String id;
  final String? assetId;
  final ClipKind kind;
  final int timelineStartTicks;
  final int durationTicks;
  final int sourceInTicks;
  final int speedNum;
  final int speedDen;
  final bool enabled;
  final String? label;
  final int streamIndex;

  // Video properties
  final int opacityPpm; // 0 to 1,000,000 (parts-per-million)

  // Audio properties
  final int gainMb;     // -60,000 to +24,000 (millibels)
  final int panPpm;     // -1,000,000 to +1,000,000
  final int fadeInTicks;
  final int fadeOutTicks;

  const Clip({
    required this.id,
    this.assetId,
    required this.kind,
    required this.timelineStartTicks,
    required this.durationTicks,
    this.sourceInTicks = 0,
    this.speedNum = 1,
    this.speedDen = 1,
    this.enabled = true,
    this.label,
    this.streamIndex = -1,
    this.opacityPpm = 1000000,
    this.gainMb = 0,
    this.panPpm = 0,
    this.fadeInTicks = 0,
    this.fadeOutTicks = 0,
  })  : assert(timelineStartTicks >= 0, 'timelineStartTicks must be >= 0'),
        assert(durationTicks >= 1, 'durationTicks must be >= 1'),
        assert(sourceInTicks >= 0, 'sourceInTicks must be >= 0'),
        assert(speedNum >= 1, 'speedNum must be >= 1'),
        assert(speedDen >= 1, 'speedDen must be >= 1'),
        assert(opacityPpm >= 0 && opacityPpm <= 1000000, 'opacityPpm must be 0..1000000'),
        assert(gainMb >= -60000 && gainMb <= 24000, 'gainMb must be -60000..24000'),
        assert(panPpm >= -1000000 && panPpm <= 1000000, 'panPpm must be -1000000..1000000'),
        assert(fadeInTicks >= 0, 'fadeInTicks must be >= 0'),
        assert(fadeOutTicks >= 0, 'fadeOutTicks must be >= 0');

  /// Creates a video clip.
  factory Clip.video({
    required String id,
    required String assetId,
    required int timelineStartTicks,
    required int durationTicks,
    int sourceInTicks = 0,
    int speedNum = 1,
    int speedDen = 1,
    bool enabled = true,
    String? label,
    int streamIndex = -1,
    int opacityPpm = 1000000,
  }) {
    return Clip(
      id: id,
      assetId: assetId,
      kind: ClipKind.video,
      timelineStartTicks: timelineStartTicks,
      durationTicks: durationTicks,
      sourceInTicks: sourceInTicks,
      speedNum: speedNum,
      speedDen: speedDen,
      enabled: enabled,
      label: label,
      streamIndex: streamIndex,
      opacityPpm: opacityPpm,
    );
  }

  /// Creates an audio clip.
  factory Clip.audio({
    required String id,
    required String assetId,
    required int timelineStartTicks,
    required int durationTicks,
    int sourceInTicks = 0,
    int speedNum = 1,
    int speedDen = 1,
    bool enabled = true,
    String? label,
    int streamIndex = -1,
    int gainMb = 0,
    int panPpm = 0,
    int fadeInTicks = 0,
    int fadeOutTicks = 0,
  }) {
    return Clip(
      id: id,
      assetId: assetId,
      kind: ClipKind.audio,
      timelineStartTicks: timelineStartTicks,
      durationTicks: durationTicks,
      sourceInTicks: sourceInTicks,
      speedNum: speedNum,
      speedDen: speedDen,
      enabled: enabled,
      label: label,
      streamIndex: streamIndex,
      gainMb: gainMb,
      panPpm: panPpm,
      fadeInTicks: fadeInTicks,
      fadeOutTicks: fadeOutTicks,
    );
  }

  /// Timeline end tick [timelineStartTicks, timelineEndTicks).
  int get timelineEndTicks => timelineStartTicks + durationTicks;

  /// Effective duration consumed in the source asset, accounting for speed.
  int get sourceDurationTicks => (durationTicks * speedNum) ~/ speedDen;

  /// Source end tick in the underlying asset.
  int get sourceEndTicks => sourceInTicks + sourceDurationTicks;

  Clip copyWith({
    String? id,
    String? assetId,
    ClipKind? kind,
    int? timelineStartTicks,
    int? durationTicks,
    int? sourceInTicks,
    int? speedNum,
    int? speedDen,
    bool? enabled,
    String? label,
    int? streamIndex,
    int? opacityPpm,
    int? gainMb,
    int? panPpm,
    int? fadeInTicks,
    int? fadeOutTicks,
  }) {
    return Clip(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      kind: kind ?? this.kind,
      timelineStartTicks: timelineStartTicks ?? this.timelineStartTicks,
      durationTicks: durationTicks ?? this.durationTicks,
      sourceInTicks: sourceInTicks ?? this.sourceInTicks,
      speedNum: speedNum ?? this.speedNum,
      speedDen: speedDen ?? this.speedDen,
      enabled: enabled ?? this.enabled,
      label: label ?? this.label,
      streamIndex: streamIndex ?? this.streamIndex,
      opacityPpm: opacityPpm ?? this.opacityPpm,
      gainMb: gainMb ?? this.gainMb,
      panPpm: panPpm ?? this.panPpm,
      fadeInTicks: fadeInTicks ?? this.fadeInTicks,
      fadeOutTicks: fadeOutTicks ?? this.fadeOutTicks,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'asset_id': assetId,
        'kind': kind.wireName,
        'timeline_start_ticks': timelineStartTicks,
        'duration_ticks': durationTicks,
        'source_in_ticks': sourceInTicks,
        'speed_num': speedNum,
        'speed_den': speedDen,
        'enabled': enabled,
        if (label != null) 'label': label,
        'stream_index': streamIndex,
        'opacity_ppm': opacityPpm,
        'gain_mb': gainMb,
        'pan_ppm': panPpm,
        'fade_in_ticks': fadeInTicks,
        'fade_out_ticks': fadeOutTicks,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Clip &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          assetId == other.assetId &&
          kind == other.kind &&
          timelineStartTicks == other.timelineStartTicks &&
          durationTicks == other.durationTicks &&
          sourceInTicks == other.sourceInTicks &&
          speedNum == other.speedNum &&
          speedDen == other.speedDen &&
          enabled == other.enabled &&
          label == other.label &&
          streamIndex == other.streamIndex &&
          opacityPpm == other.opacityPpm &&
          gainMb == other.gainMb &&
          panPpm == other.panPpm &&
          fadeInTicks == other.fadeInTicks &&
          fadeOutTicks == other.fadeOutTicks;

  @override
  int get hashCode => Object.hashAll([
        id,
        assetId,
        kind,
        timelineStartTicks,
        durationTicks,
        sourceInTicks,
        speedNum,
        speedDen,
        enabled,
        label,
        streamIndex,
        opacityPpm,
        gainMb,
        panPpm,
        fadeInTicks,
        fadeOutTicks,
      ]);

  @override
  String toString() =>
      'Clip(id: $id, kind: ${kind.name}, start: $timelineStartTicks, dur: $durationTicks, in: $sourceInTicks)';
}
