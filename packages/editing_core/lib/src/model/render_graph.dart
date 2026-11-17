import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'project_profile.dart';
import 'range_ticks.dart';
import 'render_graph_track.dart';
import 'timebase.dart';

/// Normative RenderGraph structure defined by rendergraph.schema.json (closed schema).
@immutable
class RenderGraph {
  final String graphSchema; // const 'shadow.rendergraph/1'
  final String sequenceId;
  final int projectRevision;
  final Timebase timebase;
  final ProjectProfile profile;
  final RangeTicks range;
  final String backgroundRgba;
  final List<RenderGraphTrack> tracks;

  const RenderGraph({
    this.graphSchema = 'shadow.rendergraph/1',
    required this.sequenceId,
    required this.projectRevision,
    required this.timebase,
    required this.profile,
    required this.range,
    this.backgroundRgba = '#000000FF',
    required this.tracks,
  });

  Map<String, Object?> toJson() => {
        'graph_schema': graphSchema,
        'sequence_id': sequenceId,
        'project_revision': projectRevision,
        'timebase': timebase.toJson(),
        'profile': profile.toJson(),
        'range': range.toJson(),
        'background_rgba': backgroundRgba,
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };

  factory RenderGraph.fromJson(Map<String, Object?> json) {
    final rawTracks = (json['tracks'] as List<dynamic>?) ?? const [];
    return RenderGraph(
      graphSchema: (json['graph_schema'] as String?) ?? 'shadow.rendergraph/1',
      sequenceId: json['sequence_id'] as String,
      projectRevision: json['project_revision'] as int,
      timebase: Timebase.fromJson(
        (json['timebase'] as Map).cast<String, Object?>(),
      ),
      profile: ProjectProfile.fromJson(
        (json['profile'] as Map).cast<String, Object?>(),
      ),
      range: RangeTicks.fromJson(
        (json['range'] as Map).cast<String, Object?>(),
      ),
      backgroundRgba: (json['background_rgba'] as String?) ?? '#000000FF',
      tracks: rawTracks
          .map((t) => RenderGraphTrack.fromJson((t as Map).cast<String, Object?>()))
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RenderGraph &&
          runtimeType == other.runtimeType &&
          graphSchema == other.graphSchema &&
          sequenceId == other.sequenceId &&
          projectRevision == other.projectRevision &&
          timebase == other.timebase &&
          profile == other.profile &&
          range == other.range &&
          backgroundRgba == other.backgroundRgba &&
          const ListEquality<RenderGraphTrack>().equals(tracks, other.tracks);

  @override
  int get hashCode => Object.hash(
        graphSchema,
        sequenceId,
        projectRevision,
        timebase,
        profile,
        range,
        backgroundRgba,
        const ListEquality<RenderGraphTrack>().hash(tracks),
      );
}
