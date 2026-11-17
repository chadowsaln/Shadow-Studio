import '../error/shadow_error.dart';
import '../model/project_document.dart';
import '../model/track.dart';
import 'add_track_command.dart';
import 'edit_command.dart';

/// Pure command to remove a track from the project document.
class RemoveTrackCommand implements EditCommand {
  final String trackId;
  final Track? removedTrack;
  final int? trackIndex;

  const RemoveTrackCommand({
    required this.trackId,
    this.removedTrack,
    this.trackIndex,
  });

  @override
  String get name => 'track.delete';

  @override
  CommandResult execute(ProjectDocument document) {
    final trackIndex = document.tracks.indexWhere((t) => t.id == trackId);
    if (trackIndex == -1) {
      throw ShadowError.invalidOperation('Track with ID "$trackId" not found');
    }

    final targetTrack = document.tracks[trackIndex];
    final newTracks = <Track>[];
    for (var i = 0; i < document.tracks.length; i++) {
      if (i == trackIndex) continue;
      final t = document.tracks[i];
      final newPos = i > trackIndex ? i - 1 : i;
      newTracks.add(t.copyWith(position: newPos));
    }

    final newDoc = document.copyWith(tracks: newTracks);
    final inverse = AddTrackCommand(targetTrack);

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoveTrackCommand &&
          runtimeType == other.runtimeType &&
          trackId == other.trackId;

  @override
  int get hashCode => trackId.hashCode;

  @override
  String toString() => 'RemoveTrackCommand(trackId: $trackId)';
}
