import '../error/shadow_error.dart';
import '../model/project_document.dart';
import '../model/track.dart';
import '../model/transition.dart';
import 'add_transition_command.dart';
import 'edit_command.dart';

/// Pure command that removes a transition from a track.
///
/// Carries the removed transition so undo can restore the exact original
/// (id, kind, cut point and duration).
class RemoveTransitionCommand implements EditCommand {
  final String trackId;
  final String transitionId;
  final Transition? removedTransition;

  const RemoveTransitionCommand({
    required this.trackId,
    required this.transitionId,
    this.removedTransition,
  });

  @override
  String get name => 'transition.remove';

  @override
  CommandResult execute(ProjectDocument document) {
    final trackIndex = document.tracks.indexWhere((t) => t.id == trackId);
    if (trackIndex == -1) {
      throw ShadowError.invalidOperation('Track "$trackId" not found');
    }

    final track = document.tracks[trackIndex];
    final index = track.transitions.indexWhere((t) => t.id == transitionId);
    if (index == -1) {
      throw ShadowError.invalidOperation(
        'Transition "$transitionId" not found on track "$trackId"',
      );
    }

    final removed = track.transitions[index];
    final transitions = List<Transition>.of(track.transitions)..removeAt(index);

    final updatedTracks = List<Track>.of(document.tracks);
    updatedTracks[trackIndex] = track.copyWith(transitions: transitions);

    final newDoc = document.copyWith(tracks: updatedTracks);
    final inverse = AddTransitionCommand(
      trackId: trackId,
      fromClipId: removed.fromClipId,
      toClipId: removed.toClipId,
      kind: removed.kind,
      durationTicks: removed.durationTicks,
      transitionId: removed.id,
    );

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoveTransitionCommand &&
          runtimeType == other.runtimeType &&
          trackId == other.trackId &&
          transitionId == other.transitionId;

  @override
  int get hashCode => Object.hash(trackId, transitionId);

  @override
  String toString() =>
      'RemoveTransitionCommand(trackId: $trackId, transitionId: $transitionId)';
}