import '../error/shadow_error.dart';
import '../model/clip.dart';
import '../model/effect.dart';
import '../model/project_document.dart';
import '../model/track.dart';
import '../model/transform_box.dart';
import '../uuid/uuid_v7.dart';
import 'edit_command.dart';

/// Pure command that replaces the effect stack of a clip.
///
/// Effects are non-destructive and additive: each entry is validated (unique
/// id, non-empty key) and stored as-is so the RenderGraph resolver can map it
/// to the engine's effect vocabulary.
class SetClipEffectsCommand implements EditCommand {
  final String trackId;
  final String clipId;
  final List<Effect> effects;

  const SetClipEffectsCommand({
    required this.trackId,
    required this.clipId,
    required this.effects,
  });

  @override
  String get name => 'clip.effects';

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
    if (track.kind == TrackKind.audio) {
      throw ShadowError.invalidOperation(
        'Audio tracks do not accept video effects (Spec §أ.9)',
      );
    }

    final seen = <String>{};
    for (final effect in effects) {
      if (effect.effectKey.trim().isEmpty) {
        throw ShadowError.invalidOperation('Effect id "${effect.id}" has an empty key');
      }
      if (!seen.add(effect.id)) {
        throw ShadowError.invalidOperation(
          'Duplicate effect id "${effect.id}" in clip "$clipId"',
        );
      }
    }

    final clip = track.clips[clipIndex];
    final updatedClip = clip.copyWith(effects: effects);
    final clips = List<Clip>.of(track.clips)..[clipIndex] = updatedClip;

    final updatedTracks = List<Track>.of(document.tracks);
    updatedTracks[trackIndex] = track.copyWith(clips: clips);

    final newDoc = document.copyWith(tracks: updatedTracks);
    final inverse = SetClipEffectsCommand(
      trackId: trackId,
      clipId: clipId,
      effects: clip.effects,
    );

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetClipEffectsCommand &&
          runtimeType == other.runtimeType &&
          trackId == other.trackId &&
          clipId == other.clipId &&
          _effectsEqual(effects, other.effects);

  @override
  int get hashCode => Object.hash(trackId, clipId, Object.hashAll(effects));

  @override
  String toString() =>
      'SetClipEffectsCommand(trackId: $trackId, clipId: $clipId, effects: ${effects.length})';
}

/// Pure command that adds one effect to a clip's stack.
class AddClipEffectCommand implements EditCommand {
  final String trackId;
  final String clipId;
  final Effect effect;

  const AddClipEffectCommand({
    required this.trackId,
    required this.clipId,
    required this.effect,
  });

  @override
  String get name => 'clip.effect.add';

  @override
  CommandResult execute(ProjectDocument document) {
    if (effect.effectKey.trim().isEmpty) {
      throw ShadowError.invalidOperation('Effect key must not be empty');
    }
    final trackIndex = document.tracks.indexWhere((t) => t.id == trackId);
    if (trackIndex == -1) {
      throw ShadowError.invalidOperation('Track "$trackId" not found');
    }

    final track = document.tracks[trackIndex];
    if (track.kind == TrackKind.audio) {
      throw ShadowError.invalidOperation(
        'Audio tracks do not accept video effects (Spec §أ.9)',
      );
    }

    final clipIndex = track.clips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) {
      throw ShadowError.invalidOperation(
        'Clip "$clipId" not found on track "$trackId"',
      );
    }

    final clip = track.clips[clipIndex];
    if (clip.effects.any((e) => e.id == effect.id)) {
      throw ShadowError.invalidOperation(
        'Effect "${effect.id}" already exists on clip "$clipId"',
      );
    }

    final effects = List<Effect>.of(clip.effects)..add(effect);
    final updatedClip = clip.copyWith(effects: effects);
    final clips = List<Clip>.of(track.clips)..[clipIndex] = updatedClip;

    final updatedTracks = List<Track>.of(document.tracks);
    updatedTracks[trackIndex] = track.copyWith(clips: clips);

    final newDoc = document.copyWith(tracks: updatedTracks);
    final inverse = RemoveClipEffectCommand(
      trackId: trackId,
      clipId: clipId,
      effectId: effect.id,
    );

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AddClipEffectCommand &&
          runtimeType == other.runtimeType &&
          trackId == other.trackId &&
          clipId == other.clipId &&
          effect == other.effect;

  @override
  int get hashCode => Object.hash(trackId, clipId, effect);

  @override
  String toString() =>
      'AddClipEffectCommand(trackId: $trackId, clipId: $clipId, key: ${effect.effectKey})';
}

/// Pure command that removes a single effect from a clip's stack.
class RemoveClipEffectCommand implements EditCommand {
  final String trackId;
  final String clipId;
  final String effectId;

  const RemoveClipEffectCommand({
    required this.trackId,
    required this.clipId,
    required this.effectId,
  });

  @override
  String get name => 'clip.effect.remove';

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

    final clip = track.clips[clipIndex];
    final index = clip.effects.indexWhere((e) => e.id == effectId);
    if (index == -1) {
      throw ShadowError.invalidOperation(
        'Effect "$effectId" not found on clip "$clipId"',
      );
    }

    final removed = clip.effects[index];
    final effects = List<Effect>.of(clip.effects)..removeAt(index);
    final updatedClip = clip.copyWith(effects: effects);
    final clips = List<Clip>.of(track.clips)..[clipIndex] = updatedClip;

    final updatedTracks = List<Track>.of(document.tracks);
    updatedTracks[trackIndex] = track.copyWith(clips: clips);

    final newDoc = document.copyWith(tracks: updatedTracks);
    final inverse = AddClipEffectCommand(
      trackId: trackId,
      clipId: clipId,
      effect: removed,
    );

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoveClipEffectCommand &&
          runtimeType == other.runtimeType &&
          trackId == other.trackId &&
          clipId == other.clipId &&
          effectId == other.effectId;

  @override
  int get hashCode => Object.hash(trackId, clipId, effectId);

  @override
  String toString() =>
      'RemoveClipEffectCommand(trackId: $trackId, clipId: $clipId, effectId: $effectId)';
}

/// Pure command that changes a clip's visual properties: opacity, transform,
/// enabled flag and label.
class SetClipVisualCommand implements EditCommand {
  final String trackId;
  final String clipId;
  final int? opacityPpm;
  final TransformBox? transform;
  final bool? enabled;
  final String? label;

  const SetClipVisualCommand({
    required this.trackId,
    required this.clipId,
    this.opacityPpm,
    this.transform,
    this.enabled,
    this.label,
  });

  @override
  String get name => 'clip.visual';

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
    final requestedOpacity = opacityPpm;
    if (requestedOpacity != null &&
        (requestedOpacity < 0 || requestedOpacity > 1000000)) {
      throw ShadowError.invalidOperation(
        'opacityPpm must be within 0..1000000 (got $requestedOpacity)',
      );
    }

    final clip = track.clips[clipIndex];
    final updatedClip = clip.copyWith(
      opacityPpm: opacityPpm,
      transform: transform,
      enabled: enabled,
      label: label,
      clearLabel: label == null,
    );
    final clips = List<Clip>.of(track.clips)..[clipIndex] = updatedClip;

    final updatedTracks = List<Track>.of(document.tracks);
    updatedTracks[trackIndex] = track.copyWith(clips: clips);

    final newDoc = document.copyWith(tracks: updatedTracks);
    final inverse = SetClipVisualCommand(
      trackId: trackId,
      clipId: clipId,
      opacityPpm: clip.opacityPpm,
      transform: clip.transform,
      enabled: clip.enabled,
      label: clip.label,
    );

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetClipVisualCommand &&
          runtimeType == other.runtimeType &&
          trackId == other.trackId &&
          clipId == other.clipId &&
          opacityPpm == other.opacityPpm &&
          transform == other.transform &&
          enabled == other.enabled &&
          label == other.label;

  @override
  int get hashCode =>
      Object.hash(trackId, clipId, opacityPpm, transform, enabled, label);

  @override
  String toString() =>
      'SetClipVisualCommand(trackId: $trackId, clipId: $clipId, opacityPpm: $opacityPpm, enabled: $enabled)';
}

/// Generates a fresh effect id for tool layers that do not supply one.
String newEffectId() => 'fx_${UuidV7.generate()}';

bool _effectsEqual(List<Effect> a, List<Effect> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}