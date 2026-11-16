import 'dart:convert';

enum ProviderFeature {
  textGeneration,
  streaming,
  toolCalling,
  structuredOutput,
  vision,
  jsonMode,
  promptCaching,
}

class AIModel {
  const AIModel({
    required this.id,
    required this.providerId,
    required this.displayName,
    required this.features,
    this.contextWindowTokens,
    this.maxOutputTokens,
    this.inputCostPer1kTokens,
    this.outputCostPer1kTokens,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String providerId;
  final String displayName;
  final Set<ProviderFeature> features;
  final int? contextWindowTokens;
  final int? maxOutputTokens;
  final double? inputCostPer1kTokens;
  final double? outputCostPer1kTokens;
  final Map<String, Object?> metadata;

  bool supports(ProviderFeature feature) => features.contains(feature);
}

class AIToolDefinition {
  const AIToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;
  final Map<String, Object?> inputSchema; // closed JSON-schema subset
}

class AIToolCall {
  const AIToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    this.raw,
  });

  final String id;
  final String name;
  final Map<String, Object?> arguments;
  final Map<String, Object?>? raw;

  String get argumentsJson => jsonEncode(arguments);
}

enum AIMessageRole { system, user, assistant, tool }

class AIMessage {
  const AIMessage({
    required this.role,
    this.content,
    this.toolCallId,
    this.toolCalls = const <AIToolCall>[],
    this.name,
    this.metadata = const <String, Object?>{},
  });

  final AIMessageRole role;
  final String? content;
  final String? toolCallId;
  final List<AIToolCall> toolCalls;
  final String? name;
  final Map<String, Object?> metadata;
}

class TokenUsage {
  const TokenUsage({
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
  });

  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
}

class RequestBudget {
  const RequestBudget({
    this.maxInputTokens,
    this.maxOutputTokens,
    this.maxCostUsd,
  });

  final int? maxInputTokens;
  final int? maxOutputTokens;
  final double? maxCostUsd;
}

class AIRequest {
  const AIRequest({
    required this.model,
    required this.messages,
    this.tools = const <AIToolDefinition>[],
    this.temperature = 0.0,
    this.maxOutputTokens = 2048,
    this.budget,
    this.metadata = const <String, Object?>{},
  });

  final String model;
  final List<AIMessage> messages;
  final List<AIToolDefinition> tools;
  final double temperature;
  final int maxOutputTokens;
  final RequestBudget? budget;
  final Map<String, Object?> metadata;
}

sealed class AIStreamEvent {
  const AIStreamEvent();
}

class AITextDeltaEvent extends AIStreamEvent {
  const AITextDeltaEvent(this.delta);
  final String delta;
}

class AIToolCallEvent extends AIStreamEvent {
  const AIToolCallEvent(this.call);
  final AIToolCall call;
}

class AIUsageEvent extends AIStreamEvent {
  const AIUsageEvent(this.usage);
  final TokenUsage usage;
}

class AICompletedEvent extends AIStreamEvent {
  const AICompletedEvent({
    this.finishReason,
    this.usage,
  });
  final String? finishReason;
  final TokenUsage? usage;
}

class AIErrorEvent extends AIStreamEvent {
  const AIErrorEvent(this.message, {this.code, this.retryable = false});
  final String message;
  final String? code;
  final bool retryable;
}
