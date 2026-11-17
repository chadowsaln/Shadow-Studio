import 'dart:io';

import 'package:path/path.dart' as p;

import '../error/media_error.dart';
import '../model/imported_media_asset.dart';
import '../model/media_kind.dart';
import '../model/waveform_data.dart';
import '../worker/media_worker.dart';
import 'media_hash_registry.dart';

/// High-level Media Library manager orchestrating media ingestion, probe inspection,
/// BLAKE3 deduplication, thumbnail capture, proxy generation, and waveform caching.
class MediaLibraryService {
  final MediaWorker worker;
  final Directory cacheDir;
  final MediaHashRegistry registry;

  MediaLibraryService({
    required this.worker,
    required this.cacheDir,
    MediaHashRegistry? registry,
  }) : registry = registry ?? MediaHashRegistry();

  Directory get thumbnailsDir => Directory(p.join(cacheDir.path, 'thumbnails'));
  Directory get proxiesDir => Directory(p.join(cacheDir.path, 'proxies'));
  Directory get waveformsDir => Directory(p.join(cacheDir.path, 'waveforms'));

  /// Ingests a media file from disk into the project's media library.
  ///
  /// Enforces non-destructive constraints (source files are strictly read-only).
  /// If the file's BLAKE3 hash has already been imported, returns the existing
  /// metadata with [isDeduplicated] set to true.
  Future<ImportedMediaAsset> importFile(
    String filePath, {
    String? customAssetId,
    bool generateProxy = false,
    bool generateWaveform = true,
    int? thumbnailTick,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw MediaException.assetMissing(filePath);
    }

    // 1. Compute BLAKE3 content hash for library deduplication
    final hash = await worker.computeBlake3(filePath);

    // 2. Check registry for existing duplicate asset
    final existing = registry.getByHash(hash);
    if (existing != null) {
      return existing.copyWith(isDeduplicated: true);
    }

    // 3. Probe file format and stream topology
    final probe = await worker.probe(filePath);

    // 4. Generate visual thumbnail if video or image
    String? thumbPath;
    if (probe.hasVideo || probe.inferredKind == MediaKind.image) {
      final dest = p.join(thumbnailsDir.path, '$hash.jpg');
      final atTick = thumbnailTick ??
          (probe.durationTicks > 1000000 ? 1000000 : 0);
      thumbPath = await worker.generateThumbnail(
        filePath,
        atTick: atTick,
        destinationPath: dest,
        width: 320,
      );
    }

    // 5. Generate proxy if requested and media has video
    String? proxyPath;
    if (generateProxy && probe.hasVideo) {
      final dest = p.join(proxiesDir.path, '$hash.mp4');
      proxyPath = await worker.generateProxy(
        filePath,
        destinationPath: dest,
        targetHeight: 720,
      );
    }

    // 6. Generate waveform if requested and media has audio
    WaveformData? waveform;
    if (generateWaveform && probe.hasAudio) {
      waveform = await worker.generateWaveform(
        filePath,
        samplesPerSecond: 100,
      );
    }

    // 7. Construct imported asset representation
    final absolutePath = file.absolute.path;
    final fileUri = 'file://$absolutePath';
    final assetId = customAssetId ?? 'asset_${hash.substring(0, 16)}';

    final asset = ImportedMediaAsset(
      id: assetId,
      sourcePath: absolutePath,
      sourceUri: fileUri,
      kind: probe.inferredKind,
      durationTicks: probe.durationTicks,
      blake3Hash: hash,
      probe: probe,
      thumbnailPath: thumbPath,
      proxyPath: proxyPath,
      waveformData: waveform,
      isDeduplicated: false,
    );

    // 8. Register in hash registry
    registry.register(asset);

    return asset;
  }

  /// Batch imports multiple media files concurrently or sequentially.
  Future<List<ImportedMediaAsset>> importFiles(
    List<String> filePaths, {
    bool generateProxy = false,
    bool generateWaveform = true,
  }) async {
    final results = <ImportedMediaAsset>[];
    for (final path in filePaths) {
      final asset = await importFile(
        path,
        generateProxy: generateProxy,
        generateWaveform: generateWaveform,
      );
      results.add(asset);
    }
    return results;
  }

  /// Clears on-disk cache directories for proxies and thumbnails.
  Future<void> clearCaches({bool thumbnails = true, bool proxies = true}) async {
    if (thumbnails && await thumbnailsDir.exists()) {
      await thumbnailsDir.delete(recursive: true);
    }
    if (proxies && await proxiesDir.exists()) {
      await proxiesDir.delete(recursive: true);
    }
  }
}
