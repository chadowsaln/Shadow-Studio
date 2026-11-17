import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../uuid/uuid_v7.dart';
import 'asset.dart';
import 'clip.dart';
import 'project_profile.dart';
import 'timebase.dart';
import 'track.dart';

/// Immutable project document snapshot.
///
/// Contains all tracks, clips, assets, and project configurations.
/// Commands are pure functions: Document -> Document + inverse.
@immutable
class ProjectDocument {
  final String id;
  final String name;
  final String sequenceId;
  final ProjectProfile profile;
  final Timebase timebase;
  final String backgroundRgba;
  final List<Track> tracks;
  final Map<String, Asset> assets;

  ProjectDocument({
    String? id,
    required this.name,
    String? sequenceId,
    required this.profile,
    required this.timebase,
    this.backgroundRgba = '#000000FF',
    Iterable<Track> tracks = const [],
    Map<String, Asset> assets = const {},
  })  : id = id ?? UuidV7.generate(),
        sequenceId = sequenceId ?? UuidV7.generate(),
        tracks = List.unmodifiable(
          tracks.toList()..sort((a, b) => a.position.compareTo(b.position)),
        ),
        assets = Map.unmodifiable(assets);

  /// Creates a blank starter document with standard 1080p profile and 30fps timebase.
  factory ProjectDocument.createBlank({
    required String name,
    ProjectProfile? profile,
    Timebase? timebase,
  }) {
    return ProjectDocument(
      name: name,
      profile: profile ?? ProjectProfile.hd1080p(),
      timebase: timebase ?? Timebase.fps30(),
      tracks: const [],
      assets: const {},
    );
  }

  /// Calculates total project duration in ticks based on the furthest clip end.
  int get durationTicks {
    var maxTicks = 0;
    for (final track in tracks) {
      for (final clip in track.clips) {
        if (clip.timelineEndTicks > maxTicks) {
          maxTicks = clip.timelineEndTicks;
        }
      }
    }
    return maxTicks;
  }

  /// Finds a track by its ID.
  Track? findTrack(String trackId) {
    for (final track in tracks) {
      if (track.id == trackId) return track;
    }
    return null;
  }

  /// Finds a clip by its ID across all tracks.
  Clip? findClip(String clipId) {
    for (final track in tracks) {
      final clip = track.findClip(clipId);
      if (clip != null) return clip;
    }
    return null;
  }

  /// Finds a track and clip by clip ID.
  (Track, Clip)? findTrackAndClip(String clipId) {
    for (final track in tracks) {
      final clip = track.findClip(clipId);
      if (clip != null) return (track, clip);
    }
    return null;
  }

  /// Finds an asset by its ID.
  Asset? findAsset(String assetId) => assets[assetId];

  ProjectDocument copyWith({
    String? id,
    String? name,
    String? sequenceId,
    ProjectProfile? profile,
    Timebase? timebase,
    String? backgroundRgba,
    List<Track>? tracks,
    Map<String, Asset>? assets,
  }) {
    return ProjectDocument(
      id: id ?? this.id,
      name: name ?? this.name,
      sequenceId: sequenceId ?? this.sequenceId,
      profile: profile ?? this.profile,
      timebase: timebase ?? this.timebase,
      backgroundRgba: backgroundRgba ?? this.backgroundRgba,
      tracks: tracks ?? this.tracks,
      assets: assets ?? this.assets,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'sequence_id': sequenceId,
        'profile': profile.toJson(),
        'timebase': timebase.toJson(),
        'background_rgba': backgroundRgba,
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'assets': assets.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory ProjectDocument.fromJson(Map<String, Object?> json) {
    final rawTracks = (json['tracks'] as List<dynamic>?) ?? const [];
    final tracks = rawTracks
        .map((t) => Track.fromJson((t as Map).cast<String, Object?>()))
        .toList();

    final rawAssets = (json['assets'] as Map<String, dynamic>?) ?? const {};
    final assets = rawAssets.map(
      (k, v) => MapEntry(k, Asset.fromJson((v as Map).cast<String, Object?>())),
    );

    return ProjectDocument(
      id: json['id'] as String?,
      name: json['name'] as String,
      sequenceId: json['sequence_id'] as String?,
      profile: ProjectProfile.fromJson(
        (json['profile'] as Map).cast<String, Object?>(),
      ),
      timebase: Timebase.fromJson(
        (json['timebase'] as Map).cast<String, Object?>(),
      ),
      backgroundRgba: (json['background_rgba'] as String?) ?? '#000000FF',
      tracks: tracks,
      assets: assets,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectDocument &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          sequenceId == other.sequenceId &&
          profile == other.profile &&
          timebase == other.timebase &&
          backgroundRgba == other.backgroundRgba &&
          const ListEquality<Track>().equals(tracks, other.tracks) &&
          const MapEquality<String, Asset>().equals(assets, other.assets);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        sequenceId,
        profile,
        timebase,
        backgroundRgba,
        const ListEquality<Track>().hash(tracks),
        const MapEquality<String, Asset>().hash(assets),
      );

  @override
  String toString() =>
      'ProjectDocument(id: $id, name: "$name", tracks: ${tracks.length}, assets: ${assets.length})';
}
