import 'dart:io';

import 'package:media_core/media_core.dart';
import 'package:meta/meta.dart';
import 'package:shadow_contracts/shadow_contracts.dart';

import 'workspace_paths.dart';

Map<String, Object?> _closedObject({
  Map<String, Object?> properties = const <String, Object?>{},
  List<String> required = const <String>[],
}) {
  return <String, Object?>{
    'type': 'object',
    'properties': properties,
    'required': required,
    'additionalProperties': false,
  };
}

/// Real media inspection backed by ffprobe through [MediaWorker].
class MediaProbeTool implements AgentTool {
  MediaProbeTool({
    MediaWorker? worker,
    this.ffmpegBinary = 'ffmpeg',
    this.ffprobeBinary = 'ffprobe',
  }) : _worker = worker ??
            FfmpegMediaWorker(
              ffmpegBinary: ffmpegBinary,
              ffprobeBinary: ffprobeBinary,
            );

  final MediaWorker _worker;
  final String ffmpegBinary;
  final String ffprobeBinary;

  @override
  String get name => 'media_probe';

  @override
  String get description =>
      'Probes real media metadata (container, duration, video/audio streams) using ffprobe.';

  @override
  ToolRiskLevel get riskLevel => ToolRiskLevel.safe;

  @override
  bool get idempotent => true;

  @override
  Duration get timeout => const Duration(seconds: 30);

  @override
  Map<String, Object?> get inputSchema => _closedObject(
    properties: const <String, Object?>{
      'path': <String, Object?>{'type': 'string', 'minLength': 1},
    },
    required: const <String>['path'],
  );

  @override
  Map<String, Object?> get outputSchema => _closedObject(
    properties: const <String, Object?>{
      'path': <String, Object?>{'type': 'string'},
      'probe': <String, Object?>{'type': 'object'},
    },
    required: const <String>['path', 'probe'],
  );

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> arguments,
  ) async {
    context.cancel.throwIfCancelled();
    final raw = arguments['path'] as String;
    final path = resolveWorkspacePath(raw, context.workspaceRoot);
    try {
      final probe = await _worker.probe(path);
      return ToolResult.ok(data: <String, Object?>{
        'path': path,
        'probe': probe.toJson(),
      });
    } on MediaException catch (error) {
      return ToolResult.failure(
        code: _codeFor(error),
        message: error.message,
        data: <String, Object?>{'path': path, 'code': error.code},
      );
    }
  }

  static String _codeFor(MediaException error) => error.code;
}

/// Aggregate of the real ffmpeg analyses produced by [MediaAnalysisTool].
class MediaAnalysisResult {
  const MediaAnalysisResult({
    required this.path,
    required this.hasVideo,
    required this.hasAudio,
    required this.scenes,
    required this.blackSegments,
    required this.volume,
    this.waveformSamples,
    this.warnings = const <String>[],
  });

  final String path;
  final bool hasVideo;
  final bool hasAudio;
  final List<Map<String, Object?>> scenes;
  final List<Map<String, Object?>> blackSegments;
  final Map<String, Object?>? volume;
  final int? waveformSamples;
  final List<String> warnings;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'has_video': hasVideo,
    'has_audio': hasAudio,
    'scene_count': scenes.length,
    'scenes': scenes,
    'black_segment_count': blackSegments.length,
    'black_segments': blackSegments,
    if (volume != null) 'volume': volume,
    if (waveformSamples != null) 'waveform_samples': waveformSamples,
    'warnings': warnings,
  };
}

/// Real content analysis: scene changes, black segments, loudness and waveform.
///
/// Every number comes from an ffmpeg/ffprobe run over the actual file. The tool
/// never fabricates analysis data and never modifies the source media.
class MediaAnalysisTool implements AgentTool {
  MediaAnalysisTool({
    MediaWorker? worker,
    this.ffmpegBinary = 'ffmpeg',
    this.sceneThreshold = 0.3,
    this.blackMinDurationSeconds = 0.1,
    this.blackPixelThreshold = 0.1,
    this.waveformSamplesPerSecond = 10,
  }) : _worker = worker ??
            FfmpegMediaWorker(
              ffmpegBinary: ffmpegBinary,
              ffprobeBinary: 'ffprobe',
            );

  final MediaWorker _worker;
  final String ffmpegBinary;
  final double sceneThreshold;
  final double blackMinDurationSeconds;
  final double blackPixelThreshold;
  final int waveformSamplesPerSecond;

  @override
  String get name => 'media_analysis';

  @override
  String get description =>
      'Analyzes real media content: scene changes, black segments, loudness and waveform peaks.';

  @override
  ToolRiskLevel get riskLevel => ToolRiskLevel.restricted;

  @override
  bool get idempotent => true;

  @override
  Duration get timeout => const Duration(minutes: 3);

  @override
  Map<String, Object?> get inputSchema => _closedObject(
    properties: const <String, Object?>{
      'path': <String, Object?>{'type': 'string', 'minLength': 1},
    },
    required: const <String>['path'],
  );

  @override
  Map<String, Object?> get outputSchema => _closedObject(
    properties: const <String, Object?>{
      'analysis': <String, Object?>{'type': 'object'},
    },
    required: const <String>['analysis'],
  );

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> arguments,
  ) async {
    context.cancel.throwIfCancelled();
    final raw = arguments['path'] as String;
    final path = resolveWorkspacePath(raw, context.workspaceRoot);
    final file = File(path);
    if (!await file.exists()) {
      return ToolResult.failure(
        code: ShadowErrorCode.mediaAssetMissing,
        message: 'Media file not found',
        data: <String, Object?>{'path': path},
      );
    }

    final warnings = <String>[];
    MediaProbeResult? probe;
    try {
      probe = await _worker.probe(path);
    } on MediaException catch (error) {
      return ToolResult.failure(
        code: error.code,
        message: 'Unable to probe media: ${error.message}',
        data: <String, Object?>{'path': path},
      );
    }

    final scenes = <Map<String, Object?>>[];
    final blackSegments = <Map<String, Object?>>[];

    if (probe.hasVideo) {
      context.cancel.throwIfCancelled();
      try {
        final result = await Process.run(
          ffmpegBinary,
          <String>[
            '-hide_banner',
            '-nostats',
            '-i',
            path,
            '-map',
            '0:v:0',
            '-vf',
            "select='gt(scene,$sceneThreshold)',showinfo",
            '-an',
            '-f',
            'null',
            '-',
          ],
        );
        scenes.addAll(parseSceneTimestamps(result.stderr.toString()));
      } on ProcessException {
        warnings.add('scene detection unavailable');
      }

      context.cancel.throwIfCancelled();
      try {
        final result = await Process.run(
          ffmpegBinary,
          <String>[
            '-hide_banner',
            '-nostats',
            '-i',
            path,
            '-map',
            '0:v:0',
            '-vf',
            'blackdetect=d=$blackMinDurationSeconds:pix_th=$blackPixelThreshold',
            '-an',
            '-f',
            'null',
            '-',
          ],
        );
        blackSegments.addAll(parseBlackSegments(result.stderr.toString()));
      } on ProcessException {
        warnings.add('black segment detection unavailable');
      }
    }

    Map<String, Object?>? volume;
    if (probe.hasAudio) {
      context.cancel.throwIfCancelled();
      try {
        final result = await Process.run(
          ffmpegBinary,
          <String>[
            '-hide_banner',
            '-nostats',
            '-i',
            path,
            '-map',
            '0:a:0',
            '-af',
            'volumedetect',
            '-vn',
            '-f',
            'null',
            '-',
          ],
        );
        volume = parseVolume(result.stderr.toString());
      } on ProcessException {
        warnings.add('loudness analysis unavailable');
      }
    }

    int? waveformSamples;
    if (probe.hasAudio) {
      context.cancel.throwIfCancelled();
      try {
        final waveform = await _worker.generateWaveform(
          path,
          samplesPerSecond: waveformSamplesPerSecond,
        );
        waveformSamples = waveform.sampleCount;
      } on MediaException {
        warnings.add('waveform unavailable');
      }
    }

    final analysis = MediaAnalysisResult(
      path: path,
      hasVideo: probe.hasVideo,
      hasAudio: probe.hasAudio,
      scenes: scenes,
      blackSegments: blackSegments,
      volume: volume,
      waveformSamples: waveformSamples,
      warnings: warnings,
    );
    return ToolResult.ok(data: <String, Object?>{'analysis': analysis.toJson()});
  }

  /// Parses `showinfo` stderr lines into `{index, time_seconds, time_ticks}`.
  @visibleForTesting
  static List<Map<String, Object?>> parseSceneTimestamps(String stderr) {
    final scenes = <Map<String, Object?>>[];
    final pattern = RegExp(r'pts_time:([0-9]+(?:\.[0-9]+)?)');
    var index = 0;
    for (final match in pattern.allMatches(stderr)) {
      final seconds = double.tryParse(match.group(1)!);
      if (seconds == null) continue;
      scenes.add(<String, Object?>{
        'index': index++,
        'time_seconds': seconds,
        'time_ticks': (seconds * 1000000).round(),
      });
    }
    return scenes;
  }

  /// Parses `blackdetect` stderr lines into black interval maps.
  @visibleForTesting
  static List<Map<String, Object?>> parseBlackSegments(String stderr) {
    final segments = <Map<String, Object?>>[];
    final pattern = RegExp(
      r'black_start:([0-9]+(?:\.[0-9]+)?)\s+black_end:([0-9]+(?:\.[0-9]+)?)\s+black_duration:([0-9]+(?:\.[0-9]+)?)',
    );
    for (final match in pattern.allMatches(stderr)) {
      final start = double.tryParse(match.group(1)!);
      final end = double.tryParse(match.group(2)!);
      final duration = double.tryParse(match.group(3)!);
      if (start == null || end == null || duration == null) continue;
      segments.add(<String, Object?>{
        'start_seconds': start,
        'end_seconds': end,
        'duration_seconds': duration,
        'start_ticks': (start * 1000000).round(),
        'end_ticks': (end * 1000000).round(),
      });
    }
    return segments;
  }

  /// Parses `volumedetect` stderr into mean/max dB values.
  @visibleForTesting
  static Map<String, Object?>? parseVolume(String stderr) {
    final mean = RegExp(r'mean_volume:\s*(-?[0-9.]+)\s*dB')
        .firstMatch(stderr)
        ?.group(1);
    final max = RegExp(r'max_volume:\s*(-?[0-9.]+)\s*dB')
        .firstMatch(stderr)
        ?.group(1);
    if (mean == null && max == null) return null;
    return <String, Object?>{
      'mean_db': double.tryParse(mean ?? ''),
      'max_db': double.tryParse(max ?? ''),
      'clipped': max != null && double.tryParse(max)! >= 0.0,
    };
  }
}