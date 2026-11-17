import 'dart:async';
import 'dart:convert';

import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:shadow_provider_gateway/provider_gateway.dart';

import 'agent_context_assembler.dart';
import 'planner.dart';

/// Result of one provider round-trip.
class _ProviderReply {
  const _ProviderReply({
    required this.text,
    required this.toolCalls,
    this.finishReason,
  });

  final String text;
  final List<AIToolCall> toolCalls;
  final String? finishReason;
}

/// Thrown when the provider cannot produce a usable reply.
class ProviderAgentBrainException implements Exception {
  const ProviderAgentBrainException(
    this.code,
    this.message, {
    this.retryable = false,
  });

  final String code;
  final String message;
  final bool retryable;

  @override
  String toString() => 'ProviderAgentBrainException($code): $message';
}

/// [AgentBrain] backed by a real provider through [ProviderRouter].
///
/// The model is asked for strict JSON: a plan for [plan], and one of
/// tool_calls/complete/fail/replan for [nextDecision]. Planning falls back to
/// [DefaultPlanner] when the model output is unusable, because a bad plan is
/// recoverable; execution decisions never silently succeed — an unparseable
/// decision fails the task with `PROVIDER_TOOL_CALL_MALFORMED`.
///
/// No API key, prompt secret, or provider-native object is ever stored on the
/// brain; credentials stay inside the gateway.
class ProviderAgentBrain implements AgentBrain {
  ProviderAgentBrain({
    required ProviderRouter router,
    required this.model,
    this.tools = const <AgentTool>[],
    this.providerId,
    this.fallbackProviderIds = const <String>[],
    this.temperature = 0.0,
    this.maxOutputTokens = 1024,
    this.requestTimeout = const Duration(seconds: 30),
    DefaultPlanner? fallbackPlanner,
    this.context,
    CancellationToken? cancel,
  }) : _router = router,
       _fallbackPlanner = fallbackPlanner ?? DefaultPlanner(),
       _cancel = cancel ?? CancellationToken();

  final ProviderRouter _router;
  final DefaultPlanner _fallbackPlanner;
  final CancellationToken _cancel;

  final String model;
  final String? providerId;
  final List<String> fallbackProviderIds;
  final List<AgentTool> tools;
  final double temperature;
  final int maxOutputTokens;
  final Duration requestTimeout;

  /// Live context snapshot for the running task. When present, a compact
  /// projection is added to the decision prompt so the model stays oriented
  /// without ever seeing media bytes or raw tool payloads.
  final AgentContextHolder? context;

  static const String _planSystemPrompt = '''
You are the planning stage of an autonomous video-production agent.
Return ONLY JSON, no prose, no markdown fences:
{"steps":[{"description": <string>, "expected_outcome": <string>}]}
Use 1-8 concrete steps. Each step must be verifiable from tool results.
''';

  static const String _decisionSystemPrompt = '''
You are the execution stage of an autonomous video-production agent.
Return ONLY JSON, no prose, no markdown fences, exactly one of:
{"action":"tool_calls","calls":[{"name": <tool name>, "arguments": <object>}]}
{"action":"complete","summary": <string>, "result": <object>}
{"action":"fail","code": <string>, "message": <string>}
{"action":"replan","reason": <string>}
Only call tools that appear in the provided tool list. Never invent arguments.
''';

  @override
  Future<AgentPlan> plan({
    required String request,
    required String taskId,
  }) async {
    _cancel.throwIfCancelled();
    try {
      final reply = await _call(
        system: _planSystemPrompt,
        userContent: jsonEncode(<String, Object?>{
          'goal': request,
          'tools': _toolCatalog(),
        }),
      );
      final decoded = _decodeObject(reply.text);
      final steps = _parseSteps(decoded);
      if (steps == null || steps.isEmpty) {
        return await _fallbackPlanner.createPlan(
          request: request,
          taskId: taskId,
        );
      }
      return AgentPlan(
        goal: request.trim().isEmpty ? 'Fulfill request' : request.trim(),
        revision: 1,
        steps: steps,
      );
    } on ProviderAgentBrainException {
      return await _fallbackPlanner.createPlan(
        request: request,
        taskId: taskId,
      );
    } on ProviderGatewayException {
      return await _fallbackPlanner.createPlan(
        request: request,
        taskId: taskId,
      );
    } on CancelledException {
      rethrow;
    } catch (_) {
      return await _fallbackPlanner.createPlan(
        request: request,
        taskId: taskId,
      );
    }
  }

  @override
  Future<AgentDecision> nextDecision({
    required AgentPlan plan,
    required String currentStepId,
    required List<AIMessage> history,
  }) async {
    _cancel.throwIfCancelled();
    final step = plan.steps.where((s) => s.id == currentStepId).firstOrNull;
    final reply = await _call(
      system: _decisionSystemPrompt,
      userContent: jsonEncode(<String, Object?>{
        'goal': plan.goal,
        'current_step': step == null
            ? null
            : <String, Object?>{
                'description': step.description,
                'expected_outcome': step.expectedOutcome,
              },
        'completed_steps': plan.completedSteps
            .map((s) => s.resultSummary ?? s.description)
            .toList(),
        'tools': _toolCatalog(),
        'project_context': context?.toPromptJson() ?? const <String, Object?>{},
      }),
      history: history,
    );

    final directCalls = reply.toolCalls;
    final decoded = _decodeObjectOrNull(reply.text);
    final action = decoded?['action'] as String?;

    if (directCalls.isNotEmpty) {
      return ToolCallsDecision(directCalls);
    }

    switch (action) {
      case 'tool_calls':
        final calls = _parseCalls(decoded?['calls']);
        if (calls == null || calls.isEmpty) {
          return const FailDecision(
            ShadowErrorCode.providerToolCallMalformed,
            'Model returned tool_calls without any calls',
          );
        }
        return ToolCallsDecision(calls);
      case 'complete':
        final summary = decoded?['summary'];
        if (summary is! String || summary.trim().isEmpty) {
          return const FailDecision(
            ShadowErrorCode.providerToolCallMalformed,
            'Model returned complete without a summary',
          );
        }
        final result = decoded?['result'];
        return CompleteDecision(
          summary: summary,
          result: result is Map
              ? result.cast<String, Object?>()
              : const <String, Object?>{},
        );
      case 'fail':
        final code = decoded?['code'];
        final message = decoded?['message'];
        if (code is! String || message is! String) {
          return const FailDecision(
            ShadowErrorCode.providerToolCallMalformed,
            'Model returned fail without code/message',
          );
        }
        return FailDecision(code, message);
      case 'replan':
        final reason = decoded?['reason'];
        return ReplanDecision(
          reason is String && reason.trim().isNotEmpty
              ? reason
              : 'Model requested replanning',
        );
      case null:
        if (reply.text.trim().isEmpty) {
          return const FailDecision(
            ShadowErrorCode.providerStreamBroken,
            'Provider produced no text and no tool calls',
          );
        }
        return CompleteDecision(summary: reply.text.trim());
      default:
        return FailDecision(
          ShadowErrorCode.providerToolCallMalformed,
          'Unknown action "$action"',
        );
    }
  }

  @override
  Future<AgentPlan> replan({
    required AgentPlan currentPlan,
    required String taskId,
    required String failureReason,
    required List<ToolResult> recentObservations,
  }) async {
    _cancel.throwIfCancelled();
    try {
      final reply = await _call(
        system: _planSystemPrompt,
        userContent: jsonEncode(<String, Object?>{
          'goal': currentPlan.goal,
          'failure_reason': failureReason,
          'observations': recentObservations
              .map(
                (r) => <String, Object?>{
                  'success': r.success,
                  'error_code': r.errorCode,
                  'error_message': r.errorMessage,
                },
              )
              .toList(),
          'tools': _toolCatalog(),
        }),
      );
      final steps = _parseSteps(_decodeObject(reply.text));
      if (steps == null || steps.isEmpty) {
        return await _fallbackPlanner.replan(
          currentPlan: currentPlan,
          taskId: taskId,
          failureReason: failureReason,
          recentObservations: recentObservations,
        );
      }
      return AgentPlan(
        goal: currentPlan.goal,
        revision: currentPlan.revision + 1,
        steps: steps,
      );
    } on ProviderAgentBrainException {
      return await _fallbackPlanner.replan(
        currentPlan: currentPlan,
        taskId: taskId,
        failureReason: failureReason,
        recentObservations: recentObservations,
      );
    } on ProviderGatewayException {
      return await _fallbackPlanner.replan(
        currentPlan: currentPlan,
        taskId: taskId,
        failureReason: failureReason,
        recentObservations: recentObservations,
      );
    } on CancelledException {
      rethrow;
    } catch (_) {
      return await _fallbackPlanner.replan(
        currentPlan: currentPlan,
        taskId: taskId,
        failureReason: failureReason,
        recentObservations: recentObservations,
      );
    }
  }

  Future<_ProviderReply> _call({
    required String system,
    required String userContent,
    List<AIMessage> history = const <AIMessage>[],
  }) async {
    final messages = <AIMessage>[
      AIMessage(role: AIMessageRole.system, content: system),
      ...history,
      AIMessage(role: AIMessageRole.user, content: userContent),
    ];

    final buffer = StringBuffer();
    final calls = <AIToolCall>[];
    String? finishReason;

    final stream = _router.stream(
      request: AIRequest(
        model: model,
        messages: messages,
        tools: _toolDefinitions(),
        temperature: temperature,
        maxOutputTokens: maxOutputTokens,
        metadata: const <String, Object?>{'purpose': 'agent_brain'},
      ),
      providerId: providerId,
      fallbackProviderIds: fallbackProviderIds.isEmpty
          ? null
          : fallbackProviderIds,
      cancel: _cancel,
      timeout: requestTimeout,
    );

    try {
      await for (final event in stream) {
        switch (event) {
          case AITextDeltaEvent(:final delta):
            buffer.write(delta);
          case AIToolCallEvent(:final call):
            calls.add(call);
          case AICompletedEvent(finishReason: final fr):
            finishReason ??= fr;
          case AIUsageEvent():
            break;
          case AIErrorEvent(:final message, :final code):
            throw ProviderAgentBrainException(
              code ?? ShadowErrorCode.providerStreamBroken,
              message,
              retryable: event.retryable,
            );
        }
      }
    } on ProviderGatewayException catch (e) {
      throw ProviderAgentBrainException(
        e.code,
        e.message,
        retryable: e.retryable,
      );
    }

    return _ProviderReply(
      text: buffer.toString(),
      toolCalls: calls,
      finishReason: finishReason,
    );
  }

  List<Map<String, Object?>> _toolCatalog() => <Map<String, Object?>>[
    for (final tool in tools)
      <String, Object?>{
        'name': tool.name,
        'description': tool.description,
        'risk': tool.riskLevel.name,
      },
  ];

  List<AIToolDefinition> _toolDefinitions() => <AIToolDefinition>[
    for (final tool in tools)
      AIToolDefinition(
        name: tool.name,
        description: tool.description,
        inputSchema: tool.inputSchema,
      ),
  ];

  static List<PlanStep>? _parseSteps(Object? decoded) {
    if (decoded is! Map) return null;
    final raw = decoded['steps'];
    if (raw is! List) return null;
    final steps = <PlanStep>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) return null;
      final description = item['description'];
      if (description is! String || description.trim().isEmpty) return null;
      final outcome = item['expected_outcome'];
      steps.add(
        PlanStep(
          id: 'step_${i + 1}',
          description: description.trim(),
          expectedOutcome: outcome is String && outcome.trim().isNotEmpty
              ? outcome.trim()
              : 'Verified by tool results.',
        ),
      );
    }
    return steps;
  }

  static List<AIToolCall>? _parseCalls(Object? raw) {
    if (raw is! List) return null;
    final calls = <AIToolCall>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) return null;
      final name = item['name'];
      if (name is! String || name.trim().isEmpty) return null;
      final args = item['arguments'];
      calls.add(
        AIToolCall(
          id: 'call_${i + 1}',
          name: name.trim(),
          arguments: args is Map
              ? args.map((k, v) => MapEntry(k.toString(), v))
              : <String, Object?>{},
        ),
      );
    }
    return calls;
  }

  /// Extracts the first JSON object, tolerating markdown fences and prose.
  static Map<String, Object?>? _decodeObjectOrNull(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final candidates = <String>[trimmed];
    final fenced = _firstFencedBlock(trimmed);
    if (fenced != null) candidates.add(fenced);
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      candidates.add(trimmed.substring(start, end + 1));
    }
    for (final candidate in candidates) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map<String, Object?>) return decoded;
        if (decoded is Map) return decoded.cast<String, Object?>();
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static Map<String, Object?> _decodeObject(String text) {
    final decoded = _decodeObjectOrNull(text);
    if (decoded == null) {
      throw const ProviderAgentBrainException(
        ShadowErrorCode.providerToolCallMalformed,
        'Model reply was not valid JSON',
      );
    }
    return decoded;
  }

  static String? _firstFencedBlock(String text) {
    final match = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
    return match?.group(1)?.trim();
  }
}
