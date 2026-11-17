import '../error/shadow_error.dart';
import '../model/clip.dart';
import '../model/project_document.dart';
import '../model/track.dart';
import 'add_clip_command.dart';
import 'edit_command.dart';

/// Pure command to remove a clip from a track.
class RemoveClipCommand implements EditCommand {
  final String trackId;
  final String clipId;
  final Clip? removedClip;

  const RemoveClipCommand({
    required this.trackId,
    required this.clipId,
    this.removedClip,
  });

  @override
  String get name => 'clip.delete';

  @override
  CommandResult execute(ProjectDocument document) {
    final trackIndex = document.tracks.indexWhere((t) => t.id == trackId);
    if (trackIndex == -1) {
      throw ShadowError.invalidOperation('Track with ID "$trackId" not found');
    }

    final track = document.tracks[trackIndex];
    final clipIndex = track.clips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) {
      throw ShadowError.invalidOperation(
        'Clip with ID "$clipId" not found on track "$trackId"',
      );
    }

    final targetClip = track.clips[clipIndex];
    final updatedClips = List<Clip>.of(track.clips)..removeAt(clipIndex);
    final updatedTrack = track.copyWith(clips: updatedClips);

    final updatedTracks = List<Track>.of(document.tracks);
    updatedTracks[trackIndex] = updatedTrack;

    final newDoc = document.copyWith(tracks: updatedTracks);
    final inverse = AddClipCommand(trackId: trackId, clip: targetClip);

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoveClipCommand &&
          runtimeType == other.runtimeType &&
          trackId == other.trackId &&
          clipId == other.clipId;

  @override
  int get hashCode => Object.hash(trackId, clipId);

  @override
  String toString() => 'RemoveClipCommand(trackId: $trackId, clipId: $clipId)';
}
