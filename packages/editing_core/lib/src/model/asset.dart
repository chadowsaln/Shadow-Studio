import 'package:meta/meta.dart';

/// Asset kind supported by the editor.
enum AssetKind {
  video,
  audio,
  image;

  String get wireName => name;

  static AssetKind fromWireName(String value) {
    return AssetKind.values.firstWhere(
      (k) => k.wireName == value,
      orElse: () => throw ArgumentError('Unknown asset kind: $value'),
    );
  }
}

/// Project media asset representation.
///
/// Immutable metadata descriptor for source media files.
/// Original media files are never modified (non-destructive constraint).
@immutable
class Asset {
  final String id;
  final AssetKind kind;
  final String uri;
  final int durationTicks;
  final String? hash; // BLAKE3 hex hash

  const Asset({
    required this.id,
    required this.kind,
    required this.uri,
    required this.durationTicks,
    this.hash,
  })  : assert(durationTicks >= 0, 'durationTicks must be non-negative');

  Asset copyWith({
    String? id,
    AssetKind? kind,
    String? uri,
    int? durationTicks,
    String? hash,
  }) {
    return Asset(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      uri: uri ?? this.uri,
      durationTicks: durationTicks ?? this.durationTicks,
      hash: hash ?? this.hash,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.wireName,
        'uri': uri,
        'duration_ticks': durationTicks,
        if (hash != null) 'hash': hash,
      };

  factory Asset.fromJson(Map<String, Object?> json) {
    return Asset(
      id: json['id'] as String,
      kind: AssetKind.fromWireName(json['kind'] as String),
      uri: json['uri'] as String,
      durationTicks: json['duration_ticks'] as int,
      hash: json['hash'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Asset &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          kind == other.kind &&
          uri == other.uri &&
          durationTicks == other.durationTicks &&
          hash == other.hash;

  @override
  int get hashCode => Object.hash(id, kind, uri, durationTicks, hash);

  @override
  String toString() => 'Asset(id: $id, kind: ${kind.name}, uri: $uri, duration: $durationTicks)';
}
