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

/// Horizontal alignment of a text layer inside its box.
enum TextAlign {
  left,
  center,
  right;

  String get wireName => name;

  static TextAlign fromWireName(String value) {
    return TextAlign.values.firstWhere(
      (a) => a.wireName == value,
      orElse: () => TextAlign.center,
    );
  }
}

/// Text layer entity aligned with the RenderGraph TextLayer definition.
///
/// A layer carries either:
/// - authored text (`text` + font/color/alignment fields) which the renderer
///   rasterizes through Media Core (libass shaping, identical in preview and
///   export), or
/// - a pre-rendered RGBA raster (`rasterUri`/`rasterHash`), or
/// - both, when the raster is already cached for the current content.
///
/// The RenderGraph v1 wire format only accepts rasters, so `resolveGraph`
/// emits a text layer once `rasterUri` is present.
@immutable
class TextLayer {
  final String id;

  /// Authored text. Null for raster-only layers coming from disk.
  final String? text;

  /// Whether this layer represents subtitles (rendered as a caption track).
  final bool subtitle;

  /// Font key resolved by Media Core (e.g. `app-fonts/cairo-regular.ttf`).
  final String? fontKey;

  /// Font size in profile pixels.
  final int? fontSizePx;

  /// Text color as `#RRGGBB` or `#AARRGGBB`.
  final String? colorHex;

  final TextAlign align;

  /// Pre-rendered RGBA raster (PNG) produced by the text rasterizer.
  final String? rasterUri;
  final String? rasterHash;
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
    this.text,
    this.subtitle = false,
    this.fontKey,
    this.fontSizePx,
    this.colorHex,
    this.align = TextAlign.center,
    this.rasterUri,
    this.rasterHash,
    this.rasterWidth = 0,
    this.rasterHeight = 0,
    required this.startTicks,
    required this.durationTicks,
    this.opacityPpm = 1000000,
    this.transform = const TransformBox.identity(),
    this.animationIn = const TextLayerAnimation.none(),
    this.animationOut = const TextLayerAnimation.none(),
  })  : assert(rasterWidth >= 0, 'rasterWidth must be >= 0'),
        assert(rasterHeight >= 0, 'rasterHeight must be >= 0'),
        assert(startTicks >= 0, 'startTicks must be >= 0'),
        assert(durationTicks >= 1, 'durationTicks must be >= 1'),
        assert(
          opacityPpm >= 0 && opacityPpm <= 1000000,
          'opacityPpm must be 0..1000000',
        );

  int get endTicks => startTicks + durationTicks;

  /// True when the layer has authored text that still needs rasterization.
  bool get needsRasterization =>
      (text != null && text!.trim().isNotEmpty) && rasterUri == null;

  /// True when the layer can be handed to the RenderGraph as-is.
  bool get isRenderable =>
      rasterUri != null &&
      rasterHash != null &&
      rasterWidth > 0 &&
      rasterHeight > 0;

  TextLayer copyWith({
    String? id,
    String? text,
    bool? subtitle,
    String? fontKey,
    int? fontSizePx,
    String? colorHex,
    TextAlign? align,
    String? rasterUri,
    String? rasterHash,
    int? rasterWidth,
    int? rasterHeight,
    int? startTicks,
    int? durationTicks,
    int? opacityPpm,
    TransformBox? transform,
    TextLayerAnimation? animationIn,
    TextLayerAnimation? animationOut,
    bool clearText = false,
    bool clearRaster = false,
  }) {
    return TextLayer(
      id: id ?? this.id,
      text: clearText ? null : (text ?? this.text),
      subtitle: subtitle ?? this.subtitle,
      fontKey: fontKey ?? this.fontKey,
      fontSizePx: fontSizePx ?? this.fontSizePx,
      colorHex: colorHex ?? this.colorHex,
      align: align ?? this.align,
      rasterUri: clearRaster ? null : (rasterUri ?? this.rasterUri),
      rasterHash: clearRaster ? null : (rasterHash ?? this.rasterHash),
      rasterWidth: clearRaster ? 0 : (rasterWidth ?? this.rasterWidth),
      rasterHeight: clearRaster ? 0 : (rasterHeight ?? this.rasterHeight),
      startTicks: startTicks ?? this.startTicks,
      durationTicks: durationTicks ?? this.durationTicks,
      opacityPpm: opacityPpm ?? this.opacityPpm,
      transform: transform ?? this.transform,
      animationIn: animationIn ?? this.animationIn,
      animationOut: animationOut ?? this.animationOut,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        if (text != null) 'text': text,
        if (subtitle) 'subtitle': true,
        if (fontKey != null) 'font_key': fontKey,
        if (fontSizePx != null) 'font_size_px': fontSizePx,
        if (colorHex != null) 'color_hex': colorHex,
        'align': align.wireName,
        if (rasterUri != null) 'raster_uri': rasterUri,
        if (rasterHash != null) 'raster_hash': rasterHash,
        if (rasterWidth > 0) 'raster_width': rasterWidth,
        if (rasterHeight > 0) 'raster_height': rasterHeight,
        'start_ticks': startTicks,
        'duration_ticks': durationTicks,
        'opacity_ppm': opacityPpm,
        'transform': transform.toJson(),
        'animation_in': animationIn.toJson(),
        'animation_out': animationOut.toJson(),
      };

  /// Wire projection onto the closed RenderGraph v1 TextLayer schema (§أ.8).
  ///
  /// The document model carries authored text and style, but the wire format
  /// accepts rasters only, so this projection drops everything else.
  Map<String, Object?> toRenderGraphJson() => {
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
      text: json['text'] as String?,
      subtitle: (json['subtitle'] as bool?) ?? false,
      fontKey: json['font_key'] as String?,
      fontSizePx: json['font_size_px'] as int?,
      colorHex: json['color_hex'] as String?,
      align: json['align'] == null
          ? TextAlign.center
          : TextAlign.fromWireName(json['align'] as String),
      rasterUri: json['raster_uri'] as String?,
      rasterHash: json['raster_hash'] as String?,
      rasterWidth: (json['raster_width'] as int?) ?? 0,
      rasterHeight: (json['raster_height'] as int?) ?? 0,
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
          text == other.text &&
          subtitle == other.subtitle &&
          fontKey == other.fontKey &&
          fontSizePx == other.fontSizePx &&
          colorHex == other.colorHex &&
          align == other.align &&
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
        text,
        subtitle,
        fontKey,
        fontSizePx,
        colorHex,
        align,
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
      'TextLayer(id: $id, start: $startTicks, dur: $durationTicks, '
      'subtitle: $subtitle, raster: ${rasterUri ?? 'pending'})';
}
