import 'dart:math';

import 'package:meta/meta.dart';
import 'package:shadow_contracts/shadow_contracts.dart';

enum PlanStepStatus { pending, inProgress, completed, failed, skipped }

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

  static PlanStep fromJson(Map<String, dynamic> json) => PlanStep(
        id: json['id'] as String,
        description: json['description'] as String,
        expectedOutcome: json['expectedOutcome'] as String,
        status: PlanStepStatus.values.firstWhere((s) => s.name == (json['status'] as String? ?? 'pending'), orElse: () => PlanStepStatus.pending),
        resultSummary: json['resultSummary'] as String?,
        error: json['error'] as String?,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'description': description,
        'expectedOutcome': expectedOutcome,
        'status': status.name,
        'toolCallCount': toolCalls.length,
        if (resultSummary != null) 'resultSummary': resultSummary,
        if (error != null) 'error': error,
      };
}

@immutable
class AgentPlan {
  const AgentPlan({
    required this.steps,
    required this.revision,
    this.goal,
  });

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

  AgentPlan withRevision(int nextRevision, {List<PlanStep>? newSteps, String? goal}) {
    return AgentPlan(
      goal: goal ?? this.goal,
      revision: nextRevision,
      steps: newSteps ?? steps,
    );
  }

  static AgentPlan fromJson(Map<String, dynamic> json) => AgentPlan(
        revision: json['revision'] as int,
        goal: json['goal'] as String?,
        steps: (json['steps'] as List).map((e) => PlanStep.fromJson((e as Map).cast<String, dynamic>())).toList(),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        if (goal != null) 'goal': goal,
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

/// Deterministic baseline planner (no CoT). Suitable for tests and as a safe default.
class DefaultPlanner implements Planner {
  DefaultPlanner({Random? random}) : _random = random ?? Random();

  final Random _random;

  @override
  Future<AgentPlan> createPlan({
    required String request,
    required String taskId,
  }) async {
    final normalized = request.trim();
    final step = PlanStep(
      id: _id(taskId, 0),
      description: normalized.isEmpty ? 'Execute task request' : 'Fulfill request: $normalized',
      expectedOutcome: 'Task request addressed with available tools and verified results.',
    );
    return AgentPlan(goal: normalized, revision: 1, steps: [step]);
  }

  @override
  Future<AgentPlan> replan({
    required AgentPlan currentPlan,
    required String taskId,
    required String failureReason,
    required List<ToolResult> recentObservations,
  }) async {
    final nextRevision = currentPlan.revision + 1;
    final pending = currentPlan.pendingSteps;
    if (pending.isEmpty) return currentPlan.withRevision(nextRevision);

    // Replace the first pending step with a recovery-oriented step; keep completed intact.
    final failedOrPending = pending.first;
    final recovery = PlanStep(
      id: _id(taskId, nextRevision),
      description: 'Recover and continue after failure: ${_short(failureReason)}',
      expectedOutcome: 'Resolve failure and satisfy: ${failedOrPending.expectedOutcome}',
    );
    final newSteps = <PlanStep>[
      for (final s in currentPlan.steps)
        if (s.id == failedOrPending.id) recovery else s,
    ];
    return AgentPlan(goal: currentPlan.goal, revision: nextRevision, steps: newSteps);
  }

  String _id(String taskId, int n) =>
      'step_${taskId}_${n}_${_random.nextInt(1 << 20).toRadixString(16)}';

  static String _short(String s) => s.length <= 120 ? s : '${s.substring(0, 117)}...';
}
