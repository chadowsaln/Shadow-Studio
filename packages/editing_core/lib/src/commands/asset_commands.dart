import '../error/shadow_error.dart';
import '../model/asset.dart';
import '../model/project_document.dart';
import 'edit_command.dart';

/// Pure command to add an asset to the document's asset map.
class AddAssetCommand implements EditCommand {
  final Asset asset;

  const AddAssetCommand(this.asset);

  @override
  String get name => 'asset.add';

  @override
  CommandResult execute(ProjectDocument document) {
    if (document.assets.containsKey(asset.id)) {
      throw ShadowError.invalidOperation(
        'Asset with ID "${asset.id}" already exists in project document',
      );
    }

    final updatedAssets = Map<String, Asset>.of(document.assets)..[asset.id] = asset;
    final newDoc = document.copyWith(assets: updatedAssets);
    final inverse = RemoveAssetCommand(assetId: asset.id, removedAsset: asset);

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AddAssetCommand &&
          runtimeType == other.runtimeType &&
          asset == other.asset;

  @override
  int get hashCode => asset.hashCode;

  @override
  String toString() => 'AddAssetCommand(assetId: ${asset.id})';
}

/// Pure command to remove an asset from the document's asset map.
class RemoveAssetCommand implements EditCommand {
  final String assetId;
  final Asset? removedAsset;

  const RemoveAssetCommand({
    required this.assetId,
    this.removedAsset,
  });

  @override
  String get name => 'asset.remove';

  @override
  CommandResult execute(ProjectDocument document) {
    final targetAsset = document.assets[assetId];
    if (targetAsset == null) {
      throw ShadowError.invalidOperation(
        'Asset with ID "$assetId" not found in project document',
      );
    }

    // Verify no clips currently reference this asset
    for (final track in document.tracks) {
      for (final clip in track.clips) {
        if (clip.assetId == assetId) {
          throw ShadowError.invalidOperation(
            'Cannot remove asset "$assetId": referenced by clip "${clip.id}" on track "${track.id}"',
          );
        }
      }
    }

    final updatedAssets = Map<String, Asset>.of(document.assets)..remove(assetId);
    final newDoc = document.copyWith(assets: updatedAssets);
    final inverse = AddAssetCommand(targetAsset);

    return CommandResult(document: newDoc, inverse: inverse);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoveAssetCommand &&
          runtimeType == other.runtimeType &&
          assetId == other.assetId;

  @override
  int get hashCode => assetId.hashCode;

  @override
  String toString() => 'RemoveAssetCommand(assetId: $assetId)';
}
