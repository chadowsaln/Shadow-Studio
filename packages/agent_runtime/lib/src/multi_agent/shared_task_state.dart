import 'agent_message.dart';
import 'agent_role.dart';

/// Lifecycle of a shared task across the collaborating agents.
enum SharedTaskStatus {
  created,
  planning,
  inProgress,
  awaitingApproval,
  completed,
  failed,
  cancelled;

  String get wireName => name;

  bool get isTerminal =>
      this == completed || this == failed || this == cancelled;
}

/// Per-role progress on the shared task.
class AgentRoleState {
  const AgentRoleState({
    required this.role,
    this.status = 'idle',
    this.artifacts = const <String, Object?>{},
    this.lastMessageId,
  });

  final AgentRole role;
  final String status;
  final Map<String, Object?> artifacts;
  final String? lastMessageId;

  AgentRoleState copyWith({
    String? status,
    Map<String, Object?>? artifacts,
    String? lastMessageId,
  }) {
    return AgentRoleState(
      role: role,
      status: status ?? this.status,
      artifacts: artifacts ?? this.artifacts,
      lastMessageId: lastMessageId ?? this.lastMessageId,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'role': role.id,
    'status': status,
    'artifacts': artifacts,
    if (lastMessageId != null) 'last_message_id': lastMessageId,
  };
}

/// Shared task state visible to every agent.
///
/// All agents read and write through this object instead of private channels,
/// so the runtime has one auditable view of goal, progress, artifacts and
/// messages.
class SharedTaskState {
  SharedTaskState({
    required this.taskId,
    required this.goal,
    required this.workspaceRoot,
    required int projectRevision,
    SharedTaskStatus status = SharedTaskStatus.created,
  }) : _projectRevision = projectRevision,
       _status = status;

  final String taskId;
  final String goal;
  final String workspaceRoot;
  int _projectRevision;
  SharedTaskStatus _status;

  final Map<String, Object?> _artifacts = <String, Object?>{};
  final List<AgentMessage> _messages = <AgentMessage>[];
  final Map<AgentRole, AgentRoleState> _roles = <AgentRole, AgentRoleState>{};

  int get projectRevision => _projectRevision;
  SharedTaskStatus get status => _status;
  Map<String, Object?> get artifacts =>
      Map<String, Object?>.unmodifiable(_artifacts);
  List<AgentMessage> get messages => List<AgentMessage>.unmodifiable(_messages);

  AgentRoleState? roleState(AgentRole role) => _roles[role];

  void updateProjectRevision(int revision) {
    if (revision < 0) {
      throw ArgumentError.value(revision, 'revision', 'must be >= 0');
    }
    _projectRevision = revision;
  }

  void setStatus(SharedTaskStatus status) {
    _status = status;
  }

  void setArtifact(String key, Object? value) {
    _artifacts[key] = value;
  }

  void recordMessage(AgentMessage message) {
    _messages.add(message);
    final previous = _roles[message.from];
    _roles[message.from] = (previous ?? AgentRoleState(role: message.from))
        .copyWith(lastMessageId: message.id);
  }

  void updateRole(
    AgentRole role, {
    String? status,
    Map<String, Object?>? artifacts,
  }) {
    final previous = _roles[role] ?? AgentRoleState(role: role);
    _roles[role] = previous.copyWith(
      status: status,
      artifacts: artifacts == null
          ? null
          : <String, Object?>{...previous.artifacts, ...artifacts},
    );
  }

  /// Merges artifacts carried by [message] into the shared state.
  void absorbArtifacts(AgentMessage message) {
    final raw = message.content['artifacts'];
    if (raw is Map) {
      raw.forEach((key, value) {
        _artifacts[key.toString()] = value;
      });
    }
    final role = message.from;
    final previous = _roles[role] ?? AgentRoleState(role: role);
    _roles[role] = previous.copyWith(
      artifacts: raw is Map ? <String, Object?>{...previous.artifacts} : null,
      lastMessageId: message.id,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'task_id': taskId,
    'goal': goal,
    'workspace_root': workspaceRoot,
    'project_revision': _projectRevision,
    'status': _status.wireName,
    'artifacts': _artifacts,
    'roles': <String, Object?>{
      for (final entry in _roles.entries) entry.key.id: entry.value.toJson(),
    },
    'messages': _messages.map((message) => message.toJson()).toList(),
  };
}
