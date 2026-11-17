import 'package:meta/meta.dart';

/// Thrown when a RenderGraph cannot be parsed or violates the v1 contract.
class RenderGraphException implements Exception {
  const RenderGraphException(this.code, this.message, [this.path]);

  /// Stable rejection code from §أ.12 (`RG_*`).
  final String code;
  final String message;

  /// JSON path of the offending node, when known.
  final String? path;

  @override
  String toString() =>
      'RenderGraphException($code${path == null ? '' : ' at $path'}): $message';
}

/// Closed-schema parser for `shadow.rendergraph/1`.
///
/// Every object rejects unknown keys (V-16). Parsing and validation happen in
/// one pass so a graph can never be partially interpreted: either it is a
/// valid [RenderGraphDoc] or it throws [RenderGraphException].
class RenderGraphDoc {
  RenderGraphDoc({
    required this.graphSchema,
    required this.sequenceId,
    required this.projectRevision,
    required this.timebase,
    required this.profile,
    required this.range,
    required this.backgroundRgba,
    required this.tracks,
  });

  final String graphSchema;
  final String sequenceId;
  final int projectRevision;
  final RgTimebase timebase;
  final RgProfile profile;
  final RgRange range;
  final String backgroundRgba;
  final List<RgTrack> tracks;

  double get fps => timebase.fpsNum / timebase.fpsDen;

  int get durationTicks => range.durationTicks;

  int get startTicks => range.startTicks;

  int get endTicks => range.startTicks + range.durationTicks;

  /// Tracks that produce video, ordered bottom-to-top by position.
  List<RgTrack> get videoTracks =>
      tracks.where((t) => t.kind == 'video').toList(growable: false);

  /// Tracks that produce audio, ordered by position.
  List<RgTrack> get audioTracks =>
      tracks.where((t) => t.kind == 'audio').toList(growable: false);

  /// Overlay tracks holding rasterized text layers.
  List<RgTrack> get overlayTracks =>
      tracks.where((t) => t.kind == 'overlay').toList(growable: false);

  static RenderGraphDoc parse(Map<String, Object?> json) {
    _expectOnly(json, const {
      'graph_schema',
      'sequence_id',
      'project_revision',
      'timebase',
      'profile',
      'range',
      'background_rgba',
      'tracks',
    }, 'graph');

    final schema = json['graph_schema'];
    if (schema != 'shadow.rendergraph/1') {
      throw RenderGraphException(
        'RG_SCHEMA_VERSION',
        'Unsupported graph_schema "$schema"',
        'graph_schema',
      );
    }

    final sequenceId = _string(json['sequence_id'], 'sequence_id', 'graph');
    if (!_uuidV7Pattern.hasMatch(sequenceId)) {
      throw RenderGraphException(
        'RG_SCHEMA_VERSION',
        'sequence_id must be a UUIDv7',
        'sequence_id',
      );
    }

    final revision = _int(
      json['project_revision'],
      'project_revision',
      'graph',
    );
    if (revision < 0) {
      throw RenderGraphException(
        'RG_SCHEMA_VERSION',
        'project_revision must be >= 0',
        'project_revision',
      );
    }

    final rawTracks = json['tracks'];
    if (rawTracks is! List) {
      throw RenderGraphException(
        'RG_SCHEMA_VERSION',
        'tracks must be an array',
        'tracks',
      );
    }

    final tracks = <RgTrack>[];
    for (var i = 0; i < rawTracks.length; i++) {
      final item = rawTracks[i];
      if (item is! Map) {
        throw RenderGraphException(
          'RG_SCHEMA_VERSION',
          'tracks[$i] must be an object',
          'tracks[$i]',
        );
      }
      tracks.add(
        RgTrack.parse(
          item.cast<String, Object?>(),
          position: i,
          graph: 'graph',
        ),
      );
    }

    return RenderGraphDoc(
      graphSchema: 'shadow.rendergraph/1',
      sequenceId: sequenceId,
      projectRevision: revision,
      timebase: RgTimebase.parse(_map(json['timebase'], 'timebase', 'graph')),
      profile: RgProfile.parse(_map(json['profile'], 'profile', 'graph')),
      range: RgRange.parse(_map(json['range'], 'range', 'graph')),
      backgroundRgba: _string(
        json['background_rgba'],
        'background_rgba',
        'graph',
      ),
      tracks: tracks,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'graph_schema': graphSchema,
    'sequence_id': sequenceId,
    'project_revision': projectRevision,
    'timebase': timebase.toJson(),
    'profile': profile.toJson(),
    'range': range.toJson(),
    'background_rgba': backgroundRgba,
    'tracks': tracks.map((t) => t.toJson()).toList(growable: false),
  };
}

@immutable
class RgTimebase {
  const RgTimebase({
    required this.ticksPerSecond,
    required this.fpsNum,
    required this.fpsDen,
    required this.sampleRate,
    required this.channels,
  });

  final int ticksPerSecond;
  final int fpsNum;
  final int fpsDen;
  final int sampleRate;
  final int channels;

  static RgTimebase parse(Map<String, Object?> json) {
    _expectOnly(json, const {
      'ticks_per_second',
      'fps_num',
      'fps_den',
      'sample_rate',
      'channels',
    }, 'timebase');
    final ticksPerSecond = _int(
      json['ticks_per_second'],
      'ticks_per_second',
      'timebase',
    );
    final fpsNum = _int(json['fps_num'], 'fps_num', 'timebase');
    final fpsDen = _int(json['fps_den'], 'fps_den', 'timebase');
    final sampleRate = _int(json['sample_rate'], 'sample_rate', 'timebase');
    final channels = _int(json['channels'], 'channels', 'timebase');

    if (ticksPerSecond != 1000000 ||
        fpsNum <= 0 ||
        fpsDen <= 0 ||
        sampleRate <= 0 ||
        channels <= 0 ||
        channels > 8 ||
        (fpsNum / fpsDen) > 120) {
      throw RenderGraphException(
        'RG_TIMEBASE_INVALID',
        'ticks_per_second must be 1e6, fps/sample rate/channels must be positive, fps <= 120',
        'timebase',
      );
    }

    return RgTimebase(
      ticksPerSecond: ticksPerSecond,
      fpsNum: fpsNum,
      fpsDen: fpsDen,
      sampleRate: sampleRate,
      channels: channels,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'ticks_per_second': ticksPerSecond,
    'fps_num': fpsNum,
    'fps_den': fpsDen,
    'sample_rate': sampleRate,
    'channels': channels,
  };
}

@immutable
class RgProfile {
  const RgProfile({
    required this.width,
    required this.height,
    required this.pixelFormat,
    required this.colorSpace,
    required this.interlaced,
  });

  final int width;
  final int height;
  final String pixelFormat;
  final String colorSpace;
  final bool interlaced;

  static RgProfile parse(Map<String, Object?> json) {
    _expectOnly(json, const {
      'width',
      'height',
      'pixel_format',
      'color_space',
      'interlaced',
    }, 'profile');
    final width = _int(json['width'], 'width', 'profile');
    final height = _int(json['height'], 'height', 'profile');
    final pixelFormat = _string(
      json['pixel_format'],
      'pixel_format',
      'profile',
    );
    final colorSpace = _string(json['color_space'], 'color_space', 'profile');
    final interlaced = json['interlaced'] as bool? ?? false;

    const supportedColorSpaces = {'bt709', 'bt2020', 'srgb'};
    if (interlaced ||
        width <= 0 ||
        height <= 0 ||
        !supportedColorSpaces.contains(colorSpace)) {
      throw RenderGraphException(
        'RG_UNSUPPORTED_PROFILE',
        'interlaced must be false, dimensions positive, color_space supported',
        'profile',
      );
    }
    if (pixelFormat == 'yuv420p' && (width.isOdd || height.isOdd)) {
      throw RenderGraphException(
        'RG_UNSUPPORTED_PROFILE',
        'yuv420p requires even dimensions',
        'profile',
      );
    }
    return RgProfile(
      width: width,
      height: height,
      pixelFormat: pixelFormat,
      colorSpace: colorSpace,
      interlaced: interlaced,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'width': width,
    'height': height,
    'pixel_format': pixelFormat,
    'color_space': colorSpace,
    'interlaced': interlaced,
  };
}

@immutable
class RgRange {
  const RgRange({required this.startTicks, required this.durationTicks});

  final int startTicks;
  final int durationTicks;

  int get endTicks => startTicks + durationTicks;

  bool contains(int tick) => tick >= startTicks && tick < endTicks;

  static RgRange parse(Map<String, Object?> json) {
    _expectOnly(json, const {'start_ticks', 'duration_ticks'}, 'range');
    final start = _int(json['start_ticks'], 'start_ticks', 'range');
    final duration = _int(json['duration_ticks'], 'duration_ticks', 'range');
    if (start < 0 || duration <= 0) {
      throw RenderGraphException(
        'RG_RANGE_INVALID',
        'range.start_ticks must be >= 0 and duration_ticks > 0',
        'range',
      );
    }
    if (duration > 6 * 60 * 60 * 1000000) {
      throw RenderGraphException(
        'RG_LIMITS',
        'range duration exceeds the 6 hour limit',
        'range',
      );
    }
    return RgRange(startTicks: start, durationTicks: duration);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'start_ticks': startTicks,
    'duration_ticks': durationTicks,
  };
}

/// A single track with its typed content, already validated.
class RgTrack {
  RgTrack({
    required this.id,
    required this.kind,
    required this.position,
    required this.name,
    required this.enabled,
    required this.gainMb,
    required this.panPpm,
    required this.clips,
    required this.audioClips,
    required this.textLayers,
    required this.transitions,
  });

  final String id;
  final String kind;
  final int position;
  final String name;
  final bool enabled;
  final int? gainMb;
  final int? panPpm;
  final List<RgVideoClip> clips;
  final List<RgAudioClip> audioClips;
  final List<RgTextLayer> textLayers;
  final List<RgTransition> transitions;

  static const Set<String> _commonKeys = {
    'id',
    'kind',
    'position',
    'name',
    'enabled',
  };

  static RgTrack parse(
    Map<String, Object?> json, {
    required int position,
    required String graph,
  }) {
    _expectOnly(json, {
      ..._commonKeys,
      'clips',
      'transitions',
      'gain_mb',
      'pan_ppm',
      'audio_clips',
      'text_layers',
    }, '$graph.tracks[$position]');

    final id = _string(json['id'], 'id', 'tracks[$position]');
    if (!_uuidV7Pattern.hasMatch(id)) {
      throw RenderGraphException(
        'RG_SCHEMA_VERSION',
        'track id must be a UUIDv7',
        'tracks[$position].id',
      );
    }
    final kind = _string(json['kind'], 'kind', 'tracks[$position]');
    if (!const {'video', 'audio', 'overlay'}.contains(kind)) {
      throw RenderGraphException(
        'RG_TRACK_KIND_FIELD',
        'unknown track kind "$kind',
        'tracks[$position].kind',
      );
    }
    final trackPosition = _int(
      json['position'],
      'position',
      'tracks[$position]',
    );
    if (trackPosition != position) {
      throw RenderGraphException(
        'RG_TRACK_POSITION',
        'track positions must be dense and ordered (expected $position)',
        'tracks[$position].position',
      );
    }

    final rawClips = json['clips'];
    final rawAudioClips = json['audio_clips'];
    final rawTextLayers = json['text_layers'];

    if (kind == 'video' && (rawAudioClips != null || rawTextLayers != null)) {
      throw RenderGraphException(
        'RG_TRACK_KIND_FIELD',
        'video track must not declare audio_clips/text_layers',
        'tracks[$position]',
      );
    }
    if (kind == 'audio' && (rawClips != null || rawTextLayers != null)) {
      throw RenderGraphException(
        'RG_TRACK_KIND_FIELD',
        'audio track must not declare clips/text_layers',
        'tracks[$position]',
      );
    }
    if (kind == 'overlay' &&
        (rawClips != null ||
            rawAudioClips != null ||
            json['gain_mb'] != null)) {
      throw RenderGraphException(
        'RG_TRACK_KIND_FIELD',
        'overlay track must not declare media clips or audio fields',
        'tracks[$position]',
      );
    }

    final clips = <RgVideoClip>[];
    if (rawClips is List) {
      for (var i = 0; i < rawClips.length; i++) {
        clips.add(
          RgVideoClip.parse(
            (rawClips[i] as Map).cast<String, Object?>(),
            'tracks[$position].clips[$i]',
          ),
        );
      }
    }

    final audioClips = <RgAudioClip>[];
    if (rawAudioClips is List) {
      for (var i = 0; i < rawAudioClips.length; i++) {
        audioClips.add(
          RgAudioClip.parse(
            (rawAudioClips[i] as Map).cast<String, Object?>(),
            'tracks[$position].audio_clips[$i]',
          ),
        );
      }
    }

    final textLayers = <RgTextLayer>[];
    if (rawTextLayers is List) {
      for (var i = 0; i < rawTextLayers.length; i++) {
        textLayers.add(
          RgTextLayer.parse(
            (rawTextLayers[i] as Map).cast<String, Object?>(),
            'tracks[$position].text_layers[$i]',
          ),
        );
      }
    }

    final transitions = <RgTransition>[];
    final rawTransitions = json['transitions'];
    if (rawTransitions is List) {
      for (var i = 0; i < rawTransitions.length; i++) {
        transitions.add(
          RgTransition.parse(
            (rawTransitions[i] as Map).cast<String, Object?>(),
            'tracks[$position].transitions[$i]',
          ),
        );
      }
    }

    return RgTrack(
      id: id,
      kind: kind,
      position: trackPosition,
      name: _string(json['name'], 'name', 'tracks[$position]'),
      enabled: json['enabled'] as bool? ?? true,
      gainMb: json['gain_mb'] as int?,
      panPpm: json['pan_ppm'] as int?,
      clips: clips,
      audioClips: audioClips,
      textLayers: textLayers,
      transitions: transitions,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind,
    'position': position,
    'name': name,
    'enabled': enabled,
    if (kind == 'video') ...<String, Object?>{
      'clips': clips.map((c) => c.toJson()).toList(growable: false),
      if (transitions.isNotEmpty)
        'transitions': transitions.map((t) => t.toJson()).toList(),
    },
    if (kind == 'audio') ...<String, Object?>{
      'gain_mb': gainMb ?? 0,
      'pan_ppm': panPpm ?? 0,
      'audio_clips': audioClips.map((c) => c.toJson()).toList(),
    },
    if (kind == 'overlay')
      'text_layers': textLayers.map((t) => t.toJson()).toList(),
  };
}

class RgTransform {
  const RgTransform({
    required this.xPx,
    required this.yPx,
    required this.scaleXPpm,
    required this.scaleYPpm,
    required this.rotationQuarterTurns,
    required this.anchor,
    required this.cropLeftPx,
    required this.cropRightPx,
    required this.cropTopPx,
    required this.cropBottomPx,
  });

  final int xPx;
  final int yPx;
  final int scaleXPpm;
  final int scaleYPpm;
  final int rotationQuarterTurns;
  final String anchor;
  final int cropLeftPx;
  final int cropRightPx;
  final int cropTopPx;
  final int cropBottomPx;

  static const RgTransform identity = RgTransform(
    xPx: 0,
    yPx: 0,
    scaleXPpm: 1000000,
    scaleYPpm: 1000000,
    rotationQuarterTurns: 0,
    anchor: 'center',
    cropLeftPx: 0,
    cropRightPx: 0,
    cropTopPx: 0,
    cropBottomPx: 0,
  );

  static RgTransform parse(Map<String, Object?> json, String path) {
    _expectOnly(json, const {
      'x_px',
      'y_px',
      'scale_x_ppm',
      'scale_y_ppm',
      'rotation_quarter_turns',
      'anchor',
      'crop_left_px',
      'crop_right_px',
      'crop_top_px',
      'crop_bottom_px',
    }, path);
    final transform = RgTransform(
      xPx: _int(json['x_px'], 'x_px', path),
      yPx: _int(json['y_px'], 'y_px', path),
      scaleXPpm: _int(json['scale_x_ppm'], 'scale_x_ppm', path),
      scaleYPpm: _int(json['scale_y_ppm'], 'scale_y_ppm', path),
      rotationQuarterTurns: _int(
        json['rotation_quarter_turns'],
        'rotation_quarter_turns',
        path,
      ),
      anchor: _string(json['anchor'], 'anchor', path),
      cropLeftPx: _int(json['crop_left_px'], 'crop_left_px', path),
      cropRightPx: _int(json['crop_right_px'], 'crop_right_px', path),
      cropTopPx: _int(json['crop_top_px'], 'crop_top_px', path),
      cropBottomPx: _int(json['crop_bottom_px'], 'crop_bottom_px', path),
    );
    if (transform.scaleXPpm < 1 ||
        transform.scaleYPpm < 1 ||
        transform.rotationQuarterTurns < 0 ||
        transform.rotationQuarterTurns > 3 ||
        (transform.anchor != 'center' && transform.anchor != 'top_left') ||
        transform.cropLeftPx < 0 ||
        transform.cropRightPx < 0 ||
        transform.cropTopPx < 0 ||
        transform.cropBottomPx < 0) {
      throw RenderGraphException(
        'RG_SCHEMA_VERSION',
        'invalid transform values',
        path,
      );
    }
    return transform;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'x_px': xPx,
    'y_px': yPx,
    'scale_x_ppm': scaleXPpm,
    'scale_y_ppm': scaleYPpm,
    'rotation_quarter_turns': rotationQuarterTurns,
    'anchor': anchor,
    'crop_left_px': cropLeftPx,
    'crop_right_px': cropRightPx,
    'crop_top_px': cropTopPx,
    'crop_bottom_px': cropBottomPx,
  };
}

class RgEffect {
  const RgEffect({
    required this.id,
    required this.effectKey,
    required this.enabled,
    required this.params,
  });

  final String id;
  final String effectKey;
  final bool enabled;
  final List<RgParam> params;

  static RgEffect parse(Map<String, Object?> json, String path) {
    _expectOnly(json, const {'id', 'effect_key', 'enabled', 'params'}, path);
    final effectKey = _string(json['effect_key'], 'effect_key', path);
    if (!effectKey.startsWith('shadow.')) {
      throw RenderGraphException(
        'RG_UNKNOWN_EFFECT',
        'effect_key must start with "shadow."',
        path,
      );
    }
    final rawParams = json['params'] as List? ?? const [];
    final params = <RgParam>[];
    for (var i = 0; i < rawParams.length; i++) {
      params.add(
        RgParam.parse(
          (rawParams[i] as Map).cast<String, Object?>(),
          '$path.params[$i]',
        ),
      );
    }
    if (params.length > 32) {
      throw RenderGraphException('RG_LIMITS', 'more than 32 params', path);
    }
    return RgEffect(
      id: _string(json['id'], 'id', path),
      effectKey: effectKey,
      enabled: json['enabled'] as bool? ?? true,
      params: params,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'effect_key': effectKey,
    'enabled': enabled,
    'params': params.map((p) => p.toJson()).toList(growable: false),
  };
}

class RgParam {
  const RgParam({
    required this.name,
    required this.type,
    required this.value,
    required this.keyframes,
  });

  final String name;
  final String type;
  final Object? value;
  final List<RgKeyframe> keyframes;

  static RgParam parse(Map<String, Object?> json, String path) {
    _expectOnly(json, const {'name', 'type', 'value', 'keyframes'}, path);
    final rawKeyframes = json['keyframes'] as List? ?? const [];
    if (rawKeyframes.length > 240) {
      throw RenderGraphException('RG_LIMITS', 'more than 240 keyframes', path);
    }
    final keyframes = <RgKeyframe>[];
    for (var i = 0; i < rawKeyframes.length; i++) {
      keyframes.add(
        RgKeyframe.parse(
          (rawKeyframes[i] as Map).cast<String, Object?>(),
          '$path.keyframes[$i]',
        ),
      );
    }
    for (var i = 1; i < keyframes.length; i++) {
      if (keyframes[i].atTicks <= keyframes[i - 1].atTicks) {
        throw RenderGraphException(
          'RG_KEYFRAME_ORDER',
          'keyframes must be strictly increasing',
          '$path.keyframes',
        );
      }
    }
    return RgParam(
      name: _string(json['name'], 'name', path),
      type: _string(json['type'], 'type', path),
      value: json['value'],
      keyframes: keyframes,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'type': type,
    'value': value,
    'keyframes': keyframes.map((k) => k.toJson()).toList(),
  };
}

class RgKeyframe {
  const RgKeyframe({required this.atTicks, required this.value});

  final int atTicks;
  final Object? value;

  static RgKeyframe parse(Map<String, Object?> json, String path) {
    _expectOnly(json, const {'at_ticks', 'value'}, path);
    return RgKeyframe(
      atTicks: _int(json['at_ticks'], 'at_ticks', path),
      value: json['value'],
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'at_ticks': atTicks,
    'value': value,
  };
}

/// A video clip resolved against the timeline range.
class RgVideoClip {
  RgVideoClip({
    required this.id,
    required this.assetId,
    required this.kind,
    required this.sourceUri,
    required this.sourceHash,
    required this.streamIndex,
    required this.timelineStartTicks,
    required this.durationTicks,
    required this.sourceInTicks,
    required this.speedNum,
    required this.speedDen,
    required this.opacityPpm,
    required this.enabled,
    required this.label,
    required this.transform,
    required this.effects,
  });

  final String id;
  final String? assetId;
  final String kind;
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
  final RgTransform transform;
  final List<RgEffect> effects;

  int get timelineEndTicks => timelineStartTicks + durationTicks;

  /// Source ticks consumed by this clip (speed aware).
  int get sourceDurationTicks => (durationTicks * speedNum) ~/ speedDen;

  int get sourceEndTicks => sourceInTicks + sourceDurationTicks;

  static RgVideoClip parse(Map<String, Object?> json, String path) {
    _expectOnly(json, const {
      'id',
      'asset_id',
      'kind',
      'source_uri',
      'source_hash',
      'stream_index',
      'timeline_start_ticks',
      'duration_ticks',
      'source_in_ticks',
      'speed_num',
      'speed_den',
      'opacity_ppm',
      'enabled',
      'label',
      'transform',
      'effects',
    }, path);

    final kind = _string(json['kind'], 'kind', path);
    if (kind == 'audio') {
      throw RenderGraphException(
        'RG_TRACK_KIND_FIELD',
        'audio clip placed in video clips',
        path,
      );
    }
    final sourceUri = json['source_uri'] as String?;
    final sourceHash = json['source_hash'] as String?;
    if (kind != 'color' && (sourceUri == null || sourceHash == null)) {
      throw RenderGraphException(
        'RG_MISSING_SOURCE',
        'clip kind "$kind" requires source_uri and source_hash',
        path,
      );
    }
    final durationTicks = _int(json['duration_ticks'], 'duration_ticks', path);
    final timelineStart = _int(
      json['timeline_start_ticks'],
      'timeline_start_ticks',
      path,
    );
    final sourceIn = _int(json['source_in_ticks'], 'source_in_ticks', path);
    final speedNum = _int(json['speed_num'], 'speed_num', path);
    final speedDen = _int(json['speed_den'], 'speed_den', path);

    if (durationTicks <= 0 ||
        timelineStart < 0 ||
        sourceIn < 0 ||
        speedNum <= 0 ||
        speedDen <= 0) {
      throw RenderGraphException(
        'RG_CLIP_BOUNDS',
        'durations and speeds must be positive, start/source_in >= 0',
        path,
      );
    }

    final opacity = _int(json['opacity_ppm'], 'opacity_ppm', path);
    if (opacity < 0 || opacity > 1000000) {
      throw RenderGraphException(
        'RG_SCHEMA_VERSION',
        'opacity_ppm must be 0..1000000',
        path,
      );
    }

    final transformJson = json['transform'];
    final transform = transformJson == null
        ? RgTransform.identity
        : RgTransform.parse(
            (transformJson as Map).cast<String, Object?>(),
            '$path.transform',
          );

    final rawEffects = json['effects'] as List? ?? const [];
    if (rawEffects.length > 16) {
      throw RenderGraphException('RG_LIMITS', 'more than 16 effects', path);
    }
    final effects = <RgEffect>[];
    for (var i = 0; i < rawEffects.length; i++) {
      effects.add(
        RgEffect.parse(
          (rawEffects[i] as Map).cast<String, Object?>(),
          '$path.effects[$i]',
        ),
      );
    }

    return RgVideoClip(
      id: _string(json['id'], 'id', path),
      assetId: json['asset_id'] as String?,
      kind: kind,
      sourceUri: sourceUri,
      sourceHash: sourceHash,
      streamIndex: _int(json['stream_index'], 'stream_index', path),
      timelineStartTicks: timelineStart,
      durationTicks: durationTicks,
      sourceInTicks: sourceIn,
      speedNum: speedNum,
      speedDen: speedDen,
      opacityPpm: opacity,
      enabled: json['enabled'] as bool? ?? true,
      label: json['label'] as String?,
      transform: transform,
      effects: effects,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'asset_id': assetId,
    'kind': kind,
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
}

/// An audio clip resolved against the timeline range.
class RgAudioClip {
  RgAudioClip({
    required this.id,
    required this.assetId,
    required this.sourceUri,
    required this.sourceHash,
    required this.streamIndex,
    required this.timelineStartTicks,
    required this.durationTicks,
    required this.sourceInTicks,
    required this.speedNum,
    required this.speedDen,
    required this.gainMb,
    required this.fadeInTicks,
    required this.fadeOutTicks,
    required this.enabled,
  });

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

  int get timelineEndTicks => timelineStartTicks + durationTicks;

  int get sourceDurationTicks => (durationTicks * speedNum) ~/ speedDen;

  static RgAudioClip parse(Map<String, Object?> json, String path) {
    _expectOnly(json, const {
      'id',
      'asset_id',
      'source_uri',
      'source_hash',
      'stream_index',
      'timeline_start_ticks',
      'duration_ticks',
      'source_in_ticks',
      'speed_num',
      'speed_den',
      'gain_mb',
      'fade_in_ticks',
      'fade_out_ticks',
      'enabled',
    }, path);

    final assetId = json['asset_id'] as String?;
    final sourceUri = json['source_uri'] as String?;
    final sourceHash = json['source_hash'] as String?;
    final isSilence = assetId == null && sourceUri == null;
    if (!isSilence && (sourceUri == null || sourceHash == null)) {
      throw RenderGraphException(
        'RG_MISSING_SOURCE',
        'audio clip needs asset_id+source or neither (silence)',
        path,
      );
    }

    final duration = _int(json['duration_ticks'], 'duration_ticks', path);
    final start = _int(
      json['timeline_start_ticks'],
      'timeline_start_ticks',
      path,
    );
    final sourceIn = _int(json['source_in_ticks'], 'source_in_ticks', path);
    final speedNum = _int(json['speed_num'], 'speed_num', path);
    final speedDen = _int(json['speed_den'], 'speed_den', path);
    final gain = _int(json['gain_mb'], 'gain_mb', path);
    final fadeIn = _int(json['fade_in_ticks'], 'fade_in_ticks', path);
    final fadeOut = _int(json['fade_out_ticks'], 'fade_out_ticks', path);

    if (duration <= 0 ||
        start < 0 ||
        sourceIn < 0 ||
        speedNum <= 0 ||
        speedDen <= 0) {
      throw RenderGraphException(
        'RG_CLIP_BOUNDS',
        'durations/speeds must be positive, start/source_in >= 0',
        path,
      );
    }
    if (gain < -60000 || gain > 24000) {
      throw RenderGraphException(
        'RG_SCHEMA_VERSION',
        'gain_mb must be -60000..24000',
        path,
      );
    }
    if (fadeIn < 0 || fadeOut < 0 || fadeIn + fadeOut > duration) {
      throw RenderGraphException(
        'RG_SCHEMA_VERSION',
        'fade_in + fade_out must fit inside the clip duration',
        path,
      );
    }

    return RgAudioClip(
      id: _string(json['id'], 'id', path),
      assetId: assetId,
      sourceUri: sourceUri,
      sourceHash: sourceHash,
      streamIndex: _int(json['stream_index'], 'stream_index', path),
      timelineStartTicks: start,
      durationTicks: duration,
      sourceInTicks: sourceIn,
      speedNum: speedNum,
      speedDen: speedDen,
      gainMb: gain,
      fadeInTicks: fadeIn,
      fadeOutTicks: fadeOut,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
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
}

/// A rasterized text overlay.
class RgTextLayer {
  RgTextLayer({
    required this.id,
    required this.rasterUri,
    required this.rasterHash,
    required this.rasterWidth,
    required this.rasterHeight,
    required this.startTicks,
    required this.durationTicks,
    required this.opacityPpm,
    required this.transform,
    required this.animationInKind,
    required this.animationInTicks,
    required this.animationOutKind,
    required this.animationOutTicks,
  });

  final String id;
  final String rasterUri;
  final String rasterHash;
  final int rasterWidth;
  final int rasterHeight;
  final int startTicks;
  final int durationTicks;
  final int opacityPpm;
  final RgTransform transform;
  final String animationInKind;
  final int animationInTicks;
  final String animationOutKind;
  final int animationOutTicks;

  int get endTicks => startTicks + durationTicks;

  static RgTextLayer parse(Map<String, Object?> json, String path) {
    _expectOnly(json, const {
      'id',
      'raster_uri',
      'raster_hash',
      'raster_width',
      'raster_height',
      'start_ticks',
      'duration_ticks',
      'opacity_ppm',
      'transform',
      'animation_in',
      'animation_out',
    }, path);

    final uri = _string(json['raster_uri'], 'raster_uri', path);
    if (!uri.startsWith('file://')) {
      throw RenderGraphException(
        'RG_TEXT_RASTER',
        'raster_uri must be a file:// URI',
        path,
      );
    }
    final hash = _string(json['raster_hash'], 'raster_hash', path);
    if (!_hashPattern.hasMatch(hash)) {
      throw RenderGraphException(
        'RG_TEXT_RASTER',
        'raster_hash must be 64 hex characters',
        path,
      );
    }
    final width = _int(json['raster_width'], 'raster_width', path);
    final height = _int(json['raster_height'], 'raster_height', path);
    if (width <= 0 || height <= 0) {
      throw RenderGraphException(
        'RG_TEXT_RASTER',
        'raster dimensions must be positive',
        path,
      );
    }
    final duration = _int(json['duration_ticks'], 'duration_ticks', path);
    final start = _int(json['start_ticks'], 'start_ticks', path);
    if (duration <= 0 || start < 0) {
      throw RenderGraphException(
        'RG_TEXT_RASTER',
        'text layer timing must be start >= 0 and duration > 0',
        path,
      );
    }
    final opacity = _int(json['opacity_ppm'], 'opacity_ppm', path);
    if (opacity < 0 || opacity > 1000000) {
      throw RenderGraphException(
        'RG_TEXT_RASTER',
        'opacity_ppm must be 0..1000000',
        path,
      );
    }

    final animationIn =
        (json['animation_in'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{'kind': 'none', 'duration_ticks': 0};
    final animationOut =
        (json['animation_out'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{'kind': 'none', 'duration_ticks': 0};
    final inKind = _string(animationIn['kind'], 'kind', '$path.animation_in');
    final outKind = _string(
      animationOut['kind'],
      'kind',
      '$path.animation_out',
    );
    final inTicks = _int(
      animationIn['duration_ticks'],
      'duration_ticks',
      '$path.animation_in',
    );
    final outTicks = _int(
      animationOut['duration_ticks'],
      'duration_ticks',
      '$path.animation_out',
    );
    if (!const {'none', 'fade', 'slide'}.contains(inKind) ||
        !const {'none', 'fade', 'slide'}.contains(outKind)) {
      throw RenderGraphException(
        'RG_TEXT_RASTER',
        'animation kinds must be none/fade/slide',
        path,
      );
    }
    if ((inKind == 'none' && inTicks != 0) ||
        (outKind == 'none' && outTicks != 0) ||
        inTicks < 0 ||
        outTicks < 0 ||
        inTicks + outTicks > duration) {
      throw RenderGraphException(
        'RG_TEXT_RASTER',
        'animation durations must fit inside the layer duration',
        path,
      );
    }

    return RgTextLayer(
      id: _string(json['id'], 'id', path),
      rasterUri: uri,
      rasterHash: hash,
      rasterWidth: width,
      rasterHeight: height,
      startTicks: start,
      durationTicks: duration,
      opacityPpm: opacity,
      transform: RgTransform.parse(
        (json['transform'] as Map).cast<String, Object?>(),
        '$path.transform',
      ),
      animationInKind: inKind,
      animationInTicks: inTicks,
      animationOutKind: outKind,
      animationOutTicks: outTicks,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'raster_uri': rasterUri,
    'raster_hash': rasterHash,
    'raster_width': rasterWidth,
    'raster_height': rasterHeight,
    'start_ticks': startTicks,
    'duration_ticks': durationTicks,
    'opacity_ppm': opacityPpm,
    'transform': transform.toJson(),
    'animation_in': <String, Object?>{
      'kind': animationInKind,
      'duration_ticks': animationInTicks,
    },
    'animation_out': <String, Object?>{
      'kind': animationOutKind,
      'duration_ticks': animationOutTicks,
    },
  };
}

/// A transition anchored on the cut between two adjacent clips.
class RgTransition {
  RgTransition({
    required this.id,
    required this.kind,
    required this.atTicks,
    required this.durationTicks,
    required this.fromClipId,
    required this.toClipId,
  });

  final String id;
  final String kind;
  final int atTicks;
  final int durationTicks;
  final String fromClipId;
  final String toClipId;

  static RgTransition parse(Map<String, Object?> json, String path) {
    _expectOnly(json, const {
      'id',
      'kind',
      'at_ticks',
      'duration_ticks',
      'from_clip_id',
      'to_clip_id',
    }, path);
    final kind = _string(json['kind'], 'kind', path);
    if (!const {
      'crossfade',
      'dissolve',
      'wipe_left',
      'wipe_right',
      'fade_black',
    }.contains(kind)) {
      throw RenderGraphException(
        'RG_TRANSITION_BOUNDARY',
        'unknown transition kind "$kind"',
        path,
      );
    }
    final duration = _int(json['duration_ticks'], 'duration_ticks', path);
    if (duration <= 0) {
      throw RenderGraphException(
        'RG_TRANSITION_BOUNDARY',
        'transition duration must be positive',
        path,
      );
    }
    return RgTransition(
      id: _string(json['id'], 'id', path),
      kind: kind,
      atTicks: _int(json['at_ticks'], 'at_ticks', path),
      durationTicks: duration,
      fromClipId: _string(json['from_clip_id'], 'from_clip_id', path),
      toClipId: _string(json['to_clip_id'], 'to_clip_id', path),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind,
    'at_ticks': atTicks,
    'duration_ticks': durationTicks,
    'from_clip_id': fromClipId,
    'to_clip_id': toClipId,
  };
}

final RegExp _uuidV7Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final RegExp _hashPattern = RegExp(r'^[0-9a-f]{64}$');

Map<String, Object?> _map(Object? value, String field, String path) {
  if (value is! Map) {
    throw RenderGraphException(
      'RG_SCHEMA_VERSION',
      '$field must be an object',
      path,
    );
  }
  return value.cast<String, Object?>();
}

int _int(Object? value, String field, String path) {
  if (value is int) return value;
  throw RenderGraphException(
    'RG_SCHEMA_VERSION',
    '$field must be an integer',
    path,
  );
}

String _string(Object? value, String field, String path) {
  if (value is String && value.isNotEmpty) return value;
  throw RenderGraphException(
    'RG_SCHEMA_VERSION',
    '$field must be a non-empty string',
    path,
  );
}

void _expectOnly(Map<String, Object?> json, Set<String> allowed, String path) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw RenderGraphException(
        'RG_UNKNOWN_FIELD',
        'unknown field "$key"',
        path,
      );
    }
  }
}
