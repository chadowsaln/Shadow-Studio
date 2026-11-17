import 'package:editing_core/editing_core.dart' as core;
import 'package:shadow_contracts/shadow_contracts.dart';

/// Adapts the Editing Core service to the [EditingService] contract.
///
/// The adapter is the only place where tool-layer edit operations are translated
/// into Editing Core commands, so the editor's invariants, undo/redo and revision
/// rules stay authoritative.
class CoreEditingServiceAdapter implements EditingService {
  CoreEditingServiceAdapter(this._core);

  final core.EditingService _core;

  @override
  int get revision => _core.revision;

  @override
  Future<ProjectDocument> openProject(String path) async {
    final document = await _core.openProject(path);
    return _DocumentHandle(document.id, _core.revision);
  }

  @override
  Future<EditOutcome> apply(
    EditTransaction transaction, {
    required int expectedRevision,
  }) async {
    final commands = <core.EditCommand>[];
    for (final operation in transaction.operations) {
      commands.add(_toCommand(operation));
    }
    final outcome = await _core.apply(
      core.EditTransaction(
        description: transaction.label,
        commands: commands,
        origin: 'ai',
      ),
      expectedRevision: expectedRevision,
    );
    return _mapOutcome(outcome, transaction.operations);
  }

  @override
  Future<EditOutcome> undo({required int expectedRevision}) async {
    final outcome = await _core.undo(expectedRevision: expectedRevision);
    return _mapOutcome(outcome, const <EditOperation>[]);
  }

  @override
  Future<EditOutcome> redo({required int expectedRevision}) async {
    final outcome = await _core.redo(expectedRevision: expectedRevision);
    return _mapOutcome(outcome, const <EditOperation>[]);
  }

  @override
  Future<void> save() => _core.save();

  @override
  Future<Map<String, Object?>> resolveGraph({
    required int revision,
    required RangeTicks range,
  }) async {
    final graph = _core.resolveGraph(
      revision: revision,
      range: core.RangeTicks(
        startTicks: range.start,
        durationTicks: range.end > range.start ? range.end - range.start : 1,
      ),
    );
    return graph.toJson();
  }

  EditOutcome _mapOutcome(core.EditOutcome outcome, List<EditOperation> applied) {
    if (outcome is core.EditSuccess) {
      return EditOutcome(
        revision: outcome.revision,
        applied: applied,
        events: <Object?>[outcome.document.id],
      );
    }
    final error = (outcome as core.EditFailure).error;
    throw ShadowError(
      code: error.code,
      category: _category(error.category),
      retryable: error.retryable,
      correlationId: error.correlationId ?? '',
      details: error.details,
      message: error.message,
    );
  }

  core.EditCommand _toCommand(EditOperation operation) {
    final payload = operation.payload;
    switch (operation.type) {
      case 'add_clip':
        return core.AddClipCommand(
          trackId: operation.target,
          clip: core.Clip(
            id: payload['clipId'] as String? ?? core.UuidV7.generate(),
            assetId:
                payload['assetId'] as String? ?? payload['assetPath'] as String?,
            kind: _clipKind(payload['kind'] as String?),
            timelineStartTicks: _int(payload['startTick'], 'startTick'),
            durationTicks: _int(payload['durationTicks'], 'durationTicks'),
            sourceInTicks: payload['sourceInTick'] as int? ?? 0,
            label: payload['label'] as String?,
          ),
        );

      case 'trim_clip':
        return core.TrimClipCommand(
          trackId: _trackFor(payload['clipId'] as String, operation.target),
          clipId: payload['clipId'] as String,
          newTimelineStartTicks:
              payload['startTick'] as int? ?? _clip(payload['clipId'] as String).timelineStartTicks,
          newDurationTicks: payload['durationTicks'] as int? ??
              _durationFromInOut(payload, operation),
          newSourceInTicks: payload['inTick'] as int? ?? 0,
        );

      case 'remove_clip':
        return core.RemoveClipCommand(
          trackId: _trackFor(payload['clipId'] as String, operation.target),
          clipId: payload['clipId'] as String,
        );

      case 'split_clip':
        return core.SplitClipCommand(
          trackId: _trackFor(payload['clipId'] as String, operation.target),
          clipId: payload['clipId'] as String,
          splitAtTick: _int(payload['splitAtTick'], 'splitAtTick'),
          newClipId: payload['newClipId'] as String? ?? core.UuidV7.generate(),
        );

      case 'move_clip':
        final clipId = payload['clipId'] as String;
        return core.MoveClipCommand(
          clipId: clipId,
          fromTrackId: _trackFor(clipId, operation.target),
          toTrackId: payload['toTrackId'] as String? ?? operation.target,
          newTimelineStartTicks: _int(payload['startTick'], 'startTick'),
        );

      case 'add_track':
        return core.AddTrackCommand(
          core.Track(
            id: operation.target,
            kind: _trackKind(payload['kind'] as String?),
            position: payload['position'] as int? ?? 0,
            name: payload['name'] as String? ?? operation.target,
          ),
        );

      default:
        throw ShadowError(
          code: ShadowErrorCode.editInvalidOperation,
          category: ShadowErrorCategory.edit,
          retryable: false,
          correlationId: '',
          message: 'Unsupported edit operation: ${operation.type}',
        );
    }
  }

  core.Clip _clip(String clipId) {
    for (final track in _core.currentDocument.tracks) {
      for (final clip in track.clips) {
        if (clip.id == clipId) return clip;
      }
    }
    throw ShadowError(
      code: ShadowErrorCode.editInvalidOperation,
      category: ShadowErrorCategory.edit,
      retryable: false,
      correlationId: '',
      message: 'Clip not found: $clipId',
    );
  }

  String _trackFor(String clipId, String fallback) {
    if (fallback.isNotEmpty &&
        _core.currentDocument.tracks.any((t) => t.id == fallback)) {
      return fallback;
    }
    for (final track in _core.currentDocument.tracks) {
      if (track.clips.any((c) => c.id == clipId)) return track.id;
    }
    throw ShadowError(
      code: ShadowErrorCode.editInvalidOperation,
      category: ShadowErrorCategory.edit,
      retryable: false,
      correlationId: '',
      message: 'Track for clip not found: $clipId',
    );
  }

  int _durationFromInOut(Map<String, Object?> payload, EditOperation operation) {
    final inTick = payload['inTick'] as int?;
    final outTick = payload['outTick'] as int?;
    if (inTick != null && outTick != null) {
      if (outTick < inTick) {
        throw ShadowError(
          code: ShadowErrorCode.editInvalidOperation,
          category: ShadowErrorCategory.edit,
          retryable: false,
          correlationId: '',
          message: 'outTick must be >= inTick',
        );
      }
      return outTick - inTick;
    }
    return _clip(operation.target).durationTicks;
  }

  static int _int(Object? value, String field) {
    if (value is int) return value;
    throw ShadowError(
      code: ShadowErrorCode.editInvalidOperation,
      category: ShadowErrorCategory.edit,
      retryable: false,
      correlationId: '',
      message: '$field must be an integer',
    );
  }

  static core.ClipKind _clipKind(String? value) {
    switch (value) {
      case 'audio':
        return core.ClipKind.audio;
      case 'image':
        return core.ClipKind.image;
      case 'color':
        return core.ClipKind.color;
      case 'adjustment':
        return core.ClipKind.adjustment;
      default:
        return core.ClipKind.video;
    }
  }

  static core.TrackKind _trackKind(String? value) {
    switch (value) {
      case 'audio':
        return core.TrackKind.audio;
      case 'overlay':
        return core.TrackKind.overlay;
      default:
        return core.TrackKind.video;
    }
  }

  static ShadowErrorCategory _category(String value) {
    switch (value) {
      case 'agent':
        return ShadowErrorCategory.agent;
      case 'provider':
        return ShadowErrorCategory.provider;
      case 'tool':
        return ShadowErrorCategory.tool;
      case 'perm':
        return ShadowErrorCategory.perm;
      case 'media':
        return ShadowErrorCategory.media;
      case 'store':
        return ShadowErrorCategory.store;
      default:
        return ShadowErrorCategory.edit;
    }
  }
}

class _DocumentHandle implements ProjectDocument {
  const _DocumentHandle(this.id, this.revision);
  @override
  final String id;
  @override
  final int revision;
}