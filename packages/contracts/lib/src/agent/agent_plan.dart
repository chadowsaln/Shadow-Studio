import 'package:meta/meta.dart';

import '../providers/provider_models.dart';
import '../tools/tool_contracts.dart';

/// Lifecycle state of a single plan step.
enum PlanStepStatus { pending, inProgress, completed, failed, skipped }

/// A single executable step in an [AgentPlan].
///
/// Steps are immutable value objects. A plan is revised by producing a new
/// [AgentPlan] rather than mutating an existing one.
@immutable
class PlanStep {
  const PlanStep({
    required this.id,
    required this.description,
    required this.expectedOutcome,
    this.status = PlanStepStatus.pending,
    this.toolCalls = const <AIToolCall>[],
    this.resultSummary,
    this.error,
  });

  final String id;
  final String description;
  final String expectedOutcome;
  final PlanStepStatus status;
  final List<AIToolCall> toolCalls;
  final String? resultSummary;
  final String? error;

  bool get isTerminal =>
      status == PlanStepStatus.completed ||
      status == PlanStepStatus.failed ||
      status == PlanStepStatus.skipped;

  PlanStep copyWith({
    PlanStepStatus? status,
    List<AIToolCall>? toolCalls,
    String? resultSummary,
    String? error,
  }) {
    return PlanStep(
      id: id,
      description: description,
      expectedOutcome: expectedOutcome,
      status: status ?? this.status,
      toolCalls: toolCalls ?? this.toolCalls,
      resultSummary: resultSummary ?? this.resultSummary,
      error: error ?? this.error,
    );
  }

  static PlanStepStatus _statusFromJson(Object? value) {
    if (value is String) {
      for (final s in PlanStepStatus.values) {
        if (s.name == value) return s;
      }
    }
    return PlanStepStatus.pending;
  }

  static PlanStep fromJson(Map<String, Object?> json) => PlanStep(
    id: json['id'] as String,
    description: json['description'] as String? ?? '',
    expectedOutcome: json['expectedOutcome'] as String? ?? '',
    status: _statusFromJson(json['status']),
    toolCalls: const <AIToolCall>[],
    resultSummary: json['resultSummary'] as String?,
    error: json['error'] as String?,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'description': description,
    'expectedOutcome': expectedOutcome,
    'status': status.name,
    'toolCallCount': toolCalls.length,
    if (resultSummary != null) 'resultSummary': resultSummary,
    if (error != null) 'error': error,
  };
}

/// An ordered, revisioned plan produced by a [Planner].
@immutable
class AgentPlan {
  const AgentPlan({required this.steps, required this.revision, this.goal});

  final List<PlanStep> steps;
  final int revision;
  final String? goal;

  List<PlanStep> get pendingSteps =>
      steps.where((s) => s.status == PlanStepStatus.pending).toList();
  List<PlanStep> get completedSteps =>
      steps.where((s) => s.status == PlanStepStatus.completed).toList();
  bool get isComplete => steps.isNotEmpty && steps.every((s) => s.isTerminal);

  AgentPlan updateStep(String stepId, PlanStep Function(PlanStep) transform) {
    return AgentPlan(
      goal: goal,
      revision: revision,
      steps: [
        for (final s in steps)
          if (s.id == stepId) transform(s) else s,
      ],
    );
  }

  AgentPlan withRevision(
    int nextRevision, {
    List<PlanStep>? newSteps,
    String? goal,
  }) {
    return AgentPlan(
      goal: goal ?? this.goal,
      revision: nextRevision,
      steps: newSteps ?? steps,
    );
  }

  static AgentPlan fromJson(Map<String, Object?> json) {
    final rawSteps = json['steps'] as List<Object?>? ?? const <Object?>[];
    return AgentPlan(
      revision: json['revision'] as int? ?? 0,
      goal: json['goal'] as String?,
      steps: [
        for (final e in rawSteps)
          if (e is Map)
            PlanStep.fromJson(e.map((k, v) => MapEntry(k.toString(), v))),
      ],
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    if (goal != null) 'goal': goal,
    'revision': revision,
    'steps': steps.map((s) => s.toJson()).toList(),
  };
}

/// Converts requests into executable steps and replans on failure.
abstract interface class Planner {
  Future<AgentPlan> createPlan({
    required String request,
    required String taskId,
  });

  Future<AgentPlan> replan({
    required AgentPlan currentPlan,
    required String taskId,
    required String failureReason,
    required List<ToolResult> recentObservations,
  });
}
