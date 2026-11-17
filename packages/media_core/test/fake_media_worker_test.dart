import 'dart:io';

import 'package:media_core/media_core.dart';
import 'package:test/test.dart';

void main() {
  group('FakeMediaWorker Tests', () {
    late FakeMediaWorker worker;
    late Directory tempDir;

    setUp(() {
      worker = FakeMediaWorker();
      tempDir = Directory.systemTemp.createTempSync('fake_worker_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
      worker.dispose();
    });

    test('probes file metadata with default mock data', () async {
      final fakeFile = File('${tempDir.path}/clip.mp4')..writeAsStringSync('dummy');
      final probe = await worker.probe(fakeFile.path);

      expect(probe.hasVideo, isTrue);
      expect(probe.hasAudio, isTrue);
      expect(probe.durationTicks, equals(10000000));
      expect(probe.primaryVideoStream?.width, equals(1920));
      expect(probe.primaryVideoStream?.height, equals(1080));
      expect(probe.primaryVideoStream?.fpsNumerator, equals(30000));
      expect(probe.primaryVideoStream?.fpsDenominator, equals(1001));
      expect(worker.probeCalls, equals(1));
    });

    test('computes deterministic BLAKE3 hash', () async {
      final fakeFile = File('${tempDir.path}/clip.mp4')..writeAsStringSync('hello');
      final hash = await worker.computeBlake3(fakeFile.path);

      expect(hash, equals('ea8f163db38682925e4491c5e58d4bb3506ef8c14eb78a86e908c5624a67200f'));
      expect(worker.hashCalls, equals(1));
    });

    test('generates dummy thumbnail and atomic proxy', () async {
      final fakeFile = File('${tempDir.path}/clip.mp4')..writeAsStringSync('dummy');
      final thumbPath = '${tempDir.path}/thumb.jpg';
      final proxyPath = '${tempDir.path}/proxy.mp4';

      final resThumb = await worker.generateThumbnail(
        fakeFile.path,
        atTick: 1000000,
        destinationPath: thumbPath,
      );
      final resProxy = await worker.generateProxy(
        fakeFile.path,
        destinationPath: proxyPath,
      );

      expect(resThumb, equals(thumbPath));
      expect(File(thumbPath).existsSync(), isTrue);
      expect(File(thumbPath).lengthSync(), greaterThan(0));

      expect(resProxy, equals(proxyPath));
      expect(File(proxyPath).existsSync(), isTrue);
      expect(File(proxyPath).readAsStringSync(), equals('SIMULATED_PROXY_VIDEO_DATA'));
    });

    test('generates normalized waveform samples', () async {
      final fakeFile = File('${tempDir.path}/clip.mp4')..writeAsStringSync('dummy');
      final waveform = await worker.generateWaveform(fakeFile.path, samplesPerSecond: 50);

      expect(waveform.samplesPerSecond, equals(50));
      expect(waveform.peaks.length, greaterThanOrEqualTo(10));
      for (final peak in waveform.peaks) {
        expect(peak, inInclusiveRange(0.0, 1.0));
      }
    });

    test('enforces exact Spec §14.3 error taxonomy via fault injection', () async {
      final missingPath = '${tempDir.path}/missing.mp4';

      // 1. Missing file -> MEDIA_ASSET_MISSING (not retryable)
      expect(
        () => worker.probe(missingPath),
        throwsA(
          isA<MediaException>()
              .having((e) => e.code, 'code', 'MEDIA_ASSET_MISSING')
              .having((e) => e.category, 'category', 'media')
              .having((e) => e.retryable, 'retryable', isFalse),
        ),
      );

      final dummyFile = File('${tempDir.path}/sample.mp4')..writeAsStringSync('sample');

      // 2. Unsupported format -> MEDIA_UNSUPPORTED (not retryable)
      worker.shouldReportUnsupported = true;
      expect(
        () => worker.probe(dummyFile.path),
        throwsA(
          isA<MediaException>()
              .having((e) => e.code, 'code', 'MEDIA_UNSUPPORTED')
              .having((e) => e.category, 'category', 'media')
              .having((e) => e.retryable, 'retryable', isFalse),
        ),
      );
      worker.shouldReportUnsupported = false;

      // 3. Corrupt file -> MEDIA_CORRUPT (not retryable)
      worker.shouldReportCorrupt = true;
      expect(
        () => worker.probe(dummyFile.path),
        throwsA(
          isA<MediaException>()
              .having((e) => e.code, 'code', 'MEDIA_CORRUPT')
              .having((e) => e.category, 'category', 'media')
              .having((e) => e.retryable, 'retryable', isFalse),
        ),
      );
      worker.shouldReportCorrupt = false;

      // 4. Engine crash -> MEDIA_ENGINE_CRASH (retryable: true)
      worker.shouldCrashEngine = true;
      expect(
        () => worker.probe(dummyFile.path),
        throwsA(
          isA<MediaException>()
              .having((e) => e.code, 'code', 'MEDIA_ENGINE_CRASH')
              .having((e) => e.category, 'category', 'media')
              .having((e) => e.retryable, 'retryable', isTrue),
        ),
      );
      worker.shouldCrashEngine = false;

      // 5. Worker unavailable / offline -> MEDIA_WORKER_UNAVAILABLE (retryable: true)
      worker.shouldBeUnavailable = true;
      expect(
        () => worker.probe(dummyFile.path),
        throwsA(
          isA<MediaException>()
              .having((e) => e.code, 'code', 'MEDIA_WORKER_UNAVAILABLE')
              .having((e) => e.category, 'category', 'media')
              .having((e) => e.retryable, 'retryable', isTrue),
        ),
      );
    });
  });
}
