import 'dart:io';

import 'package:shadow_contracts/shadow_contracts.dart';

/// Port for project lifecycle operations not covered by core [EditingService].
/// Implementations may be backed by local storage/project-file services; tests use mocks.
abstract interface class ProjectLifecycleService {
  /// Creates a new project inside workspace and returns its path and initial revision.
  Future<({String projectPath, String projectId, int revision})> createProject({
    required String workspaceRoot,
    required String name,
  });

  /// Opens an existing project path inside workspace.
  Future<ProjectDocument> openProject({
    required String workspaceRoot,
    required String projectPath,
  });

  EditingService get editing;
}

/// Port for environment/capability info (no shell, no native engine access).
abstract interface class EnvironmentInfoService {
  Future<Map<String, Object?>> getSystemInfo();
  Future<Map<String, Object?>> inspectCapabilities();
}

/// Port for media metadata/probe cache. No native probing in tool layer.
abstract interface class MediaMetadataService {
  Future<Map<String, Object?>>? getCachedMetadata(String workspaceRelativeOrAbsolutePath);
  Future<List<Map<String, Object?>>> scanMedia({
    required String workspaceRoot,
    String? directory,
  });
}

/// Simple local environment info (safe, no shell execution).
class LocalEnvironmentInfoService implements EnvironmentInfoService {
  const LocalEnvironmentInfoService();

  @override
  Future<Map<String, Object?>> getSystemInfo() async {
    return <String, Object?>{
      'os': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'dartVersion': Platform.version,
      'processors': Platform.numberOfProcessors,
      'locale': Platform.localeName,
      'executable': 'dart', // no shell; reports runtime kind only
    };
  }

  @override
  Future<Map<String, Object?>> inspectCapabilities() async {
    return <String, Object?>{
      'platform': Platform.operatingSystem,
      'isDesktop': Platform.isLinux || Platform.isWindows || Platform.isMacOS,
      'supportsLocalFiles': true,
      'mediaWorkerAvailable': false, // unknown without native bridge; reported honestly
      'codecs': const <String>[],
      'gpu': const <String, Object?>{'available': false},
      'note': 'Capability probe is static in tool layer; native media engine not queried.',
    };
  }
}

/// File-system based media scanner/metadata reader (reads sidecar/cache files only).
class FileSystemMediaMetadataService implements MediaMetadataService {
  const FileSystemMediaMetadataService();

  static const _mediaExts = {'.mp4', '.mov', '.mkv', '.avi', '.webm', '.mp3', '.wav', '.aac', '.flac', '.m4a', '.png', '.jpg', '.jpeg', '.webp', '.gif'};

  @override
  Future<Map<String, Object?>>? getCachedMetadata(String path) async {
    final f = File(path);
    if (!await f.exists()) {
      return <String, Object?>{'path': path, 'found': false};
    }
    final stat = await f.stat();
    final metaPath = '$path.metadata.json';
    final metaFile = File(metaPath);
    Map<String, Object?> cached = const <String, Object?>{};
    if (await metaFile.exists()) {
      try {
        final txt = await metaFile.readAsString();
        // keep as raw-ish fields; caller validates. avoid importing dart:convert heavily here? fine.
        cached = <String, Object?>{'sidecar': txt};
      } catch (_) {}
    }
    return <String, Object?>{
      'path': path,
      'found': true,
      'sizeBytes': stat.size,
      'modified': stat.modified.toUtc().toIso8601String(),
      'extension': _ext(path),
      'cached': cached.isNotEmpty,
      'metadata': cached,
    };
  }

  @override
  Future<List<Map<String, Object?>>> scanMedia({required String workspaceRoot, String? directory}) async {
    final root = Directory(directory ?? workspaceRoot);
    if (!await root.exists()) return const <Map<String, Object?>>[];
    final results = <Map<String, Object?>>[];
    await for (final ent in root.list(recursive: false, followLinks: false)) {
      if (ent is! File) continue;
      final ext = _ext(ent.path).toLowerCase();
      if (!_mediaExts.contains(ext)) continue;
      final stat = await ent.stat();
      results.add(<String, Object?>{
        'path': ent.path,
        'name': ent.uri.pathSegments.isNotEmpty ? ent.uri.pathSegments.last : ent.path,
        'extension': ext,
        'sizeBytes': stat.size,
        'modified': stat.modified.toUtc().toIso8601String(),
      });
    }
    results.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return results;
  }

  static String _ext(String path) {
    final i = path.lastIndexOf('.');
    return i >= 0 ? path.substring(i) : '';
  }
}
