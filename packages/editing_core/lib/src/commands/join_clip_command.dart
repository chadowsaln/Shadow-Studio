import '../error/shadow_error.dart';
import '../model/clip.dart';
import '../model/project_document.dart';
import '../model/track.dart';
import 'edit_command.dart';
import 'split_clip_command.dart';

/// Pure command to join two adjacent clips on a track (inverse of split or manual merge).
class JoinClipCommand implements EditCommand {
  final String trackId;
  final String firstClipId;
  final String secondClipId;
  final Clip? originalClip;

  const JoinClipCommand({
    required this.trackId,
    required this.firstClipId,
    required this.secondClipId,
    this.originalClip,
  });

  @override
  String get name => 'clip.join';

  @override
  CommandResult execute(ProjectDocument document) {
    final trackIndex = document.tracks.indexWhere((t) => t.id == trackId);
    if (trackIndex == -1) {
      throw ShadowError.invalidOperation('Track "$trackId" not found');
    }

    final track = document.tracks[trackIndex];
    final firstIndex = track.clips.indexWhere((c) => c.id == firstClipId);
    if (firstIndex == -1) {
      throw ShadowError.invalidOperation(
        'First clip "$firstClipId" not found on track "$trackId"',
      );
    }

    final secondIndex = track.clips.indexWhere((c) => c.id == secondClipId);
    if (secondIndex == -1) {
      throw ShadowError.invalidOperation(
        'Second clip "$secondClipId" not found on track "$trackId"',
      );
    }

    final firstClip = track.clips[firstIndex];
    final secondClip = track.clips[secondIndex];

    if (firstClip.timelineEndTicks != secondClip.timelineStartTicks) {
      throw ShadowError.invalidOperation(
        'Cannot join non-adjacent clips: ${firstClip.id} ends at ${firstClip.timelineEndTicks}, ${secondClip.id} starts at ${secondClip.timelineStartTicks}',
      );
    }

    final joinedClip = originalClip ??
        firstClip.copyWith(
          durationTicks: firstClip.durationTicks + secondClip.durationTicks,
        );

    final updatedClips = List<Clip>.of(track.clips)
      ..removeWhere((c) => c.id == firstClipId || c.id == secondClipId)
      ..add(joinedClip);

    final updatedTracks = List<Track>.of(document.tracks);
    updatedTracks[trackIndex] = track.copyWith(clips: updatedClips);

    final newDoc = document.copyWith(tracks: updatedTracks);
    final inverse = SplitClipCommand(
      trackId: trackId,
      clipId: firstClipId,
      splitAtTick: secondClip.timelineStartTicks,
      newClipId: secondClipId,
    );

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JoinClipCommand &&
          runtimeType == other.runtimeType &&
          trackId == other.trackId &&
          firstClipId == other.firstClipId &&
          secondClipId == other.secondClipId;

  @override
  int get hashCode => Object.hash(trackId, firstClipId, secondClipId);

  @override
  String toString() =>
      'JoinClipCommand(trackId: $trackId, first: $firstClipId, second: $secondClipId)';
}
