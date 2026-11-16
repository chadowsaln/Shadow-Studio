import 'package:meta/meta.dart';

import 'project_profile.dart';
import 'range_ticks.dart';
import 'timebase.dart';
import 'track.dart';

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
  final List<Track> tracks;

  const RenderGraph({
    this.graphSchema = 'shadow.rendergraph/1',
    required this.sequenceId,
    required this.projectRevision,
    required this.timebase,
    required this.profile,
    required this.range,
    this.backgroundRgba = '#000000ff',
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
}
