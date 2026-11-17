import 'package:meta/meta.dart';

/// Video stream metadata extracted via ffprobe/native worker.
///
/// All durations and timestamps are strictly integer ticks (1 tick = 1/1,000,000 s).
@immutable
class VideoStreamInfo {
  final int index;
  final String codec;
  final int width;
  final int height;
  final int fpsNumerator;
  final int fpsDenominator;
  final int durationTicks;
  final int rotation; // 0, 90, 180, 270 degrees
  final String? pixelFormat;
  final int? bitRate;

  const VideoStreamInfo({
    required this.index,
    required this.codec,
    required this.width,
    required this.height,
    required this.fpsNumerator,
    required this.fpsDenominator,
    required this.durationTicks,
    this.rotation = 0,
    this.pixelFormat,
    this.bitRate,
  })  : assert(width >= 0, 'width must be non-negative'),
        assert(height >= 0, 'height must be non-negative'),
        assert(fpsNumerator >= 0, 'fpsNumerator must be non-negative'),
        assert(fpsDenominator > 0, 'fpsDenominator must be positive'),
        assert(durationTicks >= 0, 'durationTicks must be non-negative');

  double get fps => fpsNumerator / fpsDenominator;

  Map<String, Object?> toJson() => {
        'index': index,
        'codec': codec,
        'width': width,
        'height': height,
        'fps_numerator': fpsNumerator,
        'fps_denominator': fpsDenominator,
        'duration_ticks': durationTicks,
        'rotation': rotation,
        if (pixelFormat != null) 'pixel_format': pixelFormat,
        if (bitRate != null) 'bit_rate': bitRate,
      };

  factory VideoStreamInfo.fromJson(Map<String, Object?> json) {
    return VideoStreamInfo(
      index: json['index'] as int,
      codec: json['codec'] as String,
      width: json['width'] as int,
      height: json['height'] as int,
      fpsNumerator: json['fps_numerator'] as int,
      fpsDenominator: json['fps_denominator'] as int,
      durationTicks: json['duration_ticks'] as int,
      rotation: (json['rotation'] as int?) ?? 0,
      pixelFormat: json['pixel_format'] as String?,
      bitRate: json['bit_rate'] as int?,
    );
  }

  @override
  String toString() =>
      'VideoStreamInfo(#$index $codec ${width}x$height @ $fpsNumerator/$fpsDenominator fps, ${durationTicks}t)';
}

/// Audio stream metadata extracted via ffprobe/native worker.
///
/// All durations and timestamps are strictly integer ticks (1 tick = 1/1,000,000 s).
@immutable
class AudioStreamInfo {
  final int index;
  final String codec;
  final int sampleRate; // e.g. 48000, 44100 Hz
  final int channels; // e.g. 2, 1, 6
  final int durationTicks;
  final String? channelLayout;
  final int? bitRate;

  const AudioStreamInfo({
    required this.index,
    required this.codec,
    required this.sampleRate,
    required this.channels,
    required this.durationTicks,
    this.channelLayout,
    this.bitRate,
  })  : assert(sampleRate >= 0, 'sampleRate must be non-negative'),
        assert(channels >= 0, 'channels must be non-negative'),
        assert(durationTicks >= 0, 'durationTicks must be non-negative');

  Map<String, Object?> toJson() => {
        'index': index,
        'codec': codec,
        'sample_rate': sampleRate,
        'channels': channels,
        'duration_ticks': durationTicks,
        if (channelLayout != null) 'channel_layout': channelLayout,
        if (bitRate != null) 'bit_rate': bitRate,
      };

  factory AudioStreamInfo.fromJson(Map<String, Object?> json) {
    return AudioStreamInfo(
      index: json['index'] as int,
      codec: json['codec'] as String,
      sampleRate: json['sample_rate'] as int,
      channels: json['channels'] as int,
      durationTicks: json['duration_ticks'] as int,
      channelLayout: json['channel_layout'] as String?,
      bitRate: json['bit_rate'] as int?,
    );
  }

  @override
  String toString() =>
      'AudioStreamInfo(#$index $codec ${sampleRate}Hz ${channels}ch, ${durationTicks}t)';
}
