import '../model/media_probe_result.dart';
import '../model/waveform_data.dart';

/// Worker abstraction for native media processing (probe, hash, thumbnail, proxy, waveform).
///
/// Implementations include:
/// - [FakeMediaWorker]: in-memory mocked worker for rapid hermetic tests.
/// - [FfmpegMediaWorker]: interim CLI runner wrapping system ffprobe and ffmpeg.
/// - Native worker (Phase 7): out-of-process C++ binary via framed MessagePack.
abstract interface class MediaWorker {
  /// Inspects stream and container format details of a media file.
  ///
  /// Throws [MediaException] on missing file, corrupt media, or unsupported codec.
  Future<MediaProbeResult> probe(String filePath);

  /// Computes the 256-bit BLAKE3 cryptographic hash of a file for library deduplication.
  Future<String> computeBlake3(String filePath);

  /// Generates a single-frame visual thumbnail at [atTick] in integer ticks.
  ///
  /// Writes to [destinationPath] and returns the absolute destination path.
  Future<String> generateThumbnail(
    String filePath, {
    required int atTick,
    required String destinationPath,
    int? width,
    int? height,
  });

  /// Generates an edit proxy (e.g. 720p H.264 MP4).
  ///
  /// Uses atomic write semantics (writing to destinationPath.part before rename).
  /// Returns the absolute destination path.
  Future<String> generateProxy(
    String filePath, {
    required String destinationPath,
    int? targetHeight,
  });

  /// Computes normalized peak audio waveform samples for visual timeline display.
  ///
  /// [samplesPerSecond] specifies density (default 100 Hz).
  Future<WaveformData> generateWaveform(
    String filePath, {
    int samplesPerSecond = 100,
  });

  /// Releases worker resources, shuts down background processes or connections.
  Future<void> dispose();
}
