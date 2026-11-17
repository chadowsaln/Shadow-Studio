import '../error/shadow_error.dart';
import '../model/clip.dart';
import '../model/project_document.dart';
import '../model/track.dart';
import 'edit_command.dart';

/// Pure command that changes the audio mix parameters of an audio track.
///
/// Editing Core v1 audio mixing = gain + pan + mute (Spec §أ.9: no audio
/// effects in the v1 contract). Values are validated against the same ranges
/// the RenderGraph contract enforces.
class SetTrackAudioCommand implements EditCommand {
  final String trackId;
  final int? gainMb;
  final int? panPpm;
  final bool? enabled;

  const SetTrackAudioCommand({
    required this.trackId,
    this.gainMb,
    this.panPpm,
    this.enabled,
  });

  @override
  String get name => 'track.audio';

  @override
  CommandResult execute(ProjectDocument document) {
    final trackIndex = document.tracks.indexWhere((t) => t.id == trackId);
    if (trackIndex == -1) {
      throw ShadowError.invalidOperation('Track "$trackId" not found');
    }

    final track = document.tracks[trackIndex];
    if (track.kind != TrackKind.audio && gainMb != null) {
      throw ShadowError.invalidOperation(
        'Track "$trackId" is not an audio track',
      );
    }
    _validateGain(gainMb);
    _validatePan(panPpm);

    final updated = track.copyWith(
      gainMb: gainMb,
      panPpm: panPpm,
      enabled: enabled,
      clearGainMb: gainMb == null,
      clearPanPpm: panPpm == null,
    );
    final updatedTracks = List<Track>.of(document.tracks);
    updatedTracks[trackIndex] = updated;

    final newDoc = document.copyWith(tracks: updatedTracks);
    final inverse = SetTrackAudioCommand(
      trackId: trackId,
      gainMb: track.gainMb,
      panPpm: track.panPpm,
      enabled: track.enabled,
    );

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetTrackAudioCommand &&
          runtimeType == other.runtimeType &&
          trackId == other.trackId &&
          gainMb == other.gainMb &&
          panPpm == other.panPpm &&
          enabled == other.enabled;

  @override
  int get hashCode => Object.hash(trackId, gainMb, panPpm, enabled);

  @override
  String toString() =>
      'SetTrackAudioCommand(trackId: $trackId, gainMb: $gainMb, panPpm: $panPpm, enabled: $enabled)';
}

/// Pure command that changes the audio properties of a single clip
/// (gain, pan, fades) without touching its media or timeline placement.
class SetClipAudioCommand implements EditCommand {
  final String trackId;
  final String clipId;
  final int? gainMb;
  final int? panPpm;
  final int? fadeInTicks;
  final int? fadeOutTicks;
  final bool? enabled;

  const SetClipAudioCommand({
    required this.trackId,
    required this.clipId,
    this.gainMb,
    this.panPpm,
    this.fadeInTicks,
    this.fadeOutTicks,
    this.enabled,
  });

  @override
  String get name => 'clip.audio';

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
    if (clip.kind != ClipKind.audio && track.kind != TrackKind.audio) {
      throw ShadowError.invalidOperation(
        'Clip "$clipId" is not an audio clip; audio properties are audio-only',
      );
    }

    _validateGain(gainMb);
    _validatePan(panPpm);
    _validateFades(clip, fadeInTicks, fadeOutTicks);

    final updatedClip = clip.copyWith(
      gainMb: gainMb,
      panPpm: panPpm,
      fadeInTicks: fadeInTicks,
      fadeOutTicks: fadeOutTicks,
      enabled: enabled,
    );
    final clips = List<Clip>.of(track.clips)..[clipIndex] = updatedClip;

    final updatedTracks = List<Track>.of(document.tracks);
    updatedTracks[trackIndex] = track.copyWith(clips: clips);

    final newDoc = document.copyWith(tracks: updatedTracks);
    final inverse = SetClipAudioCommand(
      trackId: trackId,
      clipId: clipId,
      gainMb: clip.gainMb,
      panPpm: clip.panPpm,
      fadeInTicks: clip.fadeInTicks,
      fadeOutTicks: clip.fadeOutTicks,
      enabled: clip.enabled,
    );

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetClipAudioCommand &&
          runtimeType == other.runtimeType &&
          trackId == other.trackId &&
          clipId == other.clipId &&
          gainMb == other.gainMb &&
          panPpm == other.panPpm &&
          fadeInTicks == other.fadeInTicks &&
          fadeOutTicks == other.fadeOutTicks &&
          enabled == other.enabled;

  @override
  int get hashCode => Object.hash(
        trackId,
        clipId,
        gainMb,
        panPpm,
        fadeInTicks,
        fadeOutTicks,
        enabled,
      );

  @override
  String toString() =>
      'SetClipAudioCommand(trackId: $trackId, clipId: $clipId, gainMb: $gainMb, panPpm: $panPpm)';
}

void _validateGain(int? gainMb) {
  if (gainMb != null && (gainMb < -60000 || gainMb > 24000)) {
    throw ShadowError.invalidOperation(
      'gainMb must be within -60000..24000 (got $gainMb)',
    );
  }
}

void _validatePan(int? panPpm) {
  if (panPpm != null && (panPpm < -1000000 || panPpm > 1000000)) {
    throw ShadowError.invalidOperation(
      'panPpm must be within -1000000..1000000 (got $panPpm)',
    );
  }
}

void _validateFades(Clip clip, int? fadeInTicks, int? fadeOutTicks) {
  final newIn = fadeInTicks ?? clip.fadeInTicks;
  final newOut = fadeOutTicks ?? clip.fadeOutTicks;
  if (newIn < 0 || newOut < 0) {
    throw ShadowError.invalidOperation('Fade durations must be >= 0');
  }
  if (newIn + newOut > clip.durationTicks) {
    throw ShadowError.invalidOperation(
      'fade_in + fade_out ($newIn + $newOut) exceeds clip duration (${clip.durationTicks})',
    );
  }
}