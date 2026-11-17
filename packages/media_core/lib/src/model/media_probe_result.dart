import 'package:meta/meta.dart';

import 'media_kind.dart';
import 'media_stream_info.dart';

/// Comprehensive container and stream inspection result produced by ffprobe / native media worker.
///
/// Integer ticks are used exclusively for all time intervals (1 tick = 1/1,000,000 s).
@immutable
class MediaProbeResult {
  final String filePath;
  final String container;
  final int durationTicks;
  final int fileSizeBytes;
  final int? bitRate;
  final List<VideoStreamInfo> videoStreams;
  final List<AudioStreamInfo> audioStreams;

  const MediaProbeResult({
    required this.filePath,
    required this.container,
    required this.durationTicks,
    required this.fileSizeBytes,
    this.bitRate,
    this.videoStreams = const [],
    this.audioStreams = const [],
  })  : assert(durationTicks >= 0, 'durationTicks must be non-negative'),
        assert(fileSizeBytes >= 0, 'fileSizeBytes must be non-negative');

  bool get hasVideo => videoStreams.isNotEmpty;
  bool get hasAudio => audioStreams.isNotEmpty;

  VideoStreamInfo? get primaryVideoStream =>
      videoStreams.isNotEmpty ? videoStreams.first : null;

  AudioStreamInfo? get primaryAudioStream =>
      audioStreams.isNotEmpty ? audioStreams.first : null;

  int? get primaryWidth => primaryVideoStream?.width;
  int? get primaryHeight => primaryVideoStream?.height;

  int? get primaryFpsNumerator => primaryVideoStream?.fpsNumerator;
  int? get primaryFpsDenominator => primaryVideoStream?.fpsDenominator;

  double? get primaryFps => primaryVideoStream?.fps;

  /// Infers the primary asset kind (video, audio, or image) from probe stream topology.
  MediaKind get inferredKind {
    if (videoStreams.isNotEmpty) {
      final video = videoStreams.first;
      // Single-frame image files (e.g. png, jpeg, webp) often have 0 or negligible duration
      final isImageFormat = container.contains('image') ||
          container.contains('png') ||
          container.contains('jpeg') ||
          container.contains('jpg') ||
          video.codec == 'png' ||
          video.codec == 'mjpeg' ||
          video.codec == 'webp';
      if (durationTicks == 0 && isImageFormat) {
        return MediaKind.image;
      }
      return MediaKind.video;
    }
    if (audioStreams.isNotEmpty) {
      return MediaKind.audio;
    }
    // Fallback based on container
    if (container.contains('png') || container.contains('jpeg') || container.contains('image')) {
      return MediaKind.image;
    }
    return MediaKind.video;
  }

  Map<String, Object?> toJson() => {
        'file_path': filePath,
        'container': container,
        'duration_ticks': durationTicks,
        'file_size_bytes': fileSizeBytes,
        if (bitRate != null) 'bit_rate': bitRate,
        'video_streams': videoStreams.map((v) => v.toJson()).toList(),
        'audio_streams': audioStreams.map((a) => a.toJson()).toList(),
        'inferred_kind': inferredKind.wireName,
      };

  factory MediaProbeResult.fromJson(Map<String, Object?> json) {
    return MediaProbeResult(
      filePath: json['file_path'] as String,
      container: json['container'] as String,
      durationTicks: json['duration_ticks'] as int,
      fileSizeBytes: json['file_size_bytes'] as int,
      bitRate: json['bit_rate'] as int?,
      videoStreams: (json['video_streams'] as List<dynamic>? ?? [])
          .map((v) => VideoStreamInfo.fromJson(v as Map<String, Object?>))
          .toList(),
      audioStreams: (json['audio_streams'] as List<dynamic>? ?? [])
          .map((a) => AudioStreamInfo.fromJson(a as Map<String, Object?>))
          .toList(),
    );
  }

  @override
  String toString() =>
      'MediaProbeResult($filePath, container: $container, ${durationTicks}t, video: ${videoStreams.length}, audio: ${audioStreams.length})';
}
