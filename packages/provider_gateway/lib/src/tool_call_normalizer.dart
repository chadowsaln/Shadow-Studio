import 'dart:convert';

import 'package:shadow_contracts/shadow_contracts.dart';

import 'provider_exception.dart';

/// Normalizes provider-specific tool call payloads into unified [AIToolCall].
abstract final class ToolCallNormalizer {
  /// OpenAI-style: {id, type:"function", function:{name, arguments}} or streaming deltas.
  static AIToolCall fromOpenAi(Map<String, Object?> raw) {
    final id = (raw['id'] as String?) ?? '';
    final fn = raw['function'] as Map?;
    final name = (fn?['name'] as String?) ?? (raw['name'] as String?) ?? '';
    final args = _parseArgs(fn?['arguments'] ?? raw['arguments']);
    if (name.isEmpty) {
      throw const ProviderGatewayException(
        code: ShadowErrorCode.providerToolCallMalformed,
        message: 'Missing tool call name',
        retryable: false,
      );
    }
    return AIToolCall(id: id.isEmpty ? 'tool_call' : id, name: name, arguments: args, raw: raw);
  }

  /// Anthropic-style: {id, name, input:{...}} or content_block tool_use.
  static AIToolCall fromAnthropic(Map<String, Object?> raw) {
    final id = (raw['id'] as String?) ?? 'tool_call';
    final name = (raw['name'] as String?) ?? '';
    final input = raw['input'];
    final args = input is Map ? Map<String, Object?>.from(input) : _parseArgs(input);
    if (name.isEmpty) {
      throw const ProviderGatewayException(
        code: ShadowErrorCode.providerToolCallMalformed,
        message: 'Missing tool call name',
        retryable: false,
      );
    }
    return AIToolCall(id: id, name: name, arguments: args, raw: raw);
  }

  /// Gemini-style functionCall: {name, args:{...}}
  static AIToolCall fromGemini(Map<String, Object?> raw, {String? id}) {
    final name = (raw['name'] as String?) ?? '';
    final argsRaw = raw['args'] ?? raw['arguments'];
    final args = argsRaw is Map ? Map<String, Object?>.from(argsRaw) : _parseArgs(argsRaw);
    if (name.isEmpty) {
      throw const ProviderGatewayException(
        code: ShadowErrorCode.providerToolCallMalformed,
        message: 'Missing tool call name',
        retryable: false,
      );
    }
    return AIToolCall(id: id ?? 'tool_call_${name.hashCode}', name: name, arguments: args, raw: raw);
  }

  static Map<String, Object?> _parseArgs(Object? value) {
    if (value == null) return const <String, Object?>{};
    if (value is Map) return Map<String, Object?>.from(value);
    if (value is String) {
      if (value.trim().isEmpty) return const <String, Object?>{};
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, Object?>.from(decoded);
      } catch (_) {
        // fall through
      }
      return <String, Object?>{'_raw': value};
    }
    return <String, Object?>{'_raw': value.toString()};
  }
}
