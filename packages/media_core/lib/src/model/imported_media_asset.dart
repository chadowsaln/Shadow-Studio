import 'package:meta/meta.dart';

import 'media_kind.dart';
import 'media_probe_result.dart';
import 'waveform_data.dart';

/// Fully processed media asset ingested into the local media library.
///
/// Contains probed stream topology, BLAKE3 content hash for deduplication,
/// and references to generated proxy, thumbnail, and waveform caches.
@immutable
class ImportedMediaAsset {
  final String id;
  final String sourcePath;
  final String sourceUri;
  final MediaKind kind;
  final int durationTicks;
  final String blake3Hash;
  final MediaProbeResult probe;
  final String? thumbnailPath;
  final String? proxyPath;
  final WaveformData? waveformData;
  final bool isDeduplicated;

  const ImportedMediaAsset({
    required this.id,
    required this.sourcePath,
    required this.sourceUri,
    required this.kind,
    required this.durationTicks,
    required this.blake3Hash,
    required this.probe,
    this.thumbnailPath,
    this.proxyPath,
    this.waveformData,
    this.isDeduplicated = false,
  }) : assert(durationTicks >= 0, 'durationTicks must be non-negative');

  ImportedMediaAsset copyWith({
    String? id,
    String? sourcePath,
    String? sourceUri,
    MediaKind? kind,
    int? durationTicks,
    String? blake3Hash,
    MediaProbeResult? probe,
    String? thumbnailPath,
    String? proxyPath,
    WaveformData? waveformData,
    bool? isDeduplicated,
  }) {
    return ImportedMediaAsset(
      id: id ?? this.id,
      sourcePath: sourcePath ?? this.sourcePath,
      sourceUri: sourceUri ?? this.sourceUri,
      kind: kind ?? this.kind,
      durationTicks: durationTicks ?? this.durationTicks,
      blake3Hash: blake3Hash ?? this.blake3Hash,
      probe: probe ?? this.probe,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      proxyPath: proxyPath ?? this.proxyPath,
      waveformData: waveformData ?? this.waveformData,
      isDeduplicated: isDeduplicated ?? this.isDeduplicated,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'source_path': sourcePath,
        'source_uri': sourceUri,
        'kind': kind.wireName,
        'duration_ticks': durationTicks,
        'blake3_hash': blake3Hash,
        'probe': probe.toJson(),
        if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
        if (proxyPath != null) 'proxy_path': proxyPath,
        if (waveformData != null) 'waveform_data': waveformData!.toJson(),
        'is_deduplicated': isDeduplicated,
      };

  factory ImportedMediaAsset.fromJson(Map<String, Object?> json) {
    return ImportedMediaAsset(
      id: json['id'] as String,
      sourcePath: json['source_path'] as String,
      sourceUri: json['source_uri'] as String,
      kind: MediaKind.fromWireName(json['kind'] as String),
      durationTicks: json['duration_ticks'] as int,
      blake3Hash: json['blake3_hash'] as String,
      probe: MediaProbeResult.fromJson(json['probe'] as Map<String, Object?>),
      thumbnailPath: json['thumbnail_path'] as String?,
      proxyPath: json['proxy_path'] as String?,
      waveformData: json['waveform_data'] != null
          ? WaveformData.fromJson(json['waveform_data'] as Map<String, Object?>)
          : null,
      isDeduplicated: (json['is_deduplicated'] as bool?) ?? false,
    );
  }

  @override
  String toString() =>
      'ImportedMediaAsset($id, $kind, ${durationTicks}t, dedupe: $isDeduplicated)';
}
