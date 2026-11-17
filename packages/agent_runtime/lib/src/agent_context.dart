import 'dart:convert';

/// Immutable per-task/project context snapshot inputs tracked by the runtime.
class AgentContext {
  AgentContext({
    required this.taskId,
    required this.workspaceRoot,
    required int projectRevision,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : _projectRevision = projectRevision,
       _metadata = Map<String, Object?>.unmodifiable(metadata);

  final String taskId;
  final String workspaceRoot;
  int _projectRevision;
  final Map<String, Object?> _metadata;

  int get projectRevision => _projectRevision;
  Map<String, Object?> get metadata => _metadata;

  void updateProjectRevision(int revision) {
    if (revision < 0) {
      throw ArgumentError.value(revision, 'revision', 'must be >= 0');
    }
    _projectRevision = revision;
  }

  /// Deterministic hash over task/workspace/revision/metadata for checkpoint binding.
  String get contextHash {
    final payload = <String, Object?>{
      'taskId': taskId,
      'workspaceRoot': workspaceRoot,
      'projectRevision': _projectRevision,
      'metadata': _metadata,
    };
    return _fnv1a64Hex(jsonEncode(_canonicalize(payload)));
  }

  AgentContext copyWith({
    int? projectRevision,
    Map<String, Object?>? metadata,
  }) {
    return AgentContext(
      taskId: taskId,
      workspaceRoot: workspaceRoot,
      projectRevision: projectRevision ?? _projectRevision,
      metadata: metadata ?? _metadata,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'taskId': taskId,
    'workspaceRoot': workspaceRoot,
    'projectRevision': _projectRevision,
    'metadata': _metadata,
    'contextHash': contextHash,
  };
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return <String, Object?>{for (final k in keys) k: _canonicalize(value[k])};
  }
  if (value is List) return value.map(_canonicalize).toList();
  return value;
}

String _fnv1a64Hex(String input) {
  const int fnvOffset = 0xcbf29ce484222325;
  const int fnvPrime = 0x100000001b3;
  const int mask64 = 0xFFFFFFFFFFFFFFFF;
  var hash = fnvOffset;
  for (final code in utf8.encode(input)) {
    hash ^= code;
    hash = (hash * fnvPrime) & mask64;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
