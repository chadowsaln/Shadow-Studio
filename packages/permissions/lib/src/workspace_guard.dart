import 'package:shadow_contracts/shadow_contracts.dart';

import 'path_validator.dart';

/// Guards workspace boundaries and path arguments for tool/file operations.
///
/// Path detection is deny-by-default:
/// * any argument whose name contains a path word (`path`, `dir`, `file`,
///   `folder`, `uri`, `source`, `target`, `destination`, `output`, `workspace`)
///   is validated, including camelCase variants;
/// * any string value that *looks* like a filesystem path (absolute POSIX /
///   Windows path, or contains a `..` segment) is validated even under an
///   unexpected key, so a model cannot smuggle a path through a rename;
/// * control characters (including NUL) are rejected in all string values.
class WorkspaceGuard {
  WorkspaceGuard({PathValidator? pathValidator})
    : _validator = pathValidator ?? const PathValidator();

  final PathValidator _validator;

  /// Keys that always name a filesystem path.
  static final RegExp _strongPathKeyPattern = RegExp(
    r'(^|_)(path|paths|dir|dirs|directory|directories|file|files|folder|folders|uri|workspace|root)(_|$)',
    caseSensitive: false,
  );

  /// Keys that are paths only when the value is path-shaped. `target` and
  /// `source` are frequently track/asset identifiers (`target: "main"`), and
  /// `output` may be a format; rewriting those into absolute paths would corrupt
  /// otherwise valid tool calls.
  static final RegExp _ambiguousPathKeyPattern = RegExp(
    r'(^|_)(source|target|destination|output)(_|$)',
    caseSensitive: false,
  );

  static final RegExp _fileExtensionPattern = RegExp(r'\.[A-Za-z0-9]{1,8}$');

  static final RegExp _controlChars = RegExp(
    r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]',
  );
  static final RegExp _windowsAbsolute = RegExp(r'^[A-Za-z]:[\\/]');
  static final RegExp _uncPath = RegExp(r'^[\\/]{2}[^\\/]+[\\/]');

  Future<void> ensurePathAllowed({
    required String path,
    required String workspaceRoot,
    bool mustExist = false,
  }) async {
    await _validator.assertWithinWorkspace(
      targetPath: path,
      workspaceRoot: workspaceRoot,
      mustExist: mustExist,
    );
  }

  /// Extracts and validates all path-like arguments. Rejects on the first
  /// unauthorized path. Also rejects malformed (control-character) strings.
  Future<void> validateArgumentsPaths({
    required Map<String, Object?> arguments,
    required String workspaceRoot,
  }) async {
    await resolveArgumentPaths(
      arguments: arguments,
      workspaceRoot: workspaceRoot,
    );
  }

  /// Validates every path-like argument and returns a structurally identical
  /// map whose path values are **canonical absolute paths**.
  ///
  /// Executors must pass this map to the tool: validating a relative path
  /// against the workspace root and then letting the tool resolve it against
  /// the process CWD would be a boundary bypass. Nested maps and lists are
  /// preserved.
  Future<Map<String, Object?>> resolveArgumentPaths({
    required Map<String, Object?> arguments,
    required String workspaceRoot,
  }) async {
    _assertNoControlCharacters(arguments);

    Future<Object?> walk(Object? value, [String? key]) async {
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) return value;
        if (_shouldResolveAsPath(key, trimmed)) {
          return _validator.canonicalizeWithinWorkspace(
            targetPath: trimmed,
            workspaceRoot: workspaceRoot,
          );
        }
        return value;
      }
      if (value is Map) {
        final out = <String, Object?>{};
        for (final entry in value.entries) {
          final childKey = entry.key.toString();
          out[childKey] = await walk(entry.value, childKey);
        }
        return out;
      }
      if (value is List) {
        final out = <Object?>[];
        for (final item in value) {
          out.add(await walk(item, key));
        }
        return out;
      }
      return value;
    }

    final resolved = await walk(arguments);
    return resolved as Map<String, Object?>;
  }

  /// Collects values that must be treated as filesystem paths.
  List<String> collectPathValues(Map<String, Object?> arguments) {
    final out = <String>[];
    void walk(Object? value, [String? key]) {
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) return;
        if (_shouldResolveAsPath(key, trimmed)) {
          out.add(trimmed);
        }
        return;
      }
      if (value is Map) {
        for (final entry in value.entries) {
          walk(entry.value, entry.key.toString());
        }
      } else if (value is List) {
        for (final item in value) {
          walk(item, key);
        }
      }
    }

    walk(arguments);
    return out;
  }

  void _assertNoControlCharacters(Object? value) {
    void walk(Object? node) {
      if (node is String) {
        if (_controlChars.hasMatch(node)) {
          throw const PathSecurityException(
            code: ShadowErrorCode.permInvalidArgument,
            message: 'Argument contains control characters',
          );
        }
        return;
      }
      if (node is Map) {
        for (final entry in node.entries) {
          final k = entry.key.toString();
          if (_controlChars.hasMatch(k)) {
            throw const PathSecurityException(
              code: ShadowErrorCode.permInvalidArgument,
              message: 'Argument name contains control characters',
            );
          }
          walk(entry.value);
        }
      } else if (node is List) {
        for (final item in node) {
          walk(item);
        }
      }
    }

    walk(value);
  }

  bool _shouldResolveAsPath(String? key, String value) {
    if (_looksLikePath(value)) return true;
    if (key == null) return false;
    final snake = _snakeCase(key);
    if (_strongPathKeyPattern.hasMatch(snake)) return true;
    if (!_ambiguousPathKeyPattern.hasMatch(snake)) return false;
    // Ambiguous keys: only unambiguous file/path shapes. A plain identifier
    // such as "main" stays untouched; `assets/ad.mp4` or `clip.mp4` does not.
    return value.contains('/') ||
        value.contains(r'\') ||
        _fileExtensionPattern.hasMatch(value);
  }

  String _snakeCase(String key) => key
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
      .toLowerCase();

  bool _looksLikePath(String value) {
    if (value.startsWith('/')) return true;
    if (_windowsAbsolute.hasMatch(value)) return true;
    if (_uncPath.hasMatch(value)) return true;
    final unified = value.replaceAll(r'\', '/');
    return unified.split('/').contains('..');
  }
}
