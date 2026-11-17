import 'dart:io';

import 'package:media_core/media_core.dart';
import 'package:test/test.dart';

void main() {
  group('FfmpegMediaWorker CLI Integration Tests', () {
    late FfmpegMediaWorker worker;
    late Directory tempDir;

    String findFixture(String name) {
      final candidates = [
        'tools/media-spike/out/fixtures/$name',
        '../../tools/media-spike/out/fixtures/$name',
      ];
      for (final c in candidates) {
        if (File(c).existsSync()) return File(c).absolute.path;
      }
      return candidates.first;
    }

    late final introPath = findFixture('intro-4k.mp4');
    late final audioPath = findFixture('vo-take3.wav');

    setUp(() {
      worker = FfmpegMediaWorker();
      tempDir = Directory.systemTemp.createTempSync('ffmpeg_worker_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
      worker.dispose();
    });

    test('verifies ffmpeg and ffprobe CLI binaries are available', () async {
      await worker.ensureAvailable();
    });

    test('probes 4K video stream details and integer tick duration', () async {
      expect(File(introPath).existsSync(), isTrue, reason: 'intro-4k fixture must exist');

      final probe = await worker.probe(introPath);

      expect(probe.container, contains('mp4'));
      expect(probe.hasVideo, isTrue);
      expect(probe.durationTicks, equals(6006000)); // Exactly 6.006s in integer ticks
      expect(probe.fileSizeBytes, greaterThan(0));

      final video = probe.primaryVideoStream!;
      expect(video.codec, equals('h264'));
      expect(video.width, equals(3840));
      expect(video.height, equals(2160));
      expect(video.fpsNumerator, equals(30000));
      expect(video.fpsDenominator, equals(1001));
      expect(video.rotation, equals(0));
    });

    test('probes WAV audio stream details and integer tick duration', () async {
      expect(File(audioPath).existsSync(), isTrue, reason: 'vo-take3 fixture must exist');

      final probe = await worker.probe(audioPath);

      expect(probe.container, equals('wav'));
      expect(probe.hasAudio, isTrue);
      expect(probe.durationTicks, equals(10000000)); // Exactly 10.0s in integer ticks

      final audio = probe.primaryAudioStream!;
      expect(audio.codec, equals('pcm_s16le'));
      expect(audio.sampleRate, equals(48000));
      expect(audio.channels, equals(2));
    });

    test('generates visual JPEG thumbnail via ffmpeg', () async {
      final thumbDest = '${tempDir.path}/thumb.jpg';

      final result = await worker.generateThumbnail(
        introPath,
        atTick: 1000000, // 1.0 second
        destinationPath: thumbDest,
        width: 320,
      );

      expect(result, equals(thumbDest));
      final thumbFile = File(thumbDest);
      expect(thumbFile.existsSync(), isTrue);
      expect(thumbFile.lengthSync(), greaterThan(100));
    });

    test('generates 720p proxy MP4 with atomic .part rename', () async {
      final proxyDest = '${tempDir.path}/proxy_720.mp4';

      final result = await worker.generateProxy(
        introPath,
        destinationPath: proxyDest,
        targetHeight: 720,
      );

      expect(result, equals(proxyDest));
      final proxyFile = File(proxyDest);
      expect(proxyFile.existsSync(), isTrue);
      expect(proxyFile.lengthSync(), greaterThan(1000));
      // Verify .part temporary file does not linger
      expect(File('$proxyDest.part').existsSync(), isFalse);

      // Verify generated proxy can be probed
      final proxyProbe = await worker.probe(proxyDest);
      expect(proxyProbe.hasVideo, isTrue);
      expect(proxyProbe.primaryVideoStream?.height, equals(720));
      expect(proxyProbe.primaryVideoStream?.width, equals(1280));
    });

    test('extracts audio waveform peaks from WAV fixture in milliseconds', () async {
      final waveform = await worker.generateWaveform(audioPath, samplesPerSecond: 100);

      expect(waveform.samplesPerSecond, equals(100));
      expect(waveform.peaks.length, greaterThan(500)); // ~1000 samples for 10s audio
      for (final peak in waveform.peaks) {
        expect(peak, inInclusiveRange(0.0, 1.0));
      }
      expect(waveform.minPeaks, isNotNull);
      expect(waveform.maxPeaks, isNotNull);
    });

    test('handles missing file with MEDIA_ASSET_MISSING', () async {
      expect(
        () => worker.probe('${tempDir.path}/nonexistent.mp4'),
        throwsA(
          isA<MediaException>()
              .having((e) => e.code, 'code', 'MEDIA_ASSET_MISSING')
              .having((e) => e.retryable, 'retryable', isFalse),
        ),
      );
    });

    test('handles corrupt media file with MEDIA_CORRUPT or MEDIA_UNSUPPORTED', () async {
      final corruptFile = File('${tempDir.path}/corrupt.mp4')
        ..writeAsBytesSync([0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE, 0xFD]);

      expect(
        () => worker.probe(corruptFile.path),
        throwsA(
          isA<MediaException>().having(
            (e) => e.code == 'MEDIA_CORRUPT' || e.code == 'MEDIA_UNSUPPORTED',
            'code is corrupt or unsupported',
            isTrue,
          ),
        ),
      );
    });
  });
}
