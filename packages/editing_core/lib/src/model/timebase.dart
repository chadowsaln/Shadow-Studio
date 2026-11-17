import 'package:meta/meta.dart';

/// Timebase definition aligned with RenderGraph Timebase schema.
///
/// Closed schema: ticks_per_second (const 1,000,000), fps_num, fps_den, sample_rate, channels.
@immutable
class Timebase {
  static const int standardTicksPerSecond = 1000000;

  final int ticksPerSecond;
  final int fpsNum;
  final int fpsDen;
  final int sampleRate; // 44100, 48000, 96000
  final int channels;   // 1 to 8

  const Timebase({
    this.ticksPerSecond = standardTicksPerSecond,
    required this.fpsNum,
    required this.fpsDen,
    this.sampleRate = 48000,
    this.channels = 2,
  })  : assert(ticksPerSecond == 1000000, 'ticksPerSecond must be 1,000,000'),
        assert(fpsNum >= 1, 'fpsNum must be >= 1'),
        assert(fpsDen >= 1, 'fpsDen must be >= 1'),
        assert(sampleRate == 44100 || sampleRate == 48000 || sampleRate == 96000,
            'sampleRate must be 44100, 48000, or 96000'),
        assert(channels >= 1 && channels <= 8, 'channels must be 1 to 8');

  /// Standard 30 fps (30/1).
  factory Timebase.fps30({int sampleRate = 48000, int channels = 2}) => Timebase(
        fpsNum: 30,
        fpsDen: 1,
        sampleRate: sampleRate,
        channels: channels,
      );

  /// NTSC standard 29.97 fps (30000/1001).
  factory Timebase.ntsc2997({int sampleRate = 48000, int channels = 2}) => Timebase(
        fpsNum: 30000,
        fpsDen: 1001,
        sampleRate: sampleRate,
        channels: channels,
      );

  /// Standard 60 fps (60/1).
  factory Timebase.fps60({int sampleRate = 48000, int channels = 2}) => Timebase(
        fpsNum: 60,
        fpsDen: 1,
        sampleRate: sampleRate,
        channels: channels,
      );

  /// Cinematic 24 fps (24/1).
  factory Timebase.fps24({int sampleRate = 48000, int channels = 2}) => Timebase(
        fpsNum: 24,
        fpsDen: 1,
        sampleRate: sampleRate,
        channels: channels,
      );

  Timebase copyWith({
    int? fpsNum,
    int? fpsDen,
    int? sampleRate,
    int? channels,
  }) {
    return Timebase(
      ticksPerSecond: standardTicksPerSecond,
      fpsNum: fpsNum ?? this.fpsNum,
      fpsDen: fpsDen ?? this.fpsDen,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
    );
  }

  Map<String, Object> toJson() => {
        'ticks_per_second': ticksPerSecond,
        'fps_num': fpsNum,
        'fps_den': fpsDen,
        'sample_rate': sampleRate,
        'channels': channels,
      };

  factory Timebase.fromJson(Map<String, Object?> json) {
    return Timebase(
      ticksPerSecond: (json['ticks_per_second'] as int?) ?? standardTicksPerSecond,
      fpsNum: json['fps_num'] as int,
      fpsDen: json['fps_den'] as int,
      sampleRate: (json['sample_rate'] as int?) ?? 48000,
      channels: (json['channels'] as int?) ?? 2,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Timebase &&
          runtimeType == other.runtimeType &&
          ticksPerSecond == other.ticksPerSecond &&
          fpsNum == other.fpsNum &&
          fpsDen == other.fpsDen &&
          sampleRate == other.sampleRate &&
          channels == other.channels;

  @override
  int get hashCode => Object.hash(ticksPerSecond, fpsNum, fpsDen, sampleRate, channels);

  @override
  String toString() => 'Timebase($fpsNum/$fpsDen fps, ${sampleRate}Hz, ${channels}ch)';
}
