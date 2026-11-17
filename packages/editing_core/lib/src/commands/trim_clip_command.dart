import '../error/shadow_error.dart';
import '../model/clip.dart';
import '../model/project_document.dart';
import '../model/track.dart';
import 'edit_command.dart';

/// Pure command to trim a clip's timeline start, duration, and/or source in points.
class TrimClipCommand implements EditCommand {
  final String trackId;
  final String clipId;
  final int newTimelineStartTicks;
  final int newDurationTicks;
  final int newSourceInTicks;
  final int? previousTimelineStartTicks;
  final int? previousDurationTicks;
  final int? previousSourceInTicks;

  const TrimClipCommand({
    required this.trackId,
    required this.clipId,
    required this.newTimelineStartTicks,
    required this.newDurationTicks,
    required this.newSourceInTicks,
    this.previousTimelineStartTicks,
    this.previousDurationTicks,
    this.previousSourceInTicks,
  });

  @override
  String get name => 'clip.trim';

  @override
  CommandResult execute(ProjectDocument document) {
    if (newTimelineStartTicks < 0) {
      throw ShadowError.invalidOperation(
        'newTimelineStartTicks must be >= 0 (got $newTimelineStartTicks)',
      );
    }
    if (newDurationTicks <= 0) {
      throw ShadowError.invalidOperation(
        'newDurationTicks must be > 0 (got $newDurationTicks)',
      );
    }
    if (newSourceInTicks < 0) {
      throw ShadowError.invalidOperation(
        'newSourceInTicks must be >= 0 (got $newSourceInTicks)',
      );
    }

    final trackIndex = document.tracks.indexWhere((t) => t.id == trackId);
    if (trackIndex == -1) {
      throw ShadowError.invalidOperation('Track "$trackId" not found');
    }

    final track = document.tracks[trackIndex];
    final clipIndex = track.clips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) {
      throw ShadowError.invalidOperation(
        'Clip "$clipId" not found on track "$trackId"',
      );
    }

    final originalClip = track.clips[clipIndex];
    final trimmedClip = originalClip.copyWith(
      timelineStartTicks: newTimelineStartTicks,
      durationTicks: newDurationTicks,
      sourceInTicks: newSourceInTicks,
    );

    final updatedClips = List<Clip>.of(track.clips)
      ..removeAt(clipIndex)
      ..add(trimmedClip);

    final updatedTracks = List<Track>.of(document.tracks);
    updatedTracks[trackIndex] = track.copyWith(clips: updatedClips);

    final newDoc = document.copyWith(tracks: updatedTracks);
    final inverse = TrimClipCommand(
      trackId: trackId,
      clipId: clipId,
      newTimelineStartTicks: originalClip.timelineStartTicks,
      newDurationTicks: originalClip.durationTicks,
      newSourceInTicks: originalClip.sourceInTicks,
      previousTimelineStartTicks: newTimelineStartTicks,
      previousDurationTicks: newDurationTicks,
      previousSourceInTicks: newSourceInTicks,
    );

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrimClipCommand &&
          runtimeType == other.runtimeType &&
          trackId == other.trackId &&
          clipId == other.clipId &&
          newTimelineStartTicks == other.newTimelineStartTicks &&
          newDurationTicks == other.newDurationTicks &&
          newSourceInTicks == other.newSourceInTicks;

  @override
  int get hashCode => Object.hash(
        trackId,
        clipId,
        newTimelineStartTicks,
        newDurationTicks,
        newSourceInTicks,
      );

  @override
  String toString() =>
      'TrimClipCommand(clipId: $clipId, start: $newTimelineStartTicks, dur: $newDurationTicks, in: $newSourceInTicks)';
}
