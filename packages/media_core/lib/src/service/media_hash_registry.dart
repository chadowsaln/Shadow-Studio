import '../model/imported_media_asset.dart';

/// In-memory and persistent registry for BLAKE3 media deduplication.
///
/// Ensures files with identical content are deduplicated across the project,
/// preventing redundant transcoding, proxy generation, and waveform computation.
class MediaHashRegistry {
  final Map<String, ImportedMediaAsset> _byHash = {};
  final Map<String, String> _hashById = {};

  /// Current count of unique registered media hashes.
  int get count => _byHash.length;

  /// Returns true if [hash] is already registered in the media library.
  bool containsHash(String hash) => _byHash.containsKey(hash);

  /// Looks up an imported media asset by its BLAKE3 hash.
  ImportedMediaAsset? getByHash(String hash) => _byHash[hash];

  /// Looks up an imported media asset by its unique asset ID.
  ImportedMediaAsset? getById(String id) {
    final hash = _hashById[id];
    if (hash == null) return null;
    return _byHash[hash];
  }

  /// Registers an imported asset.
  void register(ImportedMediaAsset asset) {
    _byHash[asset.blake3Hash] = asset;
    _hashById[asset.id] = asset.blake3Hash;
  }

  /// Removes an asset from the registry by ID.
  bool unregister(String id) {
    final hash = _hashById.remove(id);
    if (hash != null) {
      _byHash.remove(hash);
      return true;
    }
    return false;
  }

  /// Clears all registered media hashes.
  void clear() {
    _byHash.clear;
    _hashById.clear();
  }

  /// Exports registry state to a JSON-encodable map.
  Map<String, Object?> toJson() => {
        'assets': _byHash.values.map((a) => a.toJson()).toList(),
      };

  /// Restores registry state from a JSON-encodable map.
  void loadFromJson(Map<String, Object?> json) {
    clear();
    final list = json['assets'] as List<dynamic>? ?? [];
    for (final item in list) {
      final asset = ImportedMediaAsset.fromJson(item as Map<String, Object?>);
      register(asset);
    }
  }
}
