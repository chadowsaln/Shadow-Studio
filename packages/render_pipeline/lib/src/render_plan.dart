import 'dart:convert';

import 'render_graph_doc.dart';
import 'render_preset.dart';

/// A fully resolved FFmpeg invocation for one render.
///
/// The plan is pure data: building it touches no filesystem and spawns no
/// process, so it can be unit-tested and reused by the preview and export
/// paths alike.
class RenderPlan {
  const RenderPlan({
    required this.inputs,
    required this.filterComplex,
    required this.videoLabel,
    required this.audioLabel,
    required this.videoArgs,
    required this.audioArgs,
    required this.outputArgs,
  });

  /// Input arguments in order, e.g. `['-i', '/tmp/a.mp4']`.
  final List<String> inputs;

  /// The `-filter_complex` expression, or `null` when no filter is needed.
  final String? filterComplex;

  /// Output pad label for video (`null` for audio-only exports).
  final String? videoLabel;

  /// Output pad label for audio (`null` for silent exports).
  final String? audioLabel;

  /// Codec arguments applied before the output path.
  final List<String> videoArgs;
  final List<String> audioArgs;
  final List<String> outputArgs;

  bool get hasVideo => videoLabel != null;

  bool get hasAudio => audioLabel != null;

  List<String> toArgs() => <String>[
    ...inputs,
    if (filterComplex != null) ...<String>['-filter_complex', filterComplex!],
    if (videoLabel != null) ...<String>['-map', '[$videoLabel]'],
    if (audioLabel != null) ...<String>['-map', '[$audioLabel]'],
    ...videoArgs,
    ...audioArgs,
    ...outputArgs,
  ];
}

/// Builds a [RenderPlan] from a validated [RenderGraphDoc] and a [RenderPreset].
class RenderPlanner {
  const RenderPlanner();

  static const int ticksPerSecond = 1000000;

  RenderPlan plan({
    required RenderGraphDoc graph,
    required RenderPreset preset,
  }) {
    final builder = _Builder(graph: graph, preset: preset);
    return builder.build();
  }
}

class _Builder {
  _Builder({required this.graph, required this.preset});

  final RenderGraphDoc graph;
  final RenderPreset preset;

  static const int ticksPerSecond = 1000000;

  final List<String> inputs = <String>[];
  final Map<String, int> inputIndex = <String, int>{};
  final List<String> filters = <String>[];

  int _inputFor(String uri) {
    final existing = inputIndex[uri];
    if (existing != null) return existing;
    final index = inputs.length;
    inputs.add(uri);
    inputIndex[uri] = index;
    return index;
  }

  String _seconds(int ticks) {
    final value = ticks / ticksPerSecond;
    return value.toStringAsFixed(6);
  }

  RenderPlan build() {
    final size =
        '${preset.width ?? graph.profile.width}'
        'x${preset.height ?? graph.profile.height}';

    String? currentVideo;
    final videoTracks = graph.videoTracks;
    if (preset.hasVideo && videoTracks.isNotEmpty) {
      filters.add(
        'color=c=black:s=$size:r=${_formatRate()}:d=${_seconds(graph.durationTicks)}'
        '[base0]',
      );
      currentVideo = 'base0';
    }

    var baseIndex = 0;
    for (final track in videoTracks) {
      final assembled = _assembleVideoTrack(track);
      if (assembled == null) continue;
      final out = 'base${baseIndex + 1}';
      filters.add('[$currentVideo][$assembled]overlay=x=0:y=0[$out]');
      currentVideo = out;
      baseIndex++;
    }

    final overlayTracks = preset.hasVideo
        ? graph.overlayTracks
        : const <RgTrack>[];
    var overlayIndex = 0;
    for (final track in overlayTracks) {
      for (final layer in track.textLayers) {
        final index = _inputFor(layer.rasterUri);
        final start = _seconds(layer.startTicks);
        final end = _seconds(layer.endTicks);
        final fadeIn = layer.animationInTicks;
        final fadeOut = layer.animationOutTicks;
        final chain = <String>['[$index:v]format=rgba'];
        if (layer.animationInKind != 'none' && fadeIn > 0) {
          chain.add('fade=t=in:st=$start:d=${_seconds(fadeIn)}:alpha=1');
        }
        if (layer.animationOutKind != 'none' && fadeOut > 0) {
          chain.add(
            'fade=t=out:st=${_seconds(layer.endTicks - fadeOut)}'
            ':d=${_seconds(fadeOut)}:alpha=1',
          );
        }
        final label = 'text$overlayIndex';
        filters.add('${chain.join(',')}[$label]');
        final x = layer.transform.xPx;
        final y = layer.transform.yPx;
        final out = 'base${baseIndex + 1}';
        filters.add(
          '[$currentVideo][$label]overlay=x=$x:y=$y'
          ":enable='between(t,$start,$end)'[$out]",
        );
        currentVideo = out;
        baseIndex++;
        overlayIndex++;
      }
    }

    String? currentAudio;
    final audioTracks = graph.audioTracks;
    if (audioTracks.isNotEmpty) {
      final labels = <String>[];
      for (final track in audioTracks) {
        for (var i = 0; i < track.audioClips.length; i++) {
          labels.add(_audioClipChain(track, track.audioClips[i], i));
        }
      }
      if (labels.isEmpty) {
        currentAudio = null;
      } else if (labels.length == 1) {
        currentAudio = labels.single;
      } else {
        filters.add(
          '${labels.map((l) => '[$l]').join()}'
          'amix=inputs=${labels.length}:normalize=0:dropout_transition=0[aout]',
        );
        currentAudio = 'aout';
      }
    }

    final videoLabel = currentVideo == null || !preset.hasVideo ? null : 'vout';
    if (currentVideo != null && preset.hasVideo) {
      filters.add('[$currentVideo]null[$videoLabel]');
    }
    if (currentAudio != null && currentAudio != 'aout') {
      filters.add('[$currentAudio]anull[aout]');
    }
    final audioLabel = currentAudio == null ? null : 'aout';

    return RenderPlan(
      inputs: <String>[
        for (final uri in inputs) ...<String>['-i', _pathOf(uri)],
      ],
      filterComplex: filters.isEmpty ? null : filters.join(';'),
      videoLabel: videoLabel,
      audioLabel: audioLabel,
      videoArgs: _videoArgs(size),
      audioArgs: _audioArgs(),
      outputArgs: _outputArgs(),
    );
  }

  String get _size =>
      '${preset.width ?? graph.profile.width}'
      'x${preset.height ?? graph.profile.height}';

  String get _pad {
    final width = preset.width ?? graph.profile.width;
    final height = preset.height ?? graph.profile.height;
    return 'pad=$width:$height:(ow-iw)/2:(oh-ih)/2:color=black';
  }

  String _formatRate() {
    final num = graph.timebase.fpsNum;
    final den = graph.timebase.fpsDen;
    return den == 1 ? '$num' : '$num/$den';
  }

  String? _assembleVideoTrack(RgTrack track) {
    final clips = track.clips;
    if (clips.isEmpty) return null;

    final size = _size;
    final pad = _pad;
    final labels = <String>[];
    final durations = <double>[];

    for (var i = 0; i < clips.length; i++) {
      final clip = clips[i];
      final label = 'v${track.position}_$i';
      final duration = _seconds(clip.durationTicks);
      durations.add(clip.durationTicks / ticksPerSecond);

      if (clip.kind == 'color') {
        filters.add(
          'color=c=black:s=$size:r=${_formatRate()}:d=$duration[$label]',
        );
      } else {
        final uri = clip.sourceUri!;
        final index = _inputFor(uri);
        final sourceIn = _seconds(clip.sourceInTicks);
        final chain = <String>[
          '[$index:v]trim=start=$sourceIn:duration=$duration',
          'setpts=PTS-STARTPTS',
          'fps=${_formatRate()}',
          'scale=$size:force_original_aspect_ratio=decrease',
          pad,
          'setsar=1',
        ];
        if (clip.opacityPpm != 1000000) {
          chain.add(
            'colorchannelmixer=aa=${(clip.opacityPpm / 1000000).toStringAsFixed(4)}',
          );
        }
        chain.add('format=yuv420p');
        filters.add('${chain.join(',')}[$label]');
      }
      labels.add(label);
    }

    var current = labels.first;
    for (var i = 1; i < clips.length; i++) {
      final transition = _transitionBetween(track, i);
      final next = 'x${track.position}_$i';
      if (transition == null) {
        filters.add('[$current][${labels[i]}]concat=n=2:v=1:a=0[$next]');
        current = next;
        continue;
      }
      final transitionSeconds = transition.durationTicks / ticksPerSecond;
      final consumed = durations.take(i).reduce((a, b) => a + b);
      final offset = consumed - transitionSeconds;
      filters.add(
        '[$current][${labels[i]}]xfade='
        'transition=${transition.kind}:duration=${_seconds(transition.durationTicks)}'
        ':offset=${offset.toStringAsFixed(6)}[$next]',
      );
      current = next;
    }
    return current;
  }

  RgTransition? _transitionBetween(RgTrack track, int clipIndex) {
    final toClip = track.clips[clipIndex];
    for (final transition in track.transitions) {
      if (transition.toClipId == toClip.id) return transition;
    }
    return null;
  }

  String _audioClipChain(RgTrack track, RgAudioClip clip, int index) {
    final label = 'a${track.position}_$index';
    final duration = _seconds(clip.durationTicks);
    if (clip.sourceUri == null) {
      filters.add(
        'anullsrc=r=${graph.timebase.sampleRate}'
        ':cl=${_channelLayout()}:d=$duration[$label]',
      );
      return label;
    }
    final input = _inputFor(clip.sourceUri!);
    final chain = <String>[
      '[$input:a]atrim=start=${_seconds(clip.sourceInTicks)}'
          ':duration=$duration',
      'asetpts=PTS-STARTPTS',
    ];
    final gainDb = clip.gainMb / 1000.0;
    if (gainDb != 0) {
      chain.add('volume=${gainDb.toStringAsFixed(3)}dB');
    }
    if (clip.fadeInTicks > 0) {
      chain.add('afade=t=in:st=0:d=${_seconds(clip.fadeInTicks)}');
    }
    if (clip.fadeOutTicks > 0) {
      chain.add(
        'afade=t=out:st=${_seconds(clip.durationTicks - clip.fadeOutTicks)}'
        ':d=${_seconds(clip.fadeOutTicks)}',
      );
    }
    chain.add(
      'aformat=sample_rates=${graph.timebase.sampleRate}'
      ':channel_layouts=${_channelLayout()}',
    );
    filters.add('${chain.join(',')}[$label]');
    return label;
  }

  String _channelLayout() {
    final channels = graph.timebase.channels;
    return switch (channels) {
      1 => 'mono',
      2 => 'stereo',
      _ => '${channels}c',
    };
  }

  List<String> _videoArgs(String size) {
    if (!preset.hasVideo ||
        (graph.videoTracks.isEmpty && graph.overlayTracks.isEmpty)) {
      return const <String>[];
    }
    final args = <String>['-c:v', preset.videoCodec];
    if (preset.crf != null) {
      args.addAll(<String>['-crf', '${preset.crf}']);
    } else if (preset.videoBitrateKbps != null) {
      args.addAll(<String>['-b:v', '${preset.videoBitrateKbps}k']);
    }
    if (preset.videoPreset != null) {
      args.addAll(<String>['-preset', preset.videoPreset!]);
    }
    args.addAll(<String>[
      '-pix_fmt',
      preset.pixelFormat,
      '-r',
      '${graph.timebase.fpsNum}/${graph.timebase.fpsDen}',
      '-s',
      size,
    ]);
    return args;
  }

  List<String> _audioArgs() {
    if (!preset.hasAudio) return const <String>['-an'];
    return <String>[
      '-c:a',
      preset.audioCodec,
      if (preset.audioBitrateKbps != null) '-b:a' else '-c:a',
      if (preset.audioBitrateKbps != null) '${preset.audioBitrateKbps}k',
      '-ar',
      '${preset.audioSampleRate}',
      '-ac',
      '${preset.audioChannels}',
    ];
  }

  List<String> _outputArgs() {
    final args = <String>[];
    if (preset.fastStart) {
      args.addAll(<String>['-movflags', '+faststart']);
    }
    args.addAll(<String>['-t', _seconds(graph.durationTicks)]);
    return args;
  }

  String _pathOf(String uri) {
    if (uri.startsWith('file://')) {
      return Uri.parse(uri).toFilePath();
    }
    return uri;
  }
}

/// Serializes a plan to a JSON document for logs and the render queue UI.
String renderPlanToJson(RenderPlan plan) => jsonEncode(<String, Object?>{
  'inputs': plan.inputs,
  'filter_complex': plan.filterComplex,
  'video_label': plan.videoLabel,
  'audio_label': plan.audioLabel,
  'video_args': plan.videoArgs,
  'audio_args': plan.audioArgs,
  'output_args': plan.outputArgs,
});
