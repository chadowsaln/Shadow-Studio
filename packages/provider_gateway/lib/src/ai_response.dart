import 'package:meta/meta.dart';
import 'package:shadow_contracts/shadow_contracts.dart';

/// Unified, provider-independent response snapshot (non-streaming aggregation helper).
@immutable
class AIResponse {
  const AIResponse({
    required this.providerId,
    required this.model,
    required this.messages,
    this.text = '',
    this.toolCalls = const <AIToolCall>[],
    this.usage,
    this.finishReason,
    this.raw = const <String, Object?>{},
  });

  final String providerId;
  final String model;
  final List<AIMessage> messages;
  final String text;
  final List<AIToolCall> toolCalls;
  final TokenUsage? usage;
  final String? finishReason;
  final Map<String, Object?> raw;

  bool get hasToolCalls => toolCalls.isNotEmpty;
}
