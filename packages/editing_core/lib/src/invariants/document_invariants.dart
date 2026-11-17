import 'dart:math';

import '../error/shadow_error.dart';
import '../model/asset.dart';
import '../model/clip.dart';
import '../model/project_document.dart';
import '../model/track.dart';
import '../model/transition_kind.dart';

/// Invariant validation for [ProjectDocument].
///
/// Enforces all architecture constraints per Spec §3.4, §9.2, and §14.3.
/// Invariants return or throw EDIT_INVALID_OPERATION on violation.
abstract final class DocumentInvariants {
  /// Validates [document] against all invariants.
  ///
  /// Throws [ShadowError.invalidOperation] if any invariant is violated.
  static void validate(ProjectDocument document) {
    final violations = check(document);
    if (violations.isNotEmpty) {
      throw ShadowError.invalidOperation(
        'Document invariant violation: ${violations.first}',
        details: {'violations': violations},
      );
    }
  }

  /// Checks [document] and returns a list of all invariant violation messages.
  static List<String> check(ProjectDocument document) {
    final violations = <String>[];

    // 1. Unique track IDs and dense track positions (0..n-1)
    final trackIds = <String>{};
    for (var i = 0; i < document.tracks.length; i++) {
      final track = document.tracks[i];
      if (!trackIds.add(track.id)) {
        violations.add('Duplicate track ID: ${track.id}');
      }
      if (track.position != i) {
        violations.add(
          'Track "${track.name}" (${track.id}) has position ${track.position}, expected dense index $i',
        );
      }
    }

    // 2. Unique clip IDs across all tracks
    final allClipIds = <String>{};
    final allTextLayerIds = <String>{};

    for (final track in document.tracks) {
      // 3. Track clips must not overlap and must have positive duration
      for (var i = 0; i < track.clips.length; i++) {
        final clip = track.clips[i];

        // Unique clip IDs
        if (!allClipIds.add(clip.id)) {
          violations.add('Duplicate clip ID across document: ${clip.id}');
        }

        // Positive duration
        if (clip.durationTicks <= 0) {
          violations.add(
              'Clip ${clip.id} has non-positive duration: ${clip.durationTicks}');
        }

        // Clip kinds vs Track kinds aligned with rendergraph.schema.json
        if (track.kind == TrackKind.audio && clip.kind != ClipKind.audio) {
          violations.add(
            'Clip ${clip.id} of kind "${clip.kind.name}" placed on audio track ${track.id}',
          );
        }
        if (track.kind == TrackKind.video && clip.kind == ClipKind.audio) {
          violations
              .add('Audio clip ${clip.id} placed on video track ${track.id}');
        }
        if (track.kind == TrackKind.overlay) {
          violations.add(
            'Overlay track ${track.id} can only hold text_layers, not media clips (${clip.id})',
          );
        }

        // Asset bounds and kind matching
        if (clip.assetId != null) {
          final asset = document.assets[clip.assetId];
          if (asset == null) {
            violations.add(
              'Clip ${clip.id} references missing asset: ${clip.assetId}',
            );
          } else {
            // Asset kind vs Track kind
            if (track.kind == TrackKind.video) {
              if (asset.kind != AssetKind.video &&
                  asset.kind != AssetKind.image) {
                violations.add(
                  'Asset ${asset.id} (${asset.kind.name}) cannot be placed on video track ${track.id}',
                );
              }
            } else if (track.kind == TrackKind.audio) {
              // Audio tracks accept audio assets, or video assets with an audio stream
              if (asset.kind != AssetKind.audio &&
                  !(asset.kind == AssetKind.video && clip.streamIndex >= 0)) {
                violations.add(
                  'Asset ${asset.id} (${asset.kind.name}) without audio stream cannot be placed on audio track ${track.id}',
                );
              }
            } else if (track.kind == TrackKind.overlay) {
              violations.add(
                'Media asset ${asset.id} cannot be placed on overlay track ${track.id}',
              );
            }

            // Clip inside asset bounds
            if (clip.sourceInTicks < 0) {
              violations.add(
                  'Clip ${clip.id} has negative source_in: ${clip.sourceInTicks}');
            }
            final sourceOutTicks = clip.sourceEndTicks;
            if (sourceOutTicks > asset.durationTicks) {
              violations.add(
                'Clip ${clip.id} exceeds asset ${asset.id} bounds: source_out ($sourceOutTicks) > asset duration (${asset.durationTicks})',
              );
            }
          }
        }

        // Check overlap with next clip on this track
        if (i + 1 < track.clips.length) {
          final nextClip = track.clips[i + 1];
          if (clip.timelineEndTicks > nextClip.timelineStartTicks) {
            violations.add(
              'Overlap on track ${track.id}: clip ${clip.id} [${clip.timelineStartTicks}, ${clip.timelineEndTicks}) overlaps with clip ${nextClip.id} [${nextClip.timelineStartTicks}, ${nextClip.timelineEndTicks})',
            );
          }
        }
      }

      // 3b. Text layers live on overlay tracks and are internally consistent.
      for (final layer in track.textLayers) {
        if (!allTextLayerIds.add(layer.id)) {
          violations
              .add('Duplicate text layer ID across document: ${layer.id}');
        }
        if (track.kind != TrackKind.overlay) {
          violations.add(
            'Text layer ${layer.id} placed on ${track.kind.name} track ${track.id}; text layers require overlay tracks',
          );
        }
        if (layer.startTicks < 0) {
          violations.add(
            'Text layer ${layer.id} has negative start: ${layer.startTicks}',
          );
        }
        if (layer.durationTicks <= 0) {
          violations.add(
            'Text layer ${layer.id} has non-positive duration: ${layer.durationTicks}',
          );
        }
        final animTotal =
            layer.animationIn.durationTicks + layer.animationOut.durationTicks;
        if (layer.animationIn.kind == 'none' &&
            layer.animationIn.durationTicks != 0) {
          violations.add(
            'Text layer ${layer.id} has animation_in duration with kind none',
          );
        }
        if (layer.animationOut.kind == 'none' &&
            layer.animationOut.durationTicks != 0) {
          violations.add(
            'Text layer ${layer.id} has animation_out duration with kind none',
          );
        }
        if (animTotal > layer.durationTicks) {
          violations.add(
            'Text layer ${layer.id} animations ($animTotal) exceed duration (${layer.durationTicks})',
          );
        }
        final hasText = layer.text != null && layer.text!.trim().isNotEmpty;
        if (!hasText && !layer.isRenderable) {
          violations.add(
            'Text layer ${layer.id} has neither text nor a complete raster (uri+hash+size)',
          );
        }
        if (layer.rasterUri != null &&
            (layer.rasterHash == null ||
                layer.rasterWidth <= 0 ||
                layer.rasterHeight <= 0)) {
          violations.add(
            'Text layer ${layer.id} has raster_uri without hash/positive size',
          );
        }
        if (layer.subtitle &&
            track.textLayers.any(
              (other) =>
                  other.id != layer.id &&
                  other.subtitle &&
                  other.startTicks < layer.endTicks &&
                  layer.startTicks < other.endTicks,
            )) {
          violations.add(
            'Subtitle cue ${layer.id} overlaps another cue on track ${track.id}',
          );
        }
      }

      // 4. Transitions must be strictly on the cut boundary of two adjacent clips
      if (track.kind != TrackKind.video && track.transitions.isNotEmpty) {
        violations.add(
          'Track ${track.id} (${track.kind.name}) holds transitions; only video tracks support transitions',
        );
      }
      for (final transition in track.transitions) {
        if (!TransitionKinds.isValid(transition.kind)) {
          violations.add(
            'Transition ${transition.id} has unknown kind "${transition.kind}"',
          );
        }
        if (transition.durationTicks <= 0) {
          violations.add(
            'Transition ${transition.id} has non-positive duration: ${transition.durationTicks}',
          );
        }

        final fromClip = track.findClip(transition.fromClipId);
        final toClip = track.findClip(transition.toClipId);

        if (fromClip == null) {
          violations.add(
            'Transition ${transition.id} references missing fromClip: ${transition.fromClipId}',
          );
        }
        if (toClip == null) {
          violations.add(
            'Transition ${transition.id} references missing toClip: ${transition.toClipId}',
          );
        }

        if (fromClip != null && toClip != null) {
          // Boundary check: transition.at_ticks must equal fromClip.end and toClip.start
          if (transition.atTicks != fromClip.timelineEndTicks ||
              transition.atTicks != toClip.timelineStartTicks) {
            violations.add(
              'Transition ${transition.id} at_ticks (${transition.atTicks}) is not on boundary of ${fromClip.id} (ends at ${fromClip.timelineEndTicks}) and ${toClip.id} (starts at ${toClip.timelineStartTicks})',
            );
          }

          // Duration check: <= half of shorter clip
          final maxAllowedDuration =
              min(fromClip.durationTicks, toClip.durationTicks) ~/ 2;
          if (transition.durationTicks > maxAllowedDuration) {
            violations.add(
              'Transition ${transition.id} duration (${transition.durationTicks}) exceeds half of shortest clip ($maxAllowedDuration)',
            );
          }
        }
      }
    }

    return violations;
  }
}
