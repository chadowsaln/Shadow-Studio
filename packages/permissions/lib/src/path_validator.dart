import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shadow_contracts/shadow_contracts.dart';

/// Canonical path validation: prevents traversal and symlink escapes.
///
/// Invariants:
/// * the workspace root must exist and be a directory (fail closed);
/// * relative inputs resolve against the workspace root, never the process CWD;
/// * `..` segments are rejected lexically (both `/` and `\`), before any
///   filesystem resolution;
/// * existing targets are resolved via `resolveSymbolicLinks`, and non-existent
///   targets are resolved through their nearest existing ancestor, so a
///   symlinked parent cannot be used to escape;
/// * NUL bytes and empty paths are rejected.
class PathValidator {
  const PathValidator();

  /// Validates [targetPath] is within [workspaceRoot]. Throws
  /// [PathSecurityException] on escape or unusable input.
  Future<String> canonicalizeWithinWorkspace({
    required String targetPath,
    required String workspaceRoot,
    bool mustExist = false,
  }) async {
    final rootCanonical = await _canonicalizeRoot(workspaceRoot);
    final resolved = await _resolveTarget(
      targetPath,
      rootCanonical,
      mustExist: mustExist,
    );
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
    if (workspaceRoot.trim().isEmpty || workspaceRoot.contains('\u0000')) {
      throw const PathSecurityException(
        code: ShadowErrorCode.permPathEscape,
        message: 'Invalid workspace root',
      );
    }
    final abs = p.normalize(p.absolute(workspaceRoot));
    final type = await FileSystemEntity.type(abs, followLinks: true);
    if (type != FileSystemEntityType.directory) {
      // Fail closed: an unresolvable workspace root would make every
      // containment check meaningless.
      throw const PathSecurityException(
        code: ShadowErrorCode.permPathEscape,
        message: 'Workspace root must be an existing directory',
      );
    }
    try {
      return p.normalize(await Directory(abs).resolveSymbolicLinks());
    } on FileSystemException {
      throw const PathSecurityException(
        code: ShadowErrorCode.permPathEscape,
        message: 'Workspace root cannot be canonicalized',
      );
    }
  }

  Future<String> _resolveTarget(
    String targetPath,
    String rootCanonical, {
    required bool mustExist,
  }) async {
    if (targetPath.isEmpty || targetPath.contains('\u0000')) {
      throw const PathSecurityException(
        code: ShadowErrorCode.permInvalidArgument,
        message: 'Path is empty or contains a NUL byte',
      );
    }
    if (_hasParentTraversal(targetPath)) {
      throw const PathSecurityException(
        code: ShadowErrorCode.permPathEscape,
        message: 'Path traversal is not allowed',
      );
    }

    final abs = p.isAbsolute(targetPath)
        ? p.normalize(targetPath)
        : p.normalize(p.join(rootCanonical, targetPath));
    final type = FileSystemEntity.typeSync(abs, followLinks: false);
    if (mustExist && type == FileSystemEntityType.notFound) {
      throw const PathSecurityException(
        code: ShadowErrorCode.permPathEscape,
        message: 'Path does not exist in workspace',
      );
    }

    // Existing symlink: validate its target, never follow blindly.
    if (type == FileSystemEntityType.link) {
      final linkTarget = Link(abs).targetSync();
      final resolvedLink = p.isAbsolute(linkTarget)
          ? p.normalize(linkTarget)
          : p.normalize(p.join(p.dirname(abs), linkTarget));
      final canonicalLink = await _safeResolveExisting(resolvedLink);
      if (!_isWithin(rootCanonical, canonicalLink)) {
        throw const PathSecurityException(
          code: ShadowErrorCode.permPathEscape,
          message: 'Symlink escapes workspace',
        );
      }
      return canonicalLink;
    }

    // Existing file/directory.
    if (type != FileSystemEntityType.notFound) {
      try {
        return p.normalize(await File(abs).resolveSymbolicLinks());
      } on FileSystemException {
        try {
          return p.normalize(await Directory(abs).resolveSymbolicLinks());
        } on FileSystemException {
          // Fall through to ancestor-based resolution; never silently trust.
        }
      }
    }

    // Non-existent target: resolve the nearest existing ancestor so a symlinked
    // parent cannot point outside the workspace.
    final ancestor = _nearestExistingAncestor(abs);
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

    if (!_isWithin(rootCanonical, abs)) {
      throw const PathSecurityException(
        code: ShadowErrorCode.permPathEscape,
        message: 'Path traversal escapes workspace',
      );
    }
    return abs;
  }

  /// Rejects `..` as a lexical segment regardless of platform separators.
  bool _hasParentTraversal(String path) {
    final unified = path.replaceAll(r'\', '/');
    return unified.split('/').contains('..');
  }

  String? _nearestExistingAncestor(String abs) {
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
    if (type == FileSystemEntityType.file ||
        type == FileSystemEntityType.link) {
      try {
        return p.normalize(await File(path).resolveSymbolicLinks());
      } on FileSystemException {
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
