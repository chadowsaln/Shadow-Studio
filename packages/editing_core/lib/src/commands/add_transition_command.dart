import '../error/shadow_error.dart';
import '../model/project_document.dart';
import '../model/track.dart';
import '../model/transition.dart';
import '../model/transition_kind.dart';
import '../uuid/uuid_v7.dart';
import 'edit_command.dart';
import 'remove_transition_command.dart';

/// Pure command that places a transition on the cut between two adjacent clips.
///
/// Enforces the RenderGraph §A.7 / §3.4 rules eagerly so a bad transition can
/// never reach the document:
/// - both clips live on the same track,
/// - the clips are adjacent (`from.end == to.start`),
/// - the kind is part of the closed v1 vocabulary,
/// - `durationTicks > 0` and `durationTicks * 2 <= min(from, to)`,
/// - the transition id is unique.
class AddTransitionCommand implements EditCommand {
  final String trackId;
  final String fromClipId;
  final String toClipId;
  final String kind;
  final int durationTicks;
  final String? transitionId;

  const AddTransitionCommand({
    required this.trackId,
    required this.fromClipId,
    required this.toClipId,
    required this.kind,
    required this.durationTicks,
    this.transitionId,
  });

  @override
  String get name => 'transition.add';

  @override
  CommandResult execute(ProjectDocument document) {
    final trackIndex = document.tracks.indexWhere((t) => t.id == trackId);
    if (trackIndex == -1) {
      throw ShadowError.invalidOperation('Track "$trackId" not found');
    }

    if (!TransitionKinds.isValid(kind)) {
      throw ShadowError.invalidOperation(
        'Unknown transition kind "$kind"; allowed: ${TransitionKinds.all.join(', ')}',
      );
    }

    final track = document.tracks[trackIndex];
    final fromIndex = track.clips.indexWhere((c) => c.id == fromClipId);
    if (fromIndex == -1) {
      throw ShadowError.invalidOperation(
        'From clip "$fromClipId" not found on track "$trackId"',
      );
    }
    final toIndex = track.clips.indexWhere((c) => c.id == toClipId);
    if (toIndex == -1) {
      throw ShadowError.invalidOperation(
        'To clip "$toClipId" not found on track "$trackId"',
      );
    }

    final fromClip = track.clips[fromIndex];
    final toClip = track.clips[toIndex];

    if (toIndex != fromIndex + 1) {
      throw ShadowError.invalidOperation(
        'Transition clips must be adjacent on the track: ${fromClip.id} ends at '
        '${fromClip.timelineEndTicks}, ${toClip.id} starts at ${toClip.timelineStartTicks}',
      );
    }
    if (fromClip.timelineEndTicks != toClip.timelineStartTicks) {
      throw ShadowError.invalidOperation(
        'Transition cut mismatch: ${fromClip.id} ends at ${fromClip.timelineEndTicks} '
        'but ${toClip.id} starts at ${toClip.timelineStartTicks}',
      );
    }

    if (durationTicks <= 0) {
      throw ShadowError.invalidOperation('Transition duration must be positive');
    }
    final shortest = fromClip.durationTicks < toClip.durationTicks
        ? fromClip.durationTicks
        : toClip.durationTicks;
    if (durationTicks * 2 > shortest) {
      throw ShadowError.invalidOperation(
        'Transition duration ($durationTicks) exceeds half of the shortest clip '
        '(${shortest ~/ 2})',
      );
    }

    final id = transitionId ?? UuidV7.generate();
    if (track.transitions.any((t) => t.id == id)) {
      throw ShadowError.invalidOperation('Transition "$id" already exists');
    }
    for (final existing in track.transitions) {
      if (existing.fromClipId == fromClipId && existing.toClipId == toClipId) {
        throw ShadowError.invalidOperation(
          'A transition already exists between ${fromClip.id} and ${toClip.id}',
        );
      }
    }

    final transition = Transition(
      id: id,
      kind: kind,
      atTicks: fromClip.timelineEndTicks,
      durationTicks: durationTicks,
      fromClipId: fromClip.id,
      toClipId: toClip.id,
    );

    final transitions = List<Transition>.of(track.transitions)
      ..add(transition)
      ..sort((a, b) => a.atTicks.compareTo(b.atTicks));

    final updatedTracks = List<Track>.of(document.tracks);
    updatedTracks[trackIndex] = track.copyWith(transitions: transitions);

    final newDoc = document.copyWith(tracks: updatedTracks);
    final inverse = RemoveTransitionCommand(
      trackId: trackId,
      transitionId: id,
      removedTransition: transition,
    );

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AddTransitionCommand &&
          runtimeType == other.runtimeType &&
          trackId == other.trackId &&
          fromClipId == other.fromClipId &&
          toClipId == other.toClipId &&
          kind == other.kind &&
          durationTicks == other.durationTicks &&
          transitionId == other.transitionId;

  @override
  int get hashCode =>
      Object.hash(trackId, fromClipId, toClipId, kind, durationTicks, transitionId);

  @override
  String toString() =>
      'AddTransitionCommand(trackId: $trackId, $fromClipId -> $toClipId, kind: $kind, dur: $durationTicks)';
}