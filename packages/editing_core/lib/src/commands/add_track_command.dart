import '../error/shadow_error.dart';
import '../model/project_document.dart';
import '../model/track.dart';
import 'edit_command.dart';
import 'remove_track_command.dart';

/// Pure command to insert a track into the project document.
class AddTrackCommand implements EditCommand {
  final Track track;

  const AddTrackCommand(this.track);

  @override
  String get name => 'track.insert';

  @override
  CommandResult execute(ProjectDocument document) {
    if (document.findTrack(track.id) != null) {
      throw ShadowError.invalidOperation(
        'Track with ID "${track.id}" already exists in project',
      );
    }

    final targetPosition = track.position;
    if (targetPosition < 0 || targetPosition > document.tracks.length) {
      throw ShadowError.invalidOperation(
        'Cannot add track at position $targetPosition: expected 0..${document.tracks.length}',
      );
    }

    // Insert track and adjust subsequent track positions
    final newTracks = <Track>[];
    for (var i = 0; i < document.tracks.length; i++) {
      if (i == targetPosition) {
        newTracks.add(track);
      }
      final existing = document.tracks[i];
      final newPos = i >= targetPosition ? i + 1 : i;
      newTracks.add(existing.copyWith(position: newPos));
    }
    if (targetPosition == document.tracks.length) {
      newTracks.add(track.copyWith(position: targetPosition));
    }

    final newDoc = document.copyWith(tracks: newTracks);
    final inverse = RemoveTrackCommand(
      trackId: track.id,
      removedTrack: track,
      trackIndex: targetPosition,
    );

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AddTrackCommand &&
          runtimeType == other.runtimeType &&
          track == other.track;

  @override
  int get hashCode => track.hashCode;

  @override
  String toString() => 'AddTrackCommand(${track.name}, id: ${track.id}, pos: ${track.position})';
}
