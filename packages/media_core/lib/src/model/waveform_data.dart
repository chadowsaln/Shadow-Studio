import 'package:meta/meta.dart';

/// Pre-computed audio waveform peak amplitudes for timeline visual rendering.
///
/// Peak amplitudes are normalized in the range [0.0, 1.0].
/// Time intervals are in integer ticks (1 tick = 1/1,000,000 s).
@immutable
class WaveformData {
  /// Number of peak samples per second of timeline audio (typically 50-100).
  final int samplesPerSecond;

  /// Total duration of audio in integer ticks.
  final int durationTicks;

  /// Normalized peak magnitudes [0.0, 1.0].
  final List<double> peaks;

  /// Optional negative peak magnitudes [-1.0, 0.0] for symmetric dual-channel rendering.
  final List<double>? minPeaks;

  /// Optional positive peak magnitudes [0.0, 1.0] for symmetric dual-channel rendering.
  final List<double>? maxPeaks;

  const WaveformData({
    required this.samplesPerSecond,
    required this.durationTicks,
    required this.peaks,
    this.minPeaks,
    this.maxPeaks,
  })  : assert(samplesPerSecond > 0, 'samplesPerSecond must be positive'),
        assert(durationTicks >= 0, 'durationTicks must be non-negative');

  int get sampleCount => peaks.length;

  Map<String, Object?> toJson() => {
        'samples_per_second': samplesPerSecond,
        'duration_ticks': durationTicks,
        'peaks': peaks,
        if (minPeaks != null) 'min_peaks': minPeaks,
        if (maxPeaks != null) 'max_peaks': maxPeaks,
      };

  factory WaveformData.fromJson(Map<String, Object?> json) {
    return WaveformData(
      samplesPerSecond: json['samples_per_second'] as int,
      durationTicks: json['duration_ticks'] as int,
      peaks: (json['peaks'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList(),
      minPeaks: (json['min_peaks'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
      maxPeaks: (json['max_peaks'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
    );
  }

  @override
  String toString() =>
      'WaveformData(${peaks.length} samples @ ${samplesPerSecond}Hz, ${durationTicks}t)';
}
