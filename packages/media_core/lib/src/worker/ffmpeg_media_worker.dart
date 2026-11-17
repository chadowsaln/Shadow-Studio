import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../error/media_error.dart';
import '../hash/blake3.dart';
import '../model/media_probe_result.dart';
import '../model/media_stream_info.dart';
import '../model/waveform_data.dart';
import 'media_worker.dart';

/// Interim FFmpeg/FFprobe CLI implementation of [MediaWorker].
///
/// Wraps system `ffprobe` and `ffmpeg` binaries to provide media inspection,
/// thumbnail rendering, atomic proxy encoding, and waveform generation.
class FfmpegMediaWorker implements MediaWorker {
  final String ffmpegBinary;
  final String ffprobeBinary;
  bool _isDisposed = false;

  FfmpegMediaWorker({
    this.ffmpegBinary = 'ffmpeg',
    this.ffprobeBinary = 'ffprobe',
  });

  void _checkDisposed() {
    if (_isDisposed) {
      throw MediaException.workerUnavailable('FfmpegMediaWorker has been disposed');
    }
  }

  /// Verifies that both ffmpeg and ffprobe binaries are reachable and executable.
  Future<void> ensureAvailable() async {
    _checkDisposed();
    try {
      final probeRes = await Process.run(ffprobeBinary, ['-version']);
      if (probeRes.exitCode != 0) {
        throw MediaException.workerUnavailable('ffprobe check failed with code ${probeRes.exitCode}');
      }
      final ffmpegRes = await Process.run(ffmpegBinary, ['-version']);
      if (ffmpegRes.exitCode != 0) {
        throw MediaException.workerUnavailable('ffmpeg check failed with code ${ffmpegRes.exitCode}');
      }
    } on ProcessException catch (e) {
      throw MediaException.workerUnavailable('FFmpeg binaries missing or unexecutable: ${e.message}');
    }
  }

  @override
  Future<MediaProbeResult> probe(String filePath) async {
    _checkDisposed();
    final file = File(filePath);
    if (!await file.exists()) {
      throw MediaException.assetMissing(filePath);
    }

    final ProcessResult result;
    try {
      result = await Process.run(
        ffprobeBinary,
        [
          '-v',
          'error',
          '-print_format',
          'json',
          '-show_format',
          '-show_streams',
          filePath,
        ],
      );
    } on ProcessException catch (e) {
      throw MediaException.workerUnavailable('Failed to invoke ffprobe: ${e.message}');
    }

    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      if (stderr.contains('Invalid data found') || stderr.contains('corrupt')) {
        throw MediaException.corrupt(stderr, path: filePath);
      }
      throw MediaException.unsupported(
        stderr.isEmpty ? 'ffprobe exited with code ${result.exitCode}' : stderr,
        path: filePath,
      );
    }

    final Map<String, dynamic> parsed;
    try {
      parsed = json.decode(result.stdout.toString()) as Map<String, dynamic>;
    } catch (e) {
      throw MediaException.corrupt('Invalid JSON returned by ffprobe: $e', path: filePath);
    }

    final format = parsed['format'] as Map<String, dynamic>? ?? {};
    final streams = (parsed['streams'] as List<dynamic>? ?? []);

    final videoStreams = <VideoStreamInfo>[];
    final audioStreams = <AudioStreamInfo>[];

    for (final s in streams) {
      final streamMap = s as Map<String, dynamic>;
      final codecType = streamMap['codec_type'] as String?;
      final index = (streamMap['index'] as int?) ?? 0;
      final codecName = (streamMap['codec_name'] as String?) ?? 'unknown';

      // Stream duration calculation
      int streamTicks = 0;
      if (streamMap.containsKey('duration_ts') && streamMap.containsKey('time_base')) {
        final durationTs = int.tryParse(streamMap['duration_ts'].toString());
        final timeBaseStr = streamMap['time_base'].toString();
        final parts = timeBaseStr.split('/');
        if (durationTs != null && parts.length == 2) {
          final num = int.tryParse(parts[0]);
          final den = int.tryParse(parts[1]);
          if (num != null && den != null && den > 0) {
            // durationTs * num / den * 1,000,000
            streamTicks = (durationTs * num * 1000000) ~/ den;
          }
        }
      }
      if (streamTicks <= 0 && streamMap.containsKey('duration')) {
        final durSec = double.tryParse(streamMap['duration'].toString());
        if (durSec != null) {
          streamTicks = (durSec * 1000000).round();
        }
      }

      if (codecType == 'video') {
        final width = (streamMap['width'] as int?) ?? 0;
        final height = (streamMap['height'] as int?) ?? 0;
        int fpsNum = 30;
        int fpsDen = 1;

        final rFrameRate = streamMap['r_frame_rate']?.toString();
        final avgFrameRate = streamMap['avg_frame_rate']?.toString();
        final chosenRate = (avgFrameRate != null && avgFrameRate != '0/0')
            ? avgFrameRate
            : (rFrameRate ?? '30/1');

        final rateParts = chosenRate.split('/');
        if (rateParts.length == 2) {
          final n = int.tryParse(rateParts[0]);
          final d = int.tryParse(rateParts[1]);
          if (n != null && d != null && d > 0) {
            fpsNum = n;
            fpsDen = d;
          }
        }

        int rotation = 0;
        // Rotation can be in tags or side_data_list
        final tags = streamMap['tags'] as Map<String, dynamic>?;
        if (tags != null && tags.containsKey('rotate')) {
          rotation = int.tryParse(tags['rotate'].toString()) ?? 0;
        }
        final sideData = streamMap['side_data_list'] as List<dynamic>?;
        if (sideData != null) {
          for (final item in sideData) {
            if (item is Map<String, dynamic> && item.containsKey('rotation')) {
              rotation = (item['rotation'] as num?)?.toInt() ?? 0;
            }
          }
        }

        videoStreams.add(
          VideoStreamInfo(
            index: index,
            codec: codecName,
            width: width,
            height: height,
            fpsNumerator: fpsNum,
            fpsDenominator: fpsDen,
            durationTicks: streamTicks,
            rotation: (rotation % 360 + 360) % 360,
            pixelFormat: streamMap['pix_fmt'] as String?,
            bitRate: int.tryParse(streamMap['bit_rate']?.toString() ?? ''),
          ),
        );
      } else if (codecType == 'audio') {
        final sampleRate = int.tryParse(streamMap['sample_rate']?.toString() ?? '') ?? 48000;
        final channels = (streamMap['channels'] as int?) ?? 2;
        audioStreams.add(
          AudioStreamInfo(
            index: index,
            codec: codecName,
            sampleRate: sampleRate,
            channels: channels,
            durationTicks: streamTicks,
            channelLayout: streamMap['channel_layout'] as String?,
            bitRate: int.tryParse(streamMap['bit_rate']?.toString() ?? ''),
          ),
        );
      }
    }

    // Format level duration fallback
    int formatTicks = 0;
    if (format.containsKey('duration')) {
      final durSec = double.tryParse(format['duration'].toString());
      if (durSec != null) {
        formatTicks = (durSec * 1000000).round();
      }
    }

    int totalDurationTicks = formatTicks;
    if (totalDurationTicks <= 0) {
      for (final v in videoStreams) {
        if (v.durationTicks > totalDurationTicks) totalDurationTicks = v.durationTicks;
      }
      for (final a in audioStreams) {
        if (a.durationTicks > totalDurationTicks) totalDurationTicks = a.durationTicks;
      }
    }

    final container = (format['format_name'] as String?) ?? 'unknown';
    final fileSizeBytes = int.tryParse(format['size']?.toString() ?? '') ?? await file.length();
    final bitRate = int.tryParse(format['bit_rate']?.toString() ?? '');

    return MediaProbeResult(
      filePath: filePath,
      container: container,
      durationTicks: totalDurationTicks,
      fileSizeBytes: fileSizeBytes,
      bitRate: bitRate,
      videoStreams: videoStreams,
      audioStreams: audioStreams,
    );
  }

  @override
  Future<String> computeBlake3(String filePath) async {
    _checkDisposed();
    final file = File(filePath);
    if (!await file.exists()) {
      throw MediaException.assetMissing(filePath);
    }
    return Blake3.hashFile(file);
  }

  @override
  Future<String> generateThumbnail(
    String filePath, {
    required int atTick,
    required String destinationPath,
    int? width,
    int? height,
  }) async {
    _checkDisposed();
    final file = File(filePath);
    if (!await file.exists()) {
      throw MediaException.assetMissing(filePath);
    }

    final destFile = File(destinationPath);
    await destFile.parent.create(recursive: true);

    final seconds = atTick / 1000000.0;
    final w = width ?? 320;
    final h = height ?? -1;

    final args = [
      '-hide_banner',
      '-loglevel',
      'error',
      '-ss',
      seconds.toStringAsFixed(3),
      '-i',
      filePath,
      '-update',
      '1',
      '-frames:v',
      '1',
      '-vf',
      'scale=$w:$h',
      '-y',
      destinationPath,
    ];

    final ProcessResult result;
    try {
      result = await Process.run(ffmpegBinary, args);
    } on ProcessException catch (e) {
      throw MediaException.workerUnavailable('Failed to invoke ffmpeg thumbnailer: ${e.message}');
    }

    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      throw MediaException.corrupt('Failed to generate thumbnail: $stderr', path: filePath);
    }

    return destinationPath;
  }

  @override
  Future<String> generateProxy(
    String filePath, {
    required String destinationPath,
    int? targetHeight,
  }) async {
    _checkDisposed();
    final file = File(filePath);
    if (!await file.exists()) {
      throw MediaException.assetMissing(filePath);
    }

    final destFile = File(destinationPath);
    await destFile.parent.create(recursive: true);

    // Atomic write semantics (Spec §11 & V2-D9): write to .part first
    final partPath = '$destinationPath.part';
    final partFile = File(partPath);
    if (await partFile.exists()) {
      await partFile.delete();
    }

    final th = targetHeight ?? 720;
    final args = [
      '-hide_banner',
      '-loglevel',
      'error',
      '-i',
      filePath,
      '-vf',
      'scale=-2:$th',
      '-c:v',
      'libx264',
      '-preset',
      'ultrafast',
      '-crf',
      '28',
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-f',
      'mp4',
      '-y',
      partPath,
    ];

    final ProcessResult result;
    try {
      result = await Process.run(ffmpegBinary, args);
    } on ProcessException catch (e) {
      throw MediaException.workerUnavailable('Failed to invoke ffmpeg proxy encoder: ${e.message}');
    }

    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
      throw MediaException.corrupt('Failed to generate proxy: $stderr', path: filePath);
    }

    // Flush and atomic rename
    await partFile.rename(destinationPath);
    return destinationPath;
  }

  @override
  Future<WaveformData> generateWaveform(
    String filePath, {
    int samplesPerSecond = 100,
  }) async {
    _checkDisposed();
    final file = File(filePath);
    if (!await file.exists()) {
      throw MediaException.assetMissing(filePath);
    }

    // Extract mono 16-bit PCM at 8000 Hz through stdout pipe
    const sampleRate = 8000;
    final args = [
      '-hide_banner',
      '-loglevel',
      'error',
      '-i',
      filePath,
      '-ac',
      '1',
      '-ar',
      '$sampleRate',
      '-f',
      's16le',
      '-',
    ];

    final Process process;
    try {
      process = await Process.start(ffmpegBinary, args);
    } on ProcessException catch (e) {
      throw MediaException.workerUnavailable('Failed to start ffmpeg waveform extraction: ${e.message}');
    }

    final chunks = <List<int>>[];
    final stderrChunks = <List<int>>[];

    final stdoutFuture = process.stdout.forEach(chunks.add);
    final stderrFuture = process.stderr.forEach(stderrChunks.add);

    final exitCode = await process.exitCode;
    await Future.wait([stdoutFuture, stderrFuture]);

    if (exitCode != 0) {
      final stderr = utf8.decode(stderrChunks.expand((c) => c).toList(), allowMalformed: true);
      throw MediaException.corrupt('Waveform extraction failed: $stderr', path: filePath);
    }

    // Total bytes read
    final totalBytes = chunks.fold<int>(0, (sum, c) => sum + c.length);
    final allBytes = Uint8List(totalBytes);
    int offset = 0;
    for (final c in chunks) {
      allBytes.setRange(offset, offset + c.length, c);
      offset += c.length;
    }

    final totalSamples = totalBytes ~/ 2;
    if (totalSamples == 0) {
      return WaveformData(
        samplesPerSecond: samplesPerSecond,
        durationTicks: 0,
        peaks: const [],
      );
    }

    final byteData = ByteData.sublistView(allBytes);
    final samplesPerBucket = (sampleRate / samplesPerSecond).round().clamp(1, sampleRate);
    final bucketCount = (totalSamples + samplesPerBucket - 1) ~/ samplesPerBucket;

    final peaks = List<double>.filled(bucketCount, 0.0);
    final minPeaks = List<double>.filled(bucketCount, 0.0);
    final maxPeaks = List<double>.filled(bucketCount, 0.0);

    for (int b = 0; b < bucketCount; b++) {
      final start = b * samplesPerBucket;
      final end = (start + samplesPerBucket <= totalSamples) ? start + samplesPerBucket : totalSamples;
      int maxAmp = 0;
      int minSample = 0;
      int maxSample = 0;

      for (int i = start; i < end; i++) {
        final sample = byteData.getInt16(i * 2, Endian.little);
        if (sample.abs() > maxAmp) {
          maxAmp = sample.abs();
        }
        if (sample < minSample) {
          minSample = sample;
        }
        if (sample > maxSample) {
          maxSample = sample;
        }
      }

      peaks[b] = (maxAmp / 32768.0).clamp(0.0, 1.0);
      minPeaks[b] = (minSample / 32768.0).clamp(-1.0, 0.0);
      maxPeaks[b] = (maxSample / 32768.0).clamp(0.0, 1.0);
    }

    final durationTicks = ((totalSamples / sampleRate) * 1000000).round();

    return WaveformData(
      samplesPerSecond: samplesPerSecond,
      durationTicks: durationTicks,
      peaks: peaks,
      minPeaks: minPeaks,
      maxPeaks: maxPeaks,
    );
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
  }
}
