class RangeTicks {
  const RangeTicks({required this.start, required this.end});
  final int start;
  final int end;

  Map<String, Object?> toJson() => {'start': start, 'end': end};
}

class EditOperation {
  const EditOperation({
    required this.type,
    required this.target,
    this.payload = const <String, Object?>{},
  });

  final String type;
  final String target;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        'target': target,
        'payload': payload,
      };
}

class EditTransaction {
  const EditTransaction({
    required this.operations,
    this.label,
    this.metadata = const <String, Object?>{},
  });

  final List<EditOperation> operations;
  final String? label;
  final Map<String, Object?> metadata;
}

class EditOutcome {
  const EditOutcome({
    required this.revision,
    required this.applied,
    this.events = const <Object?>[],
  });

  final int revision;
  final List<EditOperation> applied;
  final List<Object?> events;
}

/// Opaque project document handle; concrete structure owned by Editing Core.
abstract interface class ProjectDocument {
  String get id;
  int get revision;
}

abstract interface class EditingService {
  int get revision;

  Future<ProjectDocument> openProject(String path);

  Future<EditOutcome> apply(
    EditTransaction transaction, {
    required int expectedRevision,
  });

  Future<EditOutcome> undo({required int expectedRevision});
  Future<EditOutcome> redo({required int expectedRevision});
  Future<void> save();

  /// Returns resolved RenderGraph JSON according to inherited v1 RenderGraph contract.
  Future<Map<String, Object?>> resolveGraph({
    required int revision,
    required RangeTicks range,
  });
}

class ProjectSnapshot {
  const ProjectSnapshot({
    required this.projectId,
    required this.name,
    required this.revision,
    required this.workspaceRoot,
    this.selectedItemId,
    this.metadata = const <String, Object?>{},
  });

  final String projectId;
  final String name;
  final int revision;
  final String workspaceRoot;
  final String? selectedItemId;
  final Map<String, Object?> metadata;
}
