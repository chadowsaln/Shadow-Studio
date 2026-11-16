enum AgentTaskState {
  queued,
  planning,
  acting,
  awaitingApproval,
  succeeded,
  failed,
  cancelled,
}

enum AgentEventType {
  plan,
  step,
  toolCall,
  toolResult,
  approvalRequested,
  progress,
  error,
  done,
  cancelled,
}

class AgentEvent {
  const AgentEvent({
    required this.type,
    required this.taskId,
    required this.timestamp,
    this.correlationId,
    this.message,
    this.payload = const <String, Object?>{},
  });

  final AgentEventType type;
  final String taskId;
  final DateTime timestamp;
  final String? correlationId;
  final String? message;
  final Map<String, Object?> payload;
}

class AgentBudget {
  const AgentBudget({
    this.maxToolCalls = 40,
    this.maxDuration = const Duration(minutes: 10),
    this.maxInputTokens = 60000,
    this.maxSameToolRepeat = 3,
  });

  final int maxToolCalls;
  final Duration maxDuration;
  final int maxInputTokens;
  final int maxSameToolRepeat;
}
