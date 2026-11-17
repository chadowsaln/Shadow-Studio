import 'package:meta/meta.dart';

import 'agent_models.dart';
import 'agent_plan.dart';

/// A durable snapshot of agent execution, used to resume an interrupted task.
///
/// Checkpoints are written after every tool call. They bind the plan to the
/// project revision and workspace so a resume can be validated before replay.
@immutable
class AgentCheckpoint {
  const AgentCheckpoint({
    required this.taskId,
    required this.sequence,
    required this.createdAt,
    required this.contextHash,
    required this.projectRevision,
    required this.workspaceRoot,
    required this.plan,
    required this.toolCallCount,
    required this.pendingStepId,
    this.lastToolName,
    this.lastToolIdempotent,
    this.lastToolArgumentsHash,
    this.state = AgentTaskState.acting,
  });

  final String taskId;
  final int sequence;
  final DateTime createdAt;
  final String contextHash;
  final int projectRevision;
  final String workspaceRoot;
  final AgentPlan plan;
  final int toolCallCount;
  final String? pendingStepId;
  final String? lastToolName;
  final bool? lastToolIdempotent;
  final String? lastToolArgumentsHash;
  final AgentTaskState state;

  Map<String, Object?> toJson() => <String, Object?>{
    'taskId': taskId,
    'sequence': sequence,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'contextHash': contextHash,
    'projectRevision': projectRevision,
    'workspaceRoot': workspaceRoot,
    'plan': plan.toJson(),
    'toolCallCount': toolCallCount,
    if (pendingStepId != null) 'pendingStepId': pendingStepId,
    if (lastToolName != null) 'lastToolName': lastToolName,
    if (lastToolIdempotent != null) 'lastToolIdempotent': lastToolIdempotent,
    if (lastToolArgumentsHash != null)
      'lastToolArgumentsHash': lastToolArgumentsHash,
    'state': state.name,
  };

  static AgentTaskState _stateFromJson(Object? value) {
    if (value is String) {
      for (final s in AgentTaskState.values) {
        if (s.name == value) return s;
      }
    }
    return AgentTaskState.acting;
  }

  static AgentCheckpoint fromJson(Map<String, Object?> json) {
    final rawPlan = json['plan'];
    final plan = rawPlan is Map
        ? AgentPlan.fromJson(rawPlan.map((k, v) => MapEntry(k.toString(), v)))
        : const AgentPlan(steps: <PlanStep>[], revision: 0);
    return AgentCheckpoint(
      taskId: json['taskId'] as String,
      sequence: json['sequence'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      contextHash: json['contextHash'] as String,
      projectRevision: json['projectRevision'] as int,
      workspaceRoot: json['workspaceRoot'] as String,
      plan: plan,
      toolCallCount: json['toolCallCount'] as int? ?? 0,
      pendingStepId: json['pendingStepId'] as String?,
      lastToolName: json['lastToolName'] as String?,
      lastToolIdempotent: json['lastToolIdempotent'] as bool?,
      lastToolArgumentsHash: json['lastToolArgumentsHash'] as String?,
      state: _stateFromJson(json['state']),
    );
  }
}

/// Persistence port for [AgentCheckpoint]s.
abstract interface class CheckpointStore {
  Future<void> save(AgentCheckpoint checkpoint);
  Future<AgentCheckpoint?> latest(String taskId);
  Future<void> clear(String taskId);
}
