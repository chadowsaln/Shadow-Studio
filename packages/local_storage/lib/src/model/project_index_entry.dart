import 'package:meta/meta.dart';

/// Project entry stored in the rebuildable app-level index database (`projects_index.db`).
@immutable
class ProjectIndexEntry {
  final String projectId;
  final String name;
  final String filePath;
  final int revision;
  final int durationTicks;
  final String? thumbnailUri;
  final int lastModifiedMs;
  final String createdAt;
  final String updatedAt;

  const ProjectIndexEntry({
    required this.projectId,
    required this.name,
    required this.filePath,
    required this.revision,
    required this.durationTicks,
    this.thumbnailUri,
    required this.lastModifiedMs,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectIndexEntry &&
          runtimeType == other.runtimeType &&
          projectId == other.projectId &&
          name == other.name &&
          filePath == other.filePath &&
          revision == other.revision &&
          durationTicks == other.durationTicks &&
          thumbnailUri == other.thumbnailUri &&
          lastModifiedMs == other.lastModifiedMs &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        projectId,
        name,
        filePath,
        revision,
        durationTicks,
        thumbnailUri,
        lastModifiedMs,
        createdAt,
        updatedAt,
      );

  @override
  String toString() =>
      'ProjectIndexEntry(id: $projectId, name: "$name", path: $filePath, rev: $revision)';
}
