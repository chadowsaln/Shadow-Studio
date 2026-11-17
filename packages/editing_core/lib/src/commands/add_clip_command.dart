import '../error/shadow_error.dart';
import '../model/clip.dart';
import '../model/project_document.dart';
import '../model/track.dart';
import 'edit_command.dart';
import 'remove_clip_command.dart';

/// Pure command to insert a clip onto a track.
class AddClipCommand implements EditCommand {
  final String trackId;
  final Clip clip;

  const AddClipCommand({
    required this.trackId,
    required this.clip,
  });

  @override
  String get name => 'clip.insert';

  @override
  CommandResult execute(ProjectDocument document) {
    final trackIndex = document.tracks.indexWhere((t) => t.id == trackId);
    if (trackIndex == -1) {
      throw ShadowError.invalidOperation('Track with ID "$trackId" not found');
    }

    final existingClip = document.findClip(clip.id);
    if (existingClip != null) {
      throw ShadowError.invalidOperation(
        'Clip with ID "${clip.id}" already exists in project document',
      );
    }

    final track = document.tracks[trackIndex];
    final updatedClips = [...track.clips, clip];
    final updatedTrack = track.copyWith(clips: updatedClips);

    final updatedTracks = List<Track>.of(document.tracks);
    updatedTracks[trackIndex] = updatedTrack;

    final newDoc = document.copyWith(tracks: updatedTracks);
    final inverse = RemoveClipCommand(
      trackId: trackId,
      clipId: clip.id,
      removedClip: clip,
    );

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AddClipCommand &&
          runtimeType == other.runtimeType &&
          trackId == other.trackId &&
          clip == other.clip;

  @override
  int get hashCode => Object.hash(trackId, clip);

  @override
  String toString() => 'AddClipCommand(trackId: $trackId, clipId: ${clip.id})';
}
