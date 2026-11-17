import 'path_validator.dart';

/// Guards workspace boundaries and path arguments for tool/file operations.
class WorkspaceGuard {
  WorkspaceGuard({PathValidator? pathValidator}) : _validator = pathValidator ?? const PathValidator();

  final PathValidator _validator;

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

  /// Extracts and validates all path-like arguments. Rejects on first unauthorized path.
  Future<void> validateArgumentsPaths({
    required Map<String, Object?> arguments,
    required String workspaceRoot,
  }) async {
    final paths = collectPathValues(arguments);
    for (final path in paths) {
      await ensurePathAllowed(path: path, workspaceRoot: workspaceRoot);
    }
  }

  /// Collects values for keys that represent filesystem paths.
  List<String> collectPathValues(Map<String, Object?> arguments) {
    const pathKeys = <String>{
      'path', 'file_path', 'filePath', 'project_path', 'projectPath', 'project',
      'source', 'sourcePath', 'source_path', 'target', 'targetPath', 'target_path',
      'destination', 'destinationPath', 'destination_path', 'dir', 'directory',
      'workspace', 'output', 'outputPath', 'output_path', 'media_path', 'mediaPath',
    };
    final out = <String>[];
    void walk(Object? value, [String? key]) {
      if (key != null && pathKeys.contains(key) && value is String && value.trim().isNotEmpty) {
        out.add(value);
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
}
