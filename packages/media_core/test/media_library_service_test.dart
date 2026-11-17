import 'dart:io';

import 'package:media_core/media_core.dart';
import 'package:test/test.dart';

void main() {
  group('MediaLibraryService Ingestion and Deduplication Tests', () {
    late FakeMediaWorker worker;
    late Directory cacheDir;
    late Directory mediaDir;
    late MediaLibraryService service;

    setUp(() {
      worker = FakeMediaWorker();
      cacheDir = Directory.systemTemp.createTempSync('media_cache_');
      mediaDir = Directory.systemTemp.createTempSync('media_source_');
      service = MediaLibraryService(worker: worker, cacheDir: cacheDir);
    });

    tearDown(() {
      cacheDir.deleteSync(recursive: true);
      mediaDir.deleteSync(recursive: true);
      worker.dispose();
    });

    test('ingests media file, creates cached artifacts and registers in registry', () async {
      final sample = File('${mediaDir.path}/video1.mp4')..writeAsStringSync('clip_bytes_1');

      final asset = await service.importFile(
        sample.path,
        generateProxy: true,
        generateWaveform: true,
      );

      expect(asset.id, startsWith('asset_'));
      expect(asset.kind, equals(MediaKind.video));
      expect(asset.durationTicks, equals(10000000));
      expect(asset.isDeduplicated, isFalse);
      expect(asset.thumbnailPath, isNotNull);
      expect(File(asset.thumbnailPath!).existsSync(), isTrue);
      expect(asset.proxyPath, isNotNull);
      expect(File(asset.proxyPath!).existsSync(), isTrue);
      expect(asset.waveformData, isNotNull);
      expect(asset.waveformData!.peaks.isNotEmpty, isTrue);

      expect(service.registry.count, equals(1));
      expect(service.registry.containsHash(asset.blake3Hash), isTrue);
      expect(worker.thumbnailCalls, equals(1));
      expect(worker.proxyCalls, equals(1));
      expect(worker.waveformCalls, equals(1));
    });

    test('deduplicates identical file content without re-generating artifacts', () async {
      final fileA = File('${mediaDir.path}/file_a.mp4')..writeAsStringSync('identical_content');
      final fileB = File('${mediaDir.path}/file_b.mp4')..writeAsStringSync('identical_content');

      // First import
      final asset1 = await service.importFile(
        fileA.path,
        generateProxy: true,
        generateWaveform: true,
      );
      expect(asset1.isDeduplicated, isFalse);
      expect(worker.thumbnailCalls, equals(1));
      expect(worker.proxyCalls, equals(1));
      expect(worker.waveformCalls, equals(1));

      // Second import of file with identical BLAKE3 hash
      final asset2 = await service.importFile(
        fileB.path,
        generateProxy: true,
        generateWaveform: true,
      );

      expect(asset2.isDeduplicated, isTrue);
      expect(asset2.blake3Hash, equals(asset1.blake3Hash));
      expect(asset2.thumbnailPath, equals(asset1.thumbnailPath));
      expect(asset2.proxyPath, equals(asset1.proxyPath));

      // Worker should NOT have been invoked again for thumbnail, proxy, or waveform
      expect(worker.thumbnailCalls, equals(1));
      expect(worker.proxyCalls, equals(1));
      expect(worker.waveformCalls, equals(1));
      expect(service.registry.count, equals(1));
    });

    test('rejects non-existent file with MEDIA_ASSET_MISSING', () async {
      expect(
        () => service.importFile('${mediaDir.path}/nonexistent.mov'),
        throwsA(
          isA<MediaException>()
              .having((e) => e.code, 'code', 'MEDIA_ASSET_MISSING')
              .having((e) => e.category, 'category', 'media')
              .having((e) => e.retryable, 'retryable', isFalse),
        ),
      );
    });

    test('batch import ingests multiple files sequentially', () async {
      final f1 = File('${mediaDir.path}/a.mp4')..writeAsStringSync('data1');
      final f2 = File('${mediaDir.path}/b.mp4')..writeAsStringSync('data2');
      final f3 = File('${mediaDir.path}/c.mp4')..writeAsStringSync('data3');

      final assets = await service.importFiles([f1.path, f2.path, f3.path]);
      expect(assets.length, equals(3));
      expect(service.registry.count, equals(3));
    });

    test('clearing caches deletes proxy and thumbnail directories', () async {
      final f = File('${mediaDir.path}/test.mp4')..writeAsStringSync('test');
      final asset = await service.importFile(f.path, generateProxy: true);

      expect(File(asset.thumbnailPath!).existsSync(), isTrue);
      expect(File(asset.proxyPath!).existsSync(), isTrue);

      await service.clearCaches();
      expect(File(asset.thumbnailPath!).existsSync(), isFalse);
      expect(File(asset.proxyPath!).existsSync(), isFalse);
    });
  });
}
