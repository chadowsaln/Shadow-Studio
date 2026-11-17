import 'package:meta/meta.dart';

/// Data payload stored inside a `.ssproj` SQLite project file.
///
/// Contains the canonical document JSON snapshot and metadata.
@immutable
class ProjectFileData {
  final String projectId;
  final String name;
  final int schemaVersion;
  final int revision;
  final String documentJson;
  final String createdAt;
  final String updatedAt;

  const ProjectFileData({
    required this.projectId,
    required this.name,
    required this.schemaVersion,
    required this.revision,
    required this.documentJson,
    required this.createdAt,
    required this.updatedAt,
  });

  ProjectFileData copyWith({
    String? projectId,
    String? name,
    int? schemaVersion,
    int? revision,
    String? documentJson,
    String? createdAt,
    String? updatedAt,
  }) {
    return ProjectFileData(
      projectId: projectId ?? this.projectId,
      name: name ?? this.name,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      revision: revision ?? this.revision,
      documentJson: documentJson ?? this.documentJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectFileData &&
          runtimeType == other.runtimeType &&
          projectId == other.projectId &&
          name == other.name &&
          schemaVersion == other.schemaVersion &&
          revision == other.revision &&
          documentJson == other.documentJson &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        projectId,
        name,
        schemaVersion,
        revision,
        documentJson,
        createdAt,
        updatedAt,
      );

  @override
  String toString() =>
      'ProjectFileData(id: $projectId, name: "$name", rev: $revision, schema: $schemaVersion)';
}
