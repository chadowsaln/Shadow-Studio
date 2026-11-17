import 'package:meta/meta.dart';

/// Output container for a render preset.
enum RenderContainer {
  mp4,
  webm,
  wav,
  mp3,
  gif;

  String get wireName => name;

  bool get hasVideo => this == mp4 || this == webm || this == gif;
  bool get hasAudio => this != gif;

  /// File extension used for the atomic output path.
  String get fileExtension => switch (this) {
    RenderContainer.mp4 => 'mp4',
    RenderContainer.webm => 'webm',
    RenderContainer.wav => 'wav',
    RenderContainer.mp3 => 'mp3',
    RenderContainer.gif => 'gif',
  };

  static RenderContainer fromWireName(String value) {
    return RenderContainer.values.firstWhere(
      (c) => c.wireName == value,
      orElse: () => throw ArgumentError('Unknown container: $value'),
    );
  }
}

/// Resolved export configuration for one render job.
///
/// Mirrors `RenderPresetV1` (§أ.10) restricted to the fields the FFmpeg
/// backend honours. Every field is validated at construction so a bad preset
/// fails before any process is spawned (V-18 `RG_PRESET_CONFLICT`).
@immutable
class RenderPreset {
  final String id;
  final String label;
  final RenderContainer container;
  final String videoCodec;
  final String? videoPreset;
  final int? crf;
  final int? videoBitrateKbps;
  final int? width;
  final int? height;
  final int? fpsNumerator;
  final int? fpsDenominator;
  final String pixelFormat;
  final String audioCodec;
  final int? audioBitrateKbps;
  final int audioSampleRate;
  final int audioChannels;
  final bool fastStart;
  final bool hasVideo;
  final bool hasAudio;

  RenderPreset({
    required this.id,
    required this.label,
    required this.container,
    this.videoCodec = 'libx264',
    this.videoPreset = 'veryfast',
    this.crf,
    this.videoBitrateKbps,
    this.width,
    this.height,
    this.fpsNumerator,
    this.fpsDenominator,
    this.pixelFormat = 'yuv420p',
    this.audioCodec = 'aac',
    this.audioBitrateKbps,
    this.audioSampleRate = 48000,
    this.audioChannels = 2,
    this.fastStart = true,
    bool? hasVideo,
    bool? hasAudio,
  }) : hasVideo = hasVideo ?? container.hasVideo,
       hasAudio = hasAudio ?? container.hasAudio {
    final wantsVideo = this.hasVideo;
    if (!wantsVideo &&
        videoCodec.isNotEmpty &&
        container != RenderContainer.mp3) {
      // Audio-only presets keep the field empty; anything else is a conflict.
      throw ArgumentError(
        'Preset $id declares a video codec but has no video track',
      );
    }
    if (crf != null && videoBitrateKbps != null) {
      throw ArgumentError(
        'Preset $id cannot set both crf and videoBitrateKbps (V-18)',
      );
    }
    if (wantsVideo && crf == null && videoBitrateKbps == null) {
      throw ArgumentError('Preset $id needs either crf or videoBitrateKbps');
    }
    if (audioSampleRate != 44100 &&
        audioSampleRate != 48000 &&
        audioSampleRate != 96000) {
      throw ArgumentError(
        'Preset $id uses unsupported sample rate $audioSampleRate',
      );
    }
    if (audioChannels < 1 || audioChannels > 8) {
      throw ArgumentError('Preset $id uses unsupported channel count');
    }
    final w = width;
    if (w != null && (w < 2 || w.isOdd)) {
      throw ArgumentError('Preset $id width must be a positive even number');
    }
    final h = height;
    if (h != null && (h < 2 || h.isOdd)) {
      throw ArgumentError('Preset $id height must be a positive even number');
    }
  }

  /// H.264 / MP4, 1080p — the default preset from §4.5.
  static final RenderPreset mp4H2641080p = RenderPreset(
    id: 'mp4-h264-1080p',
    label: 'YouTube 1080p (H.264 · 1920x1080 · 30fps · 12 Mbps)',
    container: RenderContainer.mp4,
    width: 1920,
    height: 1080,
    crf: 20,
    videoBitrateKbps: null,
    audioBitrateKbps: 192,
  );

  static final RenderPreset mp4H264720p = RenderPreset(
    id: 'mp4-h264-720p',
    label: 'Web 720p (H.264 · 1280x720 · 30fps · 4 Mbps)',
    container: RenderContainer.mp4,
    width: 1280,
    height: 720,
    videoBitrateKbps: 4000,
    audioBitrateKbps: 160,
  );

  static final RenderPreset mp4H2644k = RenderPreset(
    id: 'mp4-h264-4k',
    label: '4K Master (H.264 · 3840x2160 · 30fps)',
    container: RenderContainer.mp4,
    width: 3840,
    height: 2160,
    crf: 18,
    audioBitrateKbps: 320,
  );

  static final RenderPreset webmVp9 = RenderPreset(
    id: 'webm-vp9',
    label: 'WebM (VP9 · 1080p · Opus)',
    container: RenderContainer.webm,
    videoCodec: 'libvpx-vp9',
    videoPreset: null,
    width: 1920,
    height: 1080,
    crf: 32,
    audioCodec: 'libopus',
    audioBitrateKbps: 128,
    fastStart: false,
  );

  static final RenderPreset wavPcm = RenderPreset(
    id: 'wav-pcm',
    label: 'WAV (PCM 16-bit · 48 kHz stereo)',
    container: RenderContainer.wav,
    videoCodec: '',
    hasVideo: false,
    hasAudio: true,
    audioCodec: 'pcm_s16le',
    audioBitrateKbps: null,
  );

  static final RenderPreset mp3_320 = RenderPreset(
    id: 'mp3-320',
    label: 'MP3 320 kbps',
    container: RenderContainer.mp3,
    videoCodec: '',
    hasVideo: false,
    hasAudio: true,
    audioCodec: 'libmp3lame',
    audioBitrateKbps: 320,
    fastStart: false,
  );

  static final RenderPreset gif = RenderPreset(
    id: 'gif',
    label: 'GIF (15s limit · 480px wide)',
    container: RenderContainer.gif,
    videoCodec: 'gif',
    videoPreset: null,
    width: 480,
    crf: null,
    videoBitrateKbps: 1,
    pixelFormat: 'rgb24',
    hasAudio: false,
    audioCodec: '',
    audioBitrateKbps: null,
    audioSampleRate: 44100,
    audioChannels: 1,
    fastStart: false,
  );

  /// Every built-in preset, keyed by id (§4.5 MVP list).
  static final Map<String, RenderPreset> builtins = <String, RenderPreset>{
    mp4H2641080p.id: mp4H2641080p,
    mp4H264720p.id: mp4H264720p,
    mp4H2644k.id: mp4H2644k,
    webmVp9.id: webmVp9,
    wavPcm.id: wavPcm,
    mp3_320.id: mp3_320,
    gif.id: gif,
  };

  static RenderPreset byId(String id) {
    final preset = builtins[id];
    if (preset == null) {
      throw ArgumentError(
        'Unknown render preset "$id"; known: ${builtins.keys.join(', ')}',
      );
    }
    return preset;
  }

  /// Builds a custom preset from user overrides, starting from [base].
  factory RenderPreset.custom({
    required String id,
    required String label,
    required RenderPreset base,
    int? width,
    int? height,
    int? crf,
    int? videoBitrateKbps,
    int? audioBitrateKbps,
    String? videoCodec,
    String? audioCodec,
    int? audioSampleRate,
    int? audioChannels,
    bool? fastStart,
  }) {
    final merged = RenderPreset(
      id: id,
      label: label,
      container: base.container,
      videoCodec: videoCodec ?? base.videoCodec,
      videoPreset: base.videoPreset,
      crf: crf ?? (videoBitrateKbps == null ? base.crf : null),
      videoBitrateKbps: videoBitrateKbps ?? base.videoBitrateKbps,
      width: width ?? base.width,
      height: height ?? base.height,
      fpsNumerator: base.fpsNumerator,
      fpsDenominator: base.fpsDenominator,
      pixelFormat: base.pixelFormat,
      audioCodec: audioCodec ?? base.audioCodec,
      audioBitrateKbps: audioBitrateKbps ?? base.audioBitrateKbps,
      audioSampleRate: audioSampleRate ?? base.audioSampleRate,
      audioChannels: audioChannels ?? base.audioChannels,
      fastStart: fastStart ?? base.fastStart,
      hasVideo: base.hasVideo,
      hasAudio: base.hasAudio,
    );
    return merged;
  }

  RenderPreset copyWith({
    int? width,
    int? height,
    int? crf,
    int? videoBitrateKbps,
    int? audioBitrateKbps,
    int? audioSampleRate,
    int? audioChannels,
  }) {
    return RenderPreset(
      id: id,
      label: label,
      container: container,
      videoCodec: videoCodec,
      videoPreset: videoPreset,
      crf: crf ?? this.crf,
      videoBitrateKbps: videoBitrateKbps ?? this.videoBitrateKbps,
      width: width ?? this.width,
      height: height ?? this.height,
      fpsNumerator: fpsNumerator,
      fpsDenominator: fpsDenominator,
      pixelFormat: pixelFormat,
      audioCodec: audioCodec,
      audioBitrateKbps: audioBitrateKbps ?? this.audioBitrateKbps,
      audioSampleRate: audioSampleRate ?? this.audioSampleRate,
      audioChannels: audioChannels ?? this.audioChannels,
      fastStart: fastStart,
      hasVideo: hasVideo,
      hasAudio: hasAudio,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'container': container.wireName,
    'video_codec': videoCodec,
    'crf': crf,
    'video_bitrate_kbps': videoBitrateKbps,
    'width': width,
    'height': height,
    'audio_codec': audioCodec,
    'audio_bitrate_kbps': audioBitrateKbps,
    'audio_sample_rate': audioSampleRate,
    'audio_channels': audioChannels,
    'faststart': fastStart,
  };

  @override
  String toString() => 'RenderPreset($id, ${container.wireName})';
}
