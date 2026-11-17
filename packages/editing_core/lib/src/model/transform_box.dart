import 'package:meta/meta.dart';

/// Transform box for video clips and text layers.
///
/// Follows RenderGraph Transform definition:
/// x_px, y_px, scale_x_ppm, scale_y_ppm, rotation_quarter_turns (0..3),
/// anchor ("top_left" | "center"), crop_left_px, crop_right_px,
/// crop_top_px, crop_bottom_px.
@immutable
class TransformBox {
  final int xPx;
  final int yPx;
  final int scaleXPpm;
  final int scaleYPpm;
  final int rotationQuarterTurns;
  final String anchor; // 'center' or 'top_left'
  final int cropLeftPx;
  final int cropRightPx;
  final int cropTopPx;
  final int cropBottomPx;

  const TransformBox({
    this.xPx = 0,
    this.yPx = 0,
    this.scaleXPpm = 1000000,
    this.scaleYPpm = 1000000,
    this.rotationQuarterTurns = 0,
    this.anchor = 'center',
    this.cropLeftPx = 0,
    this.cropRightPx = 0,
    this.cropTopPx = 0,
    this.cropBottomPx = 0,
  })  : assert(scaleXPpm >= 1, 'scaleXPpm must be >= 1'),
        assert(scaleYPpm >= 1, 'scaleYPpm must be >= 1'),
        assert(
          rotationQuarterTurns >= 0 && rotationQuarterTurns <= 3,
          'rotationQuarterTurns must be 0..3',
        ),
        assert(
          anchor == 'center' || anchor == 'top_left',
          'anchor must be center or top_left',
        ),
        assert(cropLeftPx >= 0, 'cropLeftPx must be >= 0'),
        assert(cropRightPx >= 0, 'cropRightPx must be >= 0'),
        assert(cropTopPx >= 0, 'cropTopPx must be >= 0'),
        assert(cropBottomPx >= 0, 'cropBottomPx must be >= 0');

  const TransformBox.identity()
      : xPx = 0,
        yPx = 0,
        scaleXPpm = 1000000,
        scaleYPpm = 1000000,
        rotationQuarterTurns = 0,
        anchor = 'center',
        cropLeftPx = 0,
        cropRightPx = 0,
        cropTopPx = 0,
        cropBottomPx = 0;

  Map<String, Object?> toJson() => {
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

  factory TransformBox.fromJson(Map<String, Object?> json) {
    return TransformBox(
      xPx: (json['x_px'] as int?) ?? 0,
      yPx: (json['y_px'] as int?) ?? 0,
      scaleXPpm: (json['scale_x_ppm'] as int?) ?? 1000000,
      scaleYPpm: (json['scale_y_ppm'] as int?) ?? 1000000,
      rotationQuarterTurns: (json['rotation_quarter_turns'] as int?) ?? 0,
      anchor: (json['anchor'] as String?) ?? 'center',
      cropLeftPx: (json['crop_left_px'] as int?) ?? 0,
      cropRightPx: (json['crop_right_px'] as int?) ?? 0,
      cropTopPx: (json['crop_top_px'] as int?) ?? 0,
      cropBottomPx: (json['crop_bottom_px'] as int?) ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransformBox &&
          runtimeType == other.runtimeType &&
          xPx == other.xPx &&
          yPx == other.yPx &&
          scaleXPpm == other.scaleXPpm &&
          scaleYPpm == other.scaleYPpm &&
          rotationQuarterTurns == other.rotationQuarterTurns &&
          anchor == other.anchor &&
          cropLeftPx == other.cropLeftPx &&
          cropRightPx == other.cropRightPx &&
          cropTopPx == other.cropTopPx &&
          cropBottomPx == other.cropBottomPx;

  @override
  int get hashCode => Object.hash(
        xPx,
        yPx,
        scaleXPpm,
        scaleYPpm,
        rotationQuarterTurns,
        anchor,
        cropLeftPx,
        cropRightPx,
        cropTopPx,
        cropBottomPx,
      );

  @override
  String toString() =>
      'TransformBox(pos: ($xPx, $yPx), scale: ($scaleXPpm, $scaleYPpm), rot: $rotationQuarterTurns, anchor: $anchor)';
}
