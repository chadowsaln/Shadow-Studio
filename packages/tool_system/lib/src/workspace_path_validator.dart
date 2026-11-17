import 'dart:io';

import 'package:shadow_contracts/shadow_contracts.dart';

/// Ensures paths stay within workspace and do not escape via symlinks (PERM_PATH_ESCAPE).
class WorkspacePathValidator {
  const WorkspacePathValidator();

  Future<void> validateWithinWorkspace({
    required String candidatePath,
    required String workspaceRoot,
    required bool mustExist,
    bool resolveSymlinks = true,
  }) async {
    final root = Directory(workspaceRoot).absolute;
    final rootResolved = resolveSymlinks && await root.exists() ? await root.resolveSymbolicLinks() : root.path;

    final candidate = FileSystemEntity.isDirectorySync(candidatePath)
        ? Directory(candidatePath)
        : File(candidatePath);
    final abs = candidate.absolute;

    if (mustExist) {
      if (!await FileSystemEntity.type(abs.path, followLinks: false).then((t) => t != FileSystemEntityType.notFound)) {
        // will be checked below by exists
      }
      final type = await FileSystemEntity.type(abs.path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        throw ToolPathException('Path does not exist');
      }
    }

    String resolved;
    try {
      if (await FileSystemEntity.type(abs.path, followLinks: false) != FileSystemEntityType.notFound) {
        resolved = await File(abs.path).resolveSymbolicLinks().catchError((_) async => Directory(abs.path).resolveSymbolicLinks());
      } else {
        // resolve parent for non-existent target
        final parent = abs.parent;
        final parentResolved = await parent.exists() ? await Directory(parent.path).resolveSymbolicLinks() : parent.absolute.path;
        resolved = '$parentResolved${Platform.pathSeparator}${abs.uri.pathSegments.isNotEmpty ? abs.uri.pathSegments.last : ''}';
      }
    } catch (_) {
      resolved = abs.path;
    }

    final normRoot = _normalize(rootResolved);
    final normResolved = _normalize(resolved);
    if (normResolved != normRoot && !normResolved.startsWith('$normRoot${Platform.pathSeparator}')) {
      throw ToolPathException('Path escapes workspace', code: ShadowErrorCode.permPathEscape);
    }
  }

  String _normalize(String p) => p.replaceAll(RegExp(r'/+'), '/').replaceAll(RegExp(r'\\+'), r'\').replaceAll(r'\', '/');
}

class ToolPathException implements Exception {
  ToolPathException(this.message, {this.code = ShadowErrorCode.permPathEscape});
  final String message;
  final String code;
  @override
  String toString() => message;
}
