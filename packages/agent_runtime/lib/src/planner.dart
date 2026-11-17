import 'dart:math';

import 'package:shadow_contracts/shadow_contracts.dart';

/// Deterministic baseline planner (no CoT). Suitable for tests and as a safe default.
///
/// The [Planner], [AgentPlan], [PlanStep] and [PlanStepStatus] contracts live in
/// `shadow_contracts`; this file only provides the default implementation.
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
      description: normalized.isEmpty
          ? 'Execute task request'
          : 'Fulfill request: $normalized',
      expectedOutcome:
          'Task request addressed with available tools and verified results.',
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
      description:
          'Recover and continue after failure: ${_short(failureReason)}',
      expectedOutcome:
          'Resolve failure and satisfy: ${failedOrPending.expectedOutcome}',
    );
    final newSteps = <PlanStep>[
      for (final s in currentPlan.steps)
        if (s.id == failedOrPending.id) recovery else s,
    ];
    return AgentPlan(
      goal: currentPlan.goal,
      revision: nextRevision,
      steps: newSteps,
    );
  }

  String _id(String taskId, int n) =>
      'step_${taskId}_${n}_${_random.nextInt(1 << 20).toRadixString(16)}';

  static String _short(String s) =>
      s.length <= 120 ? s : '${s.substring(0, 117)}...';
}
