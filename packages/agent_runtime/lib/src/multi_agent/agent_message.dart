import 'agent_role.dart';

/// Kinds of structured messages exchanged between agents.
enum AgentMessageType {
  task,
  observation,
  result,
  question,
  approvalRequested,
  approvalDecided,
  status;

  String get wireName => name;

  static AgentMessageType fromWireName(String value) {
    return AgentMessageType.values.firstWhere(
      (type) => type.wireName == value,
      orElse: () => AgentMessageType.observation,
    );
  }
}

/// A structured inter-agent message.
///
/// Messages are the only channel between agents: content is a JSON-serializable
/// map, never a provider-specific object, and never contains secrets.
class AgentMessage {
  const AgentMessage({
    required this.id,
    required this.taskId,
    required this.from,
    this.to,
    required this.type,
    required this.content,
    this.correlationId,
    required this.createdAt,
  });

  final String id;
  final String taskId;
  final AgentRole from;
  final AgentRole? to;
  final AgentMessageType type;
  final Map<String, Object?> content;
  final String? correlationId;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'task_id': taskId,
    'from': from.id,
    if (to != null) 'to': to!.id,
    'type': type.wireName,
    'content': content,
    if (correlationId != null) 'correlation_id': correlationId,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory AgentMessage.fromJson(Map<String, Object?> json) => AgentMessage(
    id: json['id'] as String,
    taskId: json['task_id'] as String,
    from: AgentRole.fromId(json['from'] as String) ?? AgentRole.projectManager,
    to: json['to'] == null ? null : AgentRole.fromId(json['to'] as String),
    type: AgentMessageType.fromWireName(
      json['type'] as String? ?? 'observation',
    ),
    content:
        (json['content'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{},
    correlationId: json['correlation_id'] as String?,
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
  );

  AgentMessage copyWith({
    AgentMessageType? type,
    Map<String, Object?>? content,
    AgentRole? to,
  }) {
    return AgentMessage(
      id: id,
      taskId: taskId,
      from: from,
      to: to ?? this.to,
      type: type ?? this.type,
      content: content ?? this.content,
      correlationId: correlationId,
      createdAt: createdAt,
    );
  }
}
