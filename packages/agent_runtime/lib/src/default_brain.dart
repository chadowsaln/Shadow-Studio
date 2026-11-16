import 'package:shadow_contracts/shadow_contracts.dart';

import 'execution_loop.dart';
import 'planner.dart';

/// Simple deterministic brain for tests: proposes tool calls for pending step
/// via a provided callback, else completes.
typedef DecisionCallback = Future<AgentDecision> Function({
  required AgentPlan plan,
  required String currentStepId,
  required List<AIMessage> history,
});

class CallbackAgentBrain implements AgentBrain {
  CallbackAgentBrain({
    Planner? planner,
    DecisionCallback? onNextDecision,
  })  : _planner = planner ?? DefaultPlanner(),
        _onNextDecision = onNextDecision;

  final Planner _planner;
  final DecisionCallback? _onNextDecision;

  @override
  Future<AgentPlan> plan({required String request, required String taskId}) =>
      _planner.createPlan(request: request, taskId: taskId);

  @override
  Future<AgentDecision> nextDecision({
    required AgentPlan plan,
    required String currentStepId,
    required List<AIMessage> history,
  }) async {
    final cb = _onNextDecision;
    if (cb != null) {
      return cb(plan: plan, currentStepId: currentStepId, history: history);
    }
    return const CompleteDecision(summary: 'Completed');
  }

  @override
  Future<AgentPlan> replan({
    required AgentPlan currentPlan,
    required String taskId,
    required String failureReason,
    required List<ToolResult> recentObservations,
  }) =>
      _planner.replan(
        currentPlan: currentPlan,
        taskId: taskId,
        failureReason: failureReason,
        recentObservations: recentObservations,
      );
}
