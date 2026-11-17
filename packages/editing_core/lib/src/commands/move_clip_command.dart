import '../error/shadow_error.dart';
import '../model/clip.dart';
import '../model/project_document.dart';
import '../model/track.dart';
import 'edit_command.dart';

/// Pure command to move a clip to a new timeline position and/or to another track.
class MoveClipCommand implements EditCommand {
  final String clipId;
  final String fromTrackId;
  final String toTrackId;
  final int newTimelineStartTicks;
  final int? previousTimelineStartTicks;

  const MoveClipCommand({
    required this.clipId,
    required this.fromTrackId,
    required this.toTrackId,
    required this.newTimelineStartTicks,
    this.previousTimelineStartTicks,
  });

  @override
  String get name => 'clip.move';

  @override
  CommandResult execute(ProjectDocument document) {
    if (newTimelineStartTicks < 0) {
      throw ShadowError.invalidOperation(
        'newTimelineStartTicks must be >= 0 (got $newTimelineStartTicks)',
      );
    }

    final fromTrackIndex = document.tracks.indexWhere((t) => t.id == fromTrackId);
    if (fromTrackIndex == -1) {
      throw ShadowError.invalidOperation('Source track "$fromTrackId" not found');
    }

    final toTrackIndex = document.tracks.indexWhere((t) => t.id == toTrackId);
    if (toTrackIndex == -1) {
      throw ShadowError.invalidOperation('Destination track "$toTrackId" not found');
    }

    final fromTrack = document.tracks[fromTrackIndex];
    final clipIndex = fromTrack.clips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) {
      throw ShadowError.invalidOperation(
        'Clip "$clipId" not found on source track "$fromTrackId"',
      );
    }

    final targetClip = fromTrack.clips[clipIndex];
    final originalStart = targetClip.timelineStartTicks;
    final movedClip = targetClip.copyWith(timelineStartTicks: newTimelineStartTicks);

    final updatedTracks = List<Track>.of(document.tracks);

    if (fromTrackId == toTrackId) {
      final updatedClips = List<Clip>.of(fromTrack.clips)
        ..removeAt(clipIndex)
        ..add(movedClip);
      updatedTracks[fromTrackIndex] = fromTrack.copyWith(clips: updatedClips);
    } else {
      final updatedFromClips = List<Clip>.of(fromTrack.clips)..removeAt(clipIndex);
      final toTrack = document.tracks[toTrackIndex];
      final updatedToClips = List<Clip>.of(toTrack.clips)..add(movedClip);

      updatedTracks[fromTrackIndex] = fromTrack.copyWith(clips: updatedFromClips);
      updatedTracks[toTrackIndex] = toTrack.copyWith(clips: updatedToClips);
    }

    final newDoc = document.copyWith(tracks: updatedTracks);
    final inverse = MoveClipCommand(
      clipId: clipId,
      fromTrackId: toTrackId,
      toTrackId: fromTrackId,
      newTimelineStartTicks: originalStart,
      previousTimelineStartTicks: newTimelineStartTicks,
    );

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoveClipCommand &&
          runtimeType == other.runtimeType &&
          clipId == other.clipId &&
          fromTrackId == other.fromTrackId &&
          toTrackId == other.toTrackId &&
          newTimelineStartTicks == other.newTimelineStartTicks;

  @override
  int get hashCode => Object.hash(clipId, fromTrackId, toTrackId, newTimelineStartTicks);

  @override
  String toString() =>
      'MoveClipCommand(clipId: $clipId, from: $fromTrackId, to: $toTrackId, start: $newTimelineStartTicks)';
}
