import 'package:shadow_contracts/shadow_contracts.dart';

/// Enforced runtime limits (SS-ARCH-002 / request). Not prompt-configurable.
class AgentRuntimeLimits {
  const AgentRuntimeLimits({
    this.maxToolCalls = 40,
    this.maxDuration = const Duration(minutes: 10),
    this.maxRetriesPerTool = 3,
    this.maxInputTokensPerTask = 60000,
    this.maxConsecutiveIdenticalToolCalls = 3,
    this.maxPendingApprovals = 1,
  });

  final int maxToolCalls;
  final Duration maxDuration;
  final int maxRetriesPerTool;
  final int maxInputTokensPerTask;
  final int maxConsecutiveIdenticalToolCalls;
  final int maxPendingApprovals;

  AgentBudget toBudget() => AgentBudget(
    maxToolCalls: maxToolCalls,
    maxDuration: maxDuration,
    maxInputTokens: maxInputTokensPerTask,
    maxSameToolRepeat: maxConsecutiveIdenticalToolCalls,
  );
}

class TaskBudgetExceededException implements Exception {
  TaskBudgetExceededException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'TaskBudgetExceededException($code, $message)';
}

class LoopDetectedException implements Exception {
  LoopDetectedException(this.message);
  final String message;
  @override
  String toString() => 'LoopDetectedException($message)';
}
