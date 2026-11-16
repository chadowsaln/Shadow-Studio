import 'package:shadow_contracts/shadow_contracts.dart';

import 'ai_response.dart';

/// Aggregates a unified stream into [AIResponse] and exposes token/cost accounting hooks.
class StreamAccumulator {
  StreamAccumulator({required this.providerId, required this.model});

  final String providerId;
  final String model;
  final StringBuffer _text = StringBuffer();
  final List<AIToolCall> _toolCalls = <AIToolCall>[];
  TokenUsage? _usage;
  String? _finishReason;
  final List<AIMessage> _messages = <AIMessage>[];

  void add(AIStreamEvent event) {
    switch (event) {
      case AITextDeltaEvent(:final delta):
        _text.write(delta);
      case AIToolCallEvent(:final call):
        _toolCalls.add(call);
      case AIUsageEvent(:final usage):
        _usage = usage;
      case AICompletedEvent(:final finishReason, :final usage):
        _finishReason = finishReason ?? _finishReason;
        if (usage != null) _usage = usage;
      case AIErrorEvent():
        break;
    }
  }

  AIResponse build() {
    final text = _text.toString();
    final assistant = AIMessage(
      role: AIMessageRole.assistant,
      content: text.isEmpty ? null : text,
      toolCalls: List<AIToolCall>.unmodifiable(_toolCalls),
    );
    return AIResponse(
      providerId: providerId,
      model: model,
      messages: [assistant, ..._messages],
      text: text,
      toolCalls: List<AIToolCall>.unmodifiable(_toolCalls),
      usage: _usage,
      finishReason: _finishReason,
    );
  }
}
