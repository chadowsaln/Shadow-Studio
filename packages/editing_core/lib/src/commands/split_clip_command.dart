import '../error/shadow_error.dart';
import '../model/clip.dart';
import '../model/project_document.dart';
import '../model/track.dart';
import 'edit_command.dart';
import 'join_clip_command.dart';

/// Pure command to cut/split a clip at a specific timeline tick into two adjacent clips.
///
/// Follows Spec §A.11:
/// - The first clip retains the original clip ID.
/// - The second clip receives [newClipId] (UUIDv7).
class SplitClipCommand implements EditCommand {
  final String trackId;
  final String clipId;
  final int splitAtTick;
  final String newClipId;

  const SplitClipCommand({
    required this.trackId,
    required this.clipId,
    required this.splitAtTick,
    required this.newClipId,
  });

  @override
  String get name => 'clip.split';

  @override
  CommandResult execute(ProjectDocument document) {
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

    final targetClip = track.clips[clipIndex];

    if (splitAtTick <= targetClip.timelineStartTicks ||
        splitAtTick >= targetClip.timelineEndTicks) {
      throw ShadowError.invalidOperation(
        'splitAtTick ($splitAtTick) must be strictly within clip bounds '
        '[${targetClip.timelineStartTicks}, ${targetClip.timelineEndTicks})',
      );
    }

    final existingNewClip = document.findClip(newClipId);
    if (existingNewClip != null) {
      throw ShadowError.invalidOperation(
        'newClipId "$newClipId" already exists in document',
      );
    }

    final offsetTicks = splitAtTick - targetClip.timelineStartTicks;
    final sourceOffsetTicks = (offsetTicks * targetClip.speedNum) ~/ targetClip.speedDen;

    final firstClip = targetClip.copyWith(
      durationTicks: offsetTicks,
    );

    final secondClip = targetClip.copyWith(
      id: newClipId,
      timelineStartTicks: splitAtTick,
      durationTicks: targetClip.durationTicks - offsetTicks,
      sourceInTicks: targetClip.sourceInTicks + sourceOffsetTicks,
    );

    final updatedClips = List<Clip>.of(track.clips)
      ..removeAt(clipIndex)
      ..add(firstClip)
      ..add(secondClip);

    final updatedTracks = List<Track>.of(document.tracks);
    updatedTracks[trackIndex] = track.copyWith(clips: updatedClips);

    final newDoc = document.copyWith(tracks: updatedTracks);
    final inverse = JoinClipCommand(
      trackId: trackId,
      firstClipId: targetClip.id,
      secondClipId: newClipId,
      originalClip: targetClip,
    );

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SplitClipCommand &&
          runtimeType == other.runtimeType &&
          trackId == other.trackId &&
          clipId == other.clipId &&
          splitAtTick == other.splitAtTick &&
          newClipId == other.newClipId;

  @override
  int get hashCode => Object.hash(trackId, clipId, splitAtTick, newClipId);

  @override
  String toString() =>
      'SplitClipCommand(trackId: $trackId, clipId: $clipId, splitAt: $splitAtTick, newClipId: $newClipId)';
}
