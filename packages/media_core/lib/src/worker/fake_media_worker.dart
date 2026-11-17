import 'dart:io';
import 'dart:math' as math;

import '../error/media_error.dart';
import '../hash/blake3.dart';
import '../model/media_probe_result.dart';
import '../model/media_stream_info.dart';
import '../model/waveform_data.dart';
import 'media_worker.dart';

/// In-memory fake implementation of [MediaWorker] for hermetic, fast testing (< 10 ms).
///
/// Requires no GPU, no network, and no external FFmpeg/MLT dependencies.
/// Supports programmatic fault injection to test error recovery branches.
class FakeMediaWorker implements MediaWorker {
  /// Custom mocked probe results keyed by file path.
  final Map<String, MediaProbeResult> mockProbes = {};

  /// Custom mocked hashes keyed by file path.
  final Map<String, String> mockHashes = {};

  /// Fault injection flags.
  bool shouldFailProbe = false;
  bool shouldCrashEngine = false;
  bool shouldBeUnavailable = false;
  bool shouldReportCorrupt = false;
  bool shouldReportUnsupported = false;

  /// Call invocation counters for testing.
  int probeCalls = 0;
  int hashCalls = 0;
  int thumbnailCalls = 0;
  int proxyCalls = 0;
  int waveformCalls = 0;
  bool isDisposed = false;

  void _checkDisposedOrCrashed() {
    if (isDisposed || shouldBeUnavailable) {
      throw MediaException.workerUnavailable('FakeMediaWorker is disposed or offline');
    }
    if (shouldCrashEngine) {
      throw MediaException.engineCrash('Simulated worker process death', exitCode: 139);
    }
  }

  @override
  Future<MediaProbeResult> probe(String filePath) async {
    _checkDisposedOrCrashed();
    probeCalls++;

    final file = File(filePath);
    if (!file.existsSync() && !mockProbes.containsKey(filePath)) {
      throw MediaException.assetMissing(filePath);
    }

    if (shouldReportUnsupported) {
      throw MediaException.unsupported('Unsupported codec/container', path: filePath);
    }
    if (shouldReportCorrupt) {
      throw MediaException.corrupt('Corrupted header bytes', path: filePath);
    }
    if (shouldFailProbe) {
      throw MediaException.corrupt('Probe inspection failed', path: filePath);
    }

    if (mockProbes.containsKey(filePath)) {
      return mockProbes[filePath]!;
    }

    // Default mock probe: 10 seconds 1080p video with stereo audio
    return MediaProbeResult(
      filePath: filePath,
      container: 'mov,mp4,m4a,3gp,3g2,mj2',
      durationTicks: 10000000, // 10 seconds
      fileSizeBytes: file.existsSync() ? file.lengthSync() : 1024 * 1024,
      videoStreams: [
        const VideoStreamInfo(
          index: 0,
          codec: 'h264',
          width: 1920,
          height: 1080,
          fpsNumerator: 30000,
          fpsDenominator: 1001,
          durationTicks: 10000000,
          pixelFormat: 'yuv420p',
        ),
      ],
      audioStreams: [
        const AudioStreamInfo(
          index: 1,
          codec: 'aac',
          sampleRate: 48000,
          channels: 2,
          durationTicks: 10000000,
        ),
      ],
    );
  }

  @override
  Future<String> computeBlake3(String filePath) async {
    _checkDisposedOrCrashed();
    hashCalls++;

    if (mockHashes.containsKey(filePath)) {
      return mockHashes[filePath]!;
    }

    final file = File(filePath);
    if (file.existsSync()) {
      return Blake3.hashFile(file);
    }

    // Deterministic fake hash based on path string
    return Blake3.hash(filePath.codeUnits);
  }

  @override
  Future<String> generateThumbnail(
    String filePath, {
    required int atTick,
    required String destinationPath,
    int? width,
    int? height,
  }) async {
    _checkDisposedOrCrashed();
    thumbnailCalls++;

    final file = File(filePath);
    if (!file.existsSync() && !mockProbes.containsKey(filePath)) {
      throw MediaException.assetMissing(filePath);
    }

    final destFile = File(destinationPath);
    destFile.parent.createSync(recursive: true);
    // Write synthetic minimal JPEG signature bytes
    destFile.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0xFF, 0xD9]);
    return destinationPath;
  }

  @override
  Future<String> generateProxy(
    String filePath, {
    required String destinationPath,
    int? targetHeight,
  }) async {
    _checkDisposedOrCrashed();
    proxyCalls++;

    final file = File(filePath);
    if (!file.existsSync() && !mockProbes.containsKey(filePath)) {
      throw MediaException.assetMissing(filePath);
    }

    // Atomic write simulation: write to .part, then rename
    final partPath = '$destinationPath.part';
    final partFile = File(partPath);
    partFile.parent.createSync(recursive: true);
    partFile.writeAsStringSync('SIMULATED_PROXY_VIDEO_DATA');
    partFile.renameSync(destinationPath);

    return destinationPath;
  }

  @override
  Future<WaveformData> generateWaveform(
    String filePath, {
    int samplesPerSecond = 100,
  }) async {
    _checkDisposedOrCrashed();
    waveformCalls++;

    final file = File(filePath);
    if (!file.existsSync() && !mockProbes.containsKey(filePath)) {
      throw MediaException.assetMissing(filePath);
    }

    // Generate 50 synthetic peaks
    final sampleCount = math.max(10, samplesPerSecond * 2);
    final peaks = List<double>.generate(
      sampleCount,
      (i) => (math.sin(i * 0.1).abs() * 0.8 + 0.1).clamp(0.0, 1.0),
    );

    return WaveformData(
      samplesPerSecond: samplesPerSecond,
      durationTicks: 2000000,
      peaks: peaks,
    );
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
  }
}
