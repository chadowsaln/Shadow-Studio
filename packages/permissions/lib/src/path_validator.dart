import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shadow_contracts/shadow_contracts.dart';

/// Canonical path validation: prevents traversal and symlink escapes.
class PathValidator {
  const PathValidator();

  /// Validates [targetPath] is within [workspaceRoot]. Throws [PathSecurityException] on escape.
  /// Uses canonical filesystem paths and resolves symlinks where possible.
  Future<String> canonicalizeWithinWorkspace({
    required String targetPath,
    required String workspaceRoot,
    bool mustExist = false,
  }) async {
    final rootCanonical = await _canonicalizeRoot(workspaceRoot);
    final resolved = await _resolveTarget(targetPath, rootCanonical, mustExist: mustExist);
    if (!_isWithin(rootCanonical, resolved)) {
      throw const PathSecurityException(
        code: ShadowErrorCode.permPathEscape,
        message: 'Path escapes workspace',
      );
    }
    return resolved;
  }

  Future<void> assertWithinWorkspace({
    required String targetPath,
    required String workspaceRoot,
    bool mustExist = false,
  }) async {
    await canonicalizeWithinWorkspace(
      targetPath: targetPath,
      workspaceRoot: workspaceRoot,
      mustExist: mustExist,
    );
  }

  Future<String> _canonicalizeRoot(String workspaceRoot) async {
    final dir = Directory(workspaceRoot);
    final abs = dir.isAbsolute ? dir : Directory(p.absolute(workspaceRoot));
    try {
      if (await abs.exists()) {
        return p.normalize(await abs.resolveSymbolicLinks());
      }
    } catch (_) {}
    return p.normalize(p.absolute(abs.path));
  }

  Future<String> _resolveTarget(String targetPath, String rootCanonical, {required bool mustExist}) async {
    final abs = p.isAbsolute(targetPath) ? p.normalize(targetPath) : p.normalize(p.join(rootCanonical, targetPath));
    final type = FileSystemEntity.typeSync(abs, followLinks: false);
    if (mustExist && type == FileSystemEntityType.notFound) {
      throw const PathSecurityException(
        code: ShadowErrorCode.permPathEscape,
        message: 'Path does not exist in workspace',
      );
    }

    // Reject symlink escapes: if any component/symlink resolves outside root.
    try {
      if (type == FileSystemEntityType.link) {
        final linkTarget = Link(abs).targetSync();
        final resolvedLink = p.isAbsolute(linkTarget) ? p.normalize(linkTarget) : p.normalize(p.join(p.dirname(abs), linkTarget));
        final canonicalLink = await _safeResolveExisting(resolvedLink);
        if (!_isWithin(rootCanonical, canonicalLink)) {
          throw const PathSecurityException(
            code: ShadowErrorCode.permPathEscape,
            message: 'Symlink escapes workspace',
          );
        }
        return canonicalLink;
      }
      if (type != FileSystemEntityType.notFound) {
        final canonical = await File(abs).resolveSymbolicLinks().catchError((_) => Directory(abs).resolveSymbolicLinks());
        return p.normalize(canonical);
      }
    } on PathSecurityException {
      rethrow;
    } catch (_) {
      // fall through to lexical+parent resolution
    }

    // For non-existent targets, resolve nearest existing ancestor to detect symlinked parent escapes.
    final ancestor = await _nearestExistingAncestor(abs);
    if (ancestor != null) {
      final canonicalAncestor = await _safeResolveExisting(ancestor);
      if (!_isWithin(rootCanonical, canonicalAncestor)) {
        throw const PathSecurityException(
          code: ShadowErrorCode.permPathEscape,
          message: 'Path traversal via symlink escapes workspace',
        );
      }
      final suffix = p.relative(abs, from: ancestor);
      final candidate = p.normalize(p.join(canonicalAncestor, suffix));
      if (!_isWithin(rootCanonical, candidate)) {
        throw const PathSecurityException(
          code: ShadowErrorCode.permPathEscape,
          message: 'Path traversal escapes workspace',
        );
      }
      return candidate;
    }

    final normalized = p.normalize(abs);
    if (!_isWithin(rootCanonical, normalized)) {
      throw const PathSecurityException(
        code: ShadowErrorCode.permPathEscape,
        message: 'Path traversal escapes workspace',
      );
    }
    return normalized;
  }

  Future<String?> _nearestExistingAncestor(String abs) async {
    var cur = abs;
    while (true) {
      final type = FileSystemEntity.typeSync(cur, followLinks: false);
      if (type != FileSystemEntityType.notFound) return cur;
      final parent = p.dirname(cur);
      if (parent == cur) return null;
      cur = parent;
    }
  }

  Future<String> _safeResolveExisting(String path) async {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      return p.normalize(await Directory(path).resolveSymbolicLinks());
    }
    if (type == FileSystemEntityType.file || type == FileSystemEntityType.link) {
      try {
        return p.normalize(await File(path).resolveSymbolicLinks());
      } catch (_) {
        return p.normalize(await Directory(path).resolveSymbolicLinks());
      }
    }
    return p.normalize(path);
  }

  bool _isWithin(String rootCanonical, String targetCanonical) {
    final root = p.normalize(rootCanonical);
    final target = p.normalize(targetCanonical);
    if (target == root) return true;
    final prefix = root.endsWith(p.separator) ? root : '$root${p.separator}';
    return target.startsWith(prefix);
  }
}

class PathSecurityException implements Exception {
  const PathSecurityException({required this.code, required this.message});
  final String code;
  final String message;
  @override
  String toString() => 'PathSecurityException($code): $message';
}
