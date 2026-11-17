import '../permissions/permissions.dart';
import '../providers/provider_models.dart';
import '../tools/tool_contracts.dart';
import 'agent_plan.dart';

/// Decision returned by the planning/model layer for one turn.
sealed class AgentDecision {
  const AgentDecision();
}

/// The task is complete; no further tool calls are required.
class CompleteDecision extends AgentDecision {
  const CompleteDecision({
    required this.summary,
    this.result = const <String, Object?>{},
  });

  final String summary;
  final Map<String, Object?> result;
}

/// Execute one or more tool calls for the current step.
class ToolCallsDecision extends AgentDecision {
  const ToolCallsDecision(this.calls);

  final List<AIToolCall> calls;
}

/// Replan before executing the current step.
class ReplanDecision extends AgentDecision {
  const ReplanDecision(this.reason);

  final String reason;
}

/// Abort the task with a structured error.
class FailDecision extends AgentDecision {
  const FailDecision(this.code, this.message, {this.retryable = false});

  final String code;
  final String message;
  final bool retryable;
}

/// Abstraction over the "brain" (planner + model).
///
/// Implementations must be deterministic with respect to their inputs so the
/// execution loop can be tested without a network or a live model.
abstract interface class AgentBrain {
  Future<AgentPlan> plan({required String request, required String taskId});

  Future<AgentDecision> nextDecision({
    required AgentPlan plan,
    required String currentStepId,
    required List<AIMessage> history,
  });

  Future<AgentPlan> replan({
    required AgentPlan currentPlan,
    required String taskId,
    required String failureReason,
    required List<ToolResult> recentObservations,
  });
}

/// Executes a single tool call.
///
/// The registry, permission checks, schema validation, and audit live behind
/// this interface in `tool_system`; the agent loop only sees this port.
abstract interface class ToolCallExecutor {
  AgentTool? resolve(String name);

  Future<ToolResult> execute({
    required AIToolCall call,
    required ToolContext context,
    required AgentTool tool,
  });
}

/// Requests explicit user approval for a tool call.
///
/// Implementations must enforce at most one pending approval at a time and
/// must never auto-approve. Returning `null` means denied or timed out.
abstract interface class ApprovalGate {
  Future<ApprovalToken?> requestApproval({
    required String taskId,
    required String callId,
    required AgentTool tool,
    required Map<String, Object?> arguments,
  });
}
