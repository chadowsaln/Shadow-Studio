import '../error/shadow_error.dart';
import '../model/project_document.dart';
import '../model/text_layer.dart';
import '../model/track.dart';
import 'edit_command.dart';

/// Validates that [layer] may live on an overlay track.
void _validateOverlayTrack(ProjectDocument document, String trackId) {
  final trackIndex = document.tracks.indexWhere((t) => t.id == trackId);
  if (trackIndex == -1) {
    throw ShadowError.invalidOperation('Track "$trackId" not found');
  }
  if (document.tracks[trackIndex].kind != TrackKind.overlay) {
    throw ShadowError.invalidOperation(
      'Track "$trackId" is not an overlay track; text layers belong on overlay tracks',
    );
  }
}

/// Pure command that adds a text layer (title or subtitle cue) to an overlay track.
class AddTextLayerCommand implements EditCommand {
  final String trackId;
  final TextLayer layer;

  const AddTextLayerCommand({required this.trackId, required this.layer});

  @override
  String get name => 'text.add';

  @override
  CommandResult execute(ProjectDocument document) {
    _validateOverlayTrack(document, trackId);

    final track = document.tracks.firstWhere((t) => t.id == trackId);
    if (track.textLayers.any((l) => l.id == layer.id)) {
      throw ShadowError.invalidOperation(
        'Text layer "${layer.id}" already exists on track "$trackId"',
      );
    }
    if (layer.subtitle &&
        track.textLayers.any((l) => l.subtitle && _overlaps(l, layer))) {
      throw ShadowError.invalidOperation(
        'Subtitle cue "${layer.id}" overlaps an existing cue on track "$trackId"',
      );
    }

    final layers = List<TextLayer>.of(track.textLayers)
      ..add(layer)
      ..sort((a, b) => a.startTicks.compareTo(b.startTicks));

    final updatedTracks = List<Track>.of(document.tracks);
    updatedTracks[document.tracks.indexWhere((t) => t.id == trackId)] =
        track.copyWith(textLayers: layers);

    final newDoc = document.copyWith(tracks: updatedTracks);
    final inverse = RemoveTextLayerCommand(
      trackId: trackId,
      layerId: layer.id,
      removedLayer: layer,
    );

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AddTextLayerCommand &&
          runtimeType == other.runtimeType &&
          trackId == other.trackId &&
          layer == other.layer;

  @override
  int get hashCode => Object.hash(trackId, layer);

  @override
  String toString() =>
      'AddTextLayerCommand(trackId: $trackId, layerId: ${layer.id}, subtitle: ${layer.subtitle})';
}

/// Pure command that replaces an existing text layer (text, style, timing, raster).
class UpdateTextLayerCommand implements EditCommand {
  final String trackId;
  final String layerId;
  final TextLayer updatedLayer;

  const UpdateTextLayerCommand({
    required this.trackId,
    required this.layerId,
    required this.updatedLayer,
  });

  @override
  String get name => 'text.update';

  @override
  CommandResult execute(ProjectDocument document) {
    _validateOverlayTrack(document, trackId);

    final track = document.tracks.firstWhere((t) => t.id == trackId);
    final index = track.textLayers.indexWhere((l) => l.id == layerId);
    if (index == -1) {
      throw ShadowError.invalidOperation(
        'Text layer "$layerId" not found on track "$trackId"',
      );
    }
    if (updatedLayer.id != layerId) {
      throw ShadowError.invalidOperation(
        'Updated layer id (${updatedLayer.id}) must match target ($layerId)',
      );
    }

    final previous = track.textLayers[index];
    final layers = List<TextLayer>.of(track.textLayers)..[index] = updatedLayer;

    final updatedTracks = List<Track>.of(document.tracks);
    updatedTracks[document.tracks.indexWhere((t) => t.id == trackId)] =
        track.copyWith(textLayers: layers);

    final newDoc = document.copyWith(tracks: updatedTracks);
    final inverse = UpdateTextLayerCommand(
      trackId: trackId,
      layerId: layerId,
      updatedLayer: previous,
    );

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdateTextLayerCommand &&
          runtimeType == other.runtimeType &&
          trackId == other.trackId &&
          layerId == other.layerId &&
          updatedLayer == other.updatedLayer;

  @override
  int get hashCode => Object.hash(trackId, layerId, updatedLayer);

  @override
  String toString() =>
      'UpdateTextLayerCommand(trackId: $trackId, layerId: $layerId)';
}

/// Pure command that removes a text layer from an overlay track.
class RemoveTextLayerCommand implements EditCommand {
  final String trackId;
  final String layerId;
  final TextLayer? removedLayer;

  const RemoveTextLayerCommand({
    required this.trackId,
    required this.layerId,
    this.removedLayer,
  });

  @override
  String get name => 'text.remove';

  @override
  CommandResult execute(ProjectDocument document) {
    final trackIndex = document.tracks.indexWhere((t) => t.id == trackId);
    if (trackIndex == -1) {
      throw ShadowError.invalidOperation('Track "$trackId" not found');
    }

    final track = document.tracks[trackIndex];
    final index = track.textLayers.indexWhere((l) => l.id == layerId);
    if (index == -1) {
      throw ShadowError.invalidOperation(
        'Text layer "$layerId" not found on track "$trackId"',
      );
    }

    final removed = track.textLayers[index];
    final layers = List<TextLayer>.of(track.textLayers)..removeAt(index);

    final updatedTracks = List<Track>.of(document.tracks);
    updatedTracks[trackIndex] = track.copyWith(textLayers: layers);

    final newDoc = document.copyWith(tracks: updatedTracks);
    final inverse = AddTextLayerCommand(trackId: trackId, layer: removed);

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoveTextLayerCommand &&
          runtimeType == other.runtimeType &&
          trackId == other.trackId &&
          layerId == other.layerId;

  @override
  int get hashCode => Object.hash(trackId, layerId);

  @override
  String toString() =>
      'RemoveTextLayerCommand(trackId: $trackId, layerId: $layerId)';
}

/// Pure command that attaches a rasterized RGBA rendering to a text layer.
///
/// Text rasterization is idempotent and content-addressed: the rasterizer
/// computes the raster from `text` + style, then this command records the
/// resulting URI/hash/size so the RenderGraph can reference it.
class SetTextLayerRasterCommand implements EditCommand {
  final String trackId;
  final String layerId;
  final String rasterUri;
  final String rasterHash;
  final int rasterWidth;
  final int rasterHeight;

  const SetTextLayerRasterCommand({
    required this.trackId,
    required this.layerId,
    required this.rasterUri,
    required this.rasterHash,
    required this.rasterWidth,
    required this.rasterHeight,
  });

  @override
  String get name => 'text.raster';

  @override
  CommandResult execute(ProjectDocument document) {
    final trackIndex = document.tracks.indexWhere((t) => t.id == trackId);
    if (trackIndex == -1) {
      throw ShadowError.invalidOperation('Track "$trackId" not found');
    }

    final track = document.tracks[trackIndex];
    final index = track.textLayers.indexWhere((l) => l.id == layerId);
    if (index == -1) {
      throw ShadowError.invalidOperation(
        'Text layer "$layerId" not found on track "$trackId"',
      );
    }
    if (rasterWidth <= 0 || rasterHeight <= 0) {
      throw ShadowError.invalidOperation(
        'Raster dimensions must be positive (got ${rasterWidth}x$rasterHeight)',
      );
    }

    final previous = track.textLayers[index];
    final updated = previous.copyWith(
      rasterUri: rasterUri,
      rasterHash: rasterHash,
      rasterWidth: rasterWidth,
      rasterHeight: rasterHeight,
    );
    final layers = List<TextLayer>.of(track.textLayers)..[index] = updated;

    final updatedTracks = List<Track>.of(document.tracks);
    updatedTracks[trackIndex] = track.copyWith(textLayers: layers);

    final newDoc = document.copyWith(tracks: updatedTracks);
    final inverse = previous.isRenderable
        ? SetTextLayerRasterCommand(
            trackId: trackId,
            layerId: layerId,
            rasterUri: previous.rasterUri!,
            rasterHash: previous.rasterHash!,
            rasterWidth: previous.rasterWidth,
            rasterHeight: previous.rasterHeight,
          )
        : UpdateTextLayerCommand(
            trackId: trackId,
            layerId: layerId,
            updatedLayer: previous,
          );

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetTextLayerRasterCommand &&
          runtimeType == other.runtimeType &&
          trackId == other.trackId &&
          layerId == other.layerId &&
          rasterUri == other.rasterUri &&
          rasterHash == other.rasterHash &&
          rasterWidth == other.rasterWidth &&
          rasterHeight == other.rasterHeight;

  @override
  int get hashCode =>
      Object.hash(trackId, layerId, rasterUri, rasterHash, rasterWidth, rasterHeight);

  @override
  String toString() =>
      'SetTextLayerRasterCommand(trackId: $trackId, layerId: $layerId, ${rasterWidth}x$rasterHeight)';
}

bool _overlaps(TextLayer a, TextLayer b) =>
    a.startTicks < b.endTicks && b.startTicks < a.endTicks;