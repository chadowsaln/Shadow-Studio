import 'package:meta/meta.dart';

import 'transform_box.dart';

/// Text layer animation aligned with RenderGraph Animation definition.
@immutable
class TextLayerAnimation {
  final String kind; // 'none', 'fade', 'slide'
  final int durationTicks;

  const TextLayerAnimation({
    this.kind = 'none',
    this.durationTicks = 0,
  })  : assert(
          kind == 'none' || kind == 'fade' || kind == 'slide',
          'kind must be none, fade, or slide',
        ),
        assert(durationTicks >= 0, 'durationTicks must be >= 0');

  const TextLayerAnimation.none()
      : kind = 'none',
        durationTicks = 0;

  const TextLayerAnimation.fade(this.durationTicks)
      : kind = 'fade',
        assert(durationTicks >= 0);

  const TextLayerAnimation.slide(this.durationTicks)
      : kind = 'slide',
        assert(durationTicks >= 0);

  Map<String, Object?> toJson() => {
        'kind': kind,
        'duration_ticks': durationTicks,
      };

  factory TextLayerAnimation.fromJson(Map<String, Object?> json) {
    return TextLayerAnimation(
      kind: (json['kind'] as String?) ?? 'none',
      durationTicks: (json['duration_ticks'] as int?) ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextLayerAnimation &&
          runtimeType == other.runtimeType &&
          kind == other.kind &&
          durationTicks == other.durationTicks;

  @override
  int get hashCode => Object.hash(kind, durationTicks);

  @override
  String toString() => 'Animation($kind, dur: $durationTicks)';
}

/// Text layer entity aligned with RenderGraph TextLayer definition.
@immutable
class TextLayer {
  final String id;
  final String rasterUri;
  final String rasterHash;
  final int rasterWidth;
  final int rasterHeight;
  final int startTicks;
  final int durationTicks;
  final int opacityPpm;
  final TransformBox transform;
  final TextLayerAnimation animationIn;
  final TextLayerAnimation animationOut;

  const TextLayer({
    required this.id,
    required this.rasterUri,
    required this.rasterHash,
    required this.rasterWidth,
    required this.rasterHeight,
    required this.startTicks,
    required this.durationTicks,
    this.opacityPpm = 1000000,
    this.transform = const TransformBox.identity(),
    this.animationIn = const TextLayerAnimation.none(),
    this.animationOut = const TextLayerAnimation.none(),
  })  : assert(rasterWidth >= 1, 'rasterWidth must be >= 1'),
        assert(rasterHeight >= 1, 'rasterHeight must be >= 1'),
        assert(startTicks >= 0, 'startTicks must be >= 0'),
        assert(durationTicks >= 1, 'durationTicks must be >= 1'),
        assert(
          opacityPpm >= 0 && opacityPpm <= 1000000,
          'opacityPpm must be 0..1000000',
        );

  int get endTicks => startTicks + durationTicks;

  Map<String, Object?> toJson() => {
        'id': id,
        'raster_uri': rasterUri,
        'raster_hash': rasterHash,
        'raster_width': rasterWidth,
        'raster_height': rasterHeight,
        'start_ticks': startTicks,
        'duration_ticks': durationTicks,
        'opacity_ppm': opacityPpm,
        'transform': transform.toJson(),
        'animation_in': animationIn.toJson(),
        'animation_out': animationOut.toJson(),
      };

  factory TextLayer.fromJson(Map<String, Object?> json) {
    return TextLayer(
      id: json['id'] as String,
      rasterUri: json['raster_uri'] as String,
      rasterHash: json['raster_hash'] as String,
      rasterWidth: json['raster_width'] as int,
      rasterHeight: json['raster_height'] as int,
      startTicks: json['start_ticks'] as int,
      durationTicks: json['duration_ticks'] as int,
      opacityPpm: (json['opacity_ppm'] as int?) ?? 1000000,
      transform: json.containsKey('transform')
          ? TransformBox.fromJson(
              (json['transform'] as Map).cast<String, Object?>(),
            )
          : const TransformBox.identity(),
      animationIn: json.containsKey('animation_in')
          ? TextLayerAnimation.fromJson(
              (json['animation_in'] as Map).cast<String, Object?>(),
            )
          : const TextLayerAnimation.none(),
      animationOut: json.containsKey('animation_out')
          ? TextLayerAnimation.fromJson(
              (json['animation_out'] as Map).cast<String, Object?>(),
            )
          : const TextLayerAnimation.none(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextLayer &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          rasterUri == other.rasterUri &&
          rasterHash == other.rasterHash &&
          rasterWidth == other.rasterWidth &&
          rasterHeight == other.rasterHeight &&
          startTicks == other.startTicks &&
          durationTicks == other.durationTicks &&
          opacityPpm == other.opacityPpm &&
          transform == other.transform &&
          animationIn == other.animationIn &&
          animationOut == other.animationOut;

  @override
  int get hashCode => Object.hash(
        id,
        rasterUri,
        rasterHash,
        rasterWidth,
        rasterHeight,
        startTicks,
        durationTicks,
        opacityPpm,
        transform,
        animationIn,
        animationOut,
      );

  @override
  String toString() =>
      'TextLayer(id: $id, start: $startTicks, dur: $durationTicks, raster: $rasterUri)';
}
