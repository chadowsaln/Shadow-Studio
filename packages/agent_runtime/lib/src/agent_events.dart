import 'package:shadow_contracts/shadow_contracts.dart';
import 'planner.dart';

/// Typed UI-facing events (plans/progress/tool activity/results only, no CoT).
sealed class AgentRuntimeEvent {
  const AgentRuntimeEvent({
    required this.taskId,
    required this.timestamp,
  });

  final String taskId;
  final DateTime timestamp;

  Map<String, Object?> toJson();
}

class TaskStarted extends AgentRuntimeEvent {
  const TaskStarted({
    required super.taskId,
    required super.timestamp,
    required this.request,
    required this.workspaceRoot,
    required this.projectRevision,
  });
  final String request;
  final String workspaceRoot;
  final int projectRevision;
  @override
  Map<String, Object?> toJson() => {
        'type': 'TaskStarted',
        'taskId': taskId,
        'timestamp': timestamp.toIso8601String(),
        'request': request,
        'workspaceRoot': workspaceRoot,
        'projectRevision': projectRevision,
      };
}

class PlanUpdated extends AgentRuntimeEvent {
  const PlanUpdated({
    required super.taskId,
    required super.timestamp,
    required this.steps,
    required this.revision,
    this.reason,
  });
  final List<PlanStep> steps;
  final int revision;
  final String? reason;
  @override
  Map<String, Object?> toJson() => {
        'type': 'PlanUpdated',
        'taskId': taskId,
        'timestamp': timestamp.toIso8601String(),
        'revision': revision,
        if (reason != null) 'reason': reason,
        'steps': steps.map((s) => s.toJson()).toList(),
      };
}

class StepStarted extends AgentRuntimeEvent {
  const StepStarted({
    required super.taskId,
    required super.timestamp,
    required this.stepId,
    required this.description,
    required this.index,
  });
  final String stepId;
  final String description;
  final int index;
  @override
  Map<String, Object?> toJson() => {
        'type': 'StepStarted',
        'taskId': taskId,
        'timestamp': timestamp.toIso8601String(),
        'stepId': stepId,
        'description': description,
        'index': index,
      };
}

class ToolCallRequested extends AgentRuntimeEvent {
  const ToolCallRequested({
    required super.taskId,
    required super.timestamp,
    required this.callId,
    required this.toolName,
    required this.arguments,
    required this.stepId,
  });
  final String callId;
  final String toolName;
  final Map<String, Object?> arguments;
  final String stepId;
  @override
  Map<String, Object?> toJson() => {
        'type': 'ToolCallRequested',
        'taskId': taskId,
        'timestamp': timestamp.toIso8601String(),
        'callId': callId,
        'toolName': toolName,
        'arguments': arguments,
        'stepId': stepId,
      };
}

class ToolExecutionStarted extends AgentRuntimeEvent {
  const ToolExecutionStarted({
    required super.taskId,
    required super.timestamp,
    required this.callId,
    required this.toolName,
    required this.attempt,
  });
  final String callId;
  final String toolName;
  final int attempt;
  @override
  Map<String, Object?> toJson() => {
        'type': 'ToolExecutionStarted',
        'taskId': taskId,
        'timestamp': timestamp.toIso8601String(),
        'callId': callId,
        'toolName': toolName,
        'attempt': attempt,
      };
}

class ToolExecutionCompleted extends AgentRuntimeEvent {
  const ToolExecutionCompleted({
    required super.taskId,
    required super.timestamp,
    required this.callId,
    required this.toolName,
    required this.result,
    required this.attempt,
  });
  final String callId;
  final String toolName;
  final ToolResult result;
  final int attempt;
  @override
  Map<String, Object?> toJson() => {
        'type': 'ToolExecutionCompleted',
        'taskId': taskId,
        'timestamp': timestamp.toIso8601String(),
        'callId': callId,
        'toolName': toolName,
        'attempt': attempt,
        'result': result.toJson(),
      };
}

class ApprovalRequested extends AgentRuntimeEvent {
  const ApprovalRequested({
    required super.taskId,
    required super.timestamp,
    required this.callId,
    required this.toolName,
    required this.arguments,
    required this.riskLevel,
    this.reason,
  });
  final String callId;
  final String toolName;
  final Map<String, Object?> arguments;
  final ToolRiskLevel riskLevel;
  final String? reason;
  @override
  Map<String, Object?> toJson() => {
        'type': 'ApprovalRequested',
        'taskId': taskId,
        'timestamp': timestamp.toIso8601String(),
        'callId': callId,
        'toolName': toolName,
        'arguments': arguments,
        'riskLevel': riskLevel.name,
        if (reason != null) 'reason': reason,
      };
}

class TaskProgress extends AgentRuntimeEvent {
  const TaskProgress({
    required super.taskId,
    required super.timestamp,
    required this.message,
    this.completedSteps = 0,
    this.totalSteps = 0,
    this.toolCallsUsed = 0,
  });
  final String message;
  final int completedSteps;
  final int totalSteps;
  final int toolCallsUsed;
  @override
  Map<String, Object?> toJson() => {
        'type': 'TaskProgress',
        'taskId': taskId,
        'timestamp': timestamp.toIso8601String(),
        'message': message,
        'completedSteps': completedSteps,
        'totalSteps': totalSteps,
        'toolCallsUsed': toolCallsUsed,
      };
}

class TaskCompleted extends AgentRuntimeEvent {
  const TaskCompleted({
    required super.taskId,
    required super.timestamp,
    required this.summary,
    this.result = const <String, Object?>{},
  });
  final String summary;
  final Map<String, Object?> result;
  @override
  Map<String, Object?> toJson() => {
        'type': 'TaskCompleted',
        'taskId': taskId,
        'timestamp': timestamp.toIso8601String(),
        'summary': summary,
        'result': result,
      };
}

class TaskFailed extends AgentRuntimeEvent {
  const TaskFailed({
    required super.taskId,
    required super.timestamp,
    required this.code,
    required this.message,
    this.retryable = false,
  });
  final String code;
  final String message;
  final bool retryable;
  @override
  Map<String, Object?> toJson() => {
        'type': 'TaskFailed',
        'taskId': taskId,
        'timestamp': timestamp.toIso8601String(),
        'code': code,
        'message': message,
        'retryable': retryable,
      };
}

class TaskCancelled extends AgentRuntimeEvent {
  const TaskCancelled({
    required super.taskId,
    required super.timestamp,
    this.reason,
  });
  final String? reason;
  @override
  Map<String, Object?> toJson() => {
        'type': 'TaskCancelled',
        'taskId': taskId,
        'timestamp': timestamp.toIso8601String(),
        if (reason != null) 'reason': reason,
      };
}
