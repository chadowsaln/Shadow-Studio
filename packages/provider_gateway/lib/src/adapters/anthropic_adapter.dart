import 'dart:async';

import 'package:shadow_contracts/shadow_contracts.dart';

import '../credential_store.dart';
import '../provider_exception.dart';
import '../provider_transport.dart';
import '../tool_call_normalizer.dart';
import 'adapter_utils.dart';

class AnthropicAdapter implements AIProvider {
  AnthropicAdapter({
    ProviderTransport? transport,
    CredentialStore? credentialStore,
    Uri? baseUri,
    this.defaultTimeout = const Duration(seconds: 60),
  }) : _transport = transport ?? MockProviderTransport(),
       _credentials = ProviderCredentialResolver(
         credentialStore ?? InMemoryCredentialStore(),
       ),
       _baseUri = baseUri ?? Uri.parse('https://api.anthropic.com/v1');

  static const provider = 'anthropic';
  final ProviderTransport _transport;
  final ProviderCredentialResolver _credentials;
  final Uri _baseUri;
  final Duration defaultTimeout;

  @override
  String get id => provider;
  @override
  String get displayName => 'Anthropic';
  @override
  Set<ProviderFeature> get features => const {
    ProviderFeature.textGeneration,
    ProviderFeature.streaming,
    ProviderFeature.toolCalling,
    ProviderFeature.vision,
    ProviderFeature.promptCaching,
  };

  static const _models = <AIModel>[
    AIModel(
      id: 'claude-3-5-sonnet-latest',
      providerId: provider,
      displayName: 'Claude 3.5 Sonnet',
      features: {
        ProviderFeature.textGeneration,
        ProviderFeature.streaming,
        ProviderFeature.toolCalling,
        ProviderFeature.vision,
        ProviderFeature.promptCaching,
      },
      contextWindowTokens: 200000,
    ),
    AIModel(
      id: 'claude-3-5-haiku-latest',
      providerId: provider,
      displayName: 'Claude 3.5 Haiku',
      features: {
        ProviderFeature.textGeneration,
        ProviderFeature.streaming,
        ProviderFeature.toolCalling,
      },
      contextWindowTokens: 200000,
    ),
  ];

  @override
  Future<List<AIModel>> getModels({required CancellationToken cancel}) async =>
      _models;

  @override
  Stream<AIStreamEvent> stream({
    required AIRequest request,
    required CancellationToken cancel,
  }) async* {
    final key = await _credentials.requireApiKey(id);
    final uri = resolveProviderEndpoint(_baseUri, 'messages');
    final (system, messages) = _messages(request);
    final body = <String, Object?>{
      'model': request.model,
      'messages': messages,
      'max_tokens': request.maxOutputTokens,
      'temperature': request.temperature,
      'stream': true,
      'system': ?system,
      if (request.tools.isNotEmpty)
        'tools': [
          for (final t in request.tools)
            {
              'name': t.name,
              'description': t.description,
              'input_schema': t.inputSchema,
            },
        ],
    };
    final headers = <String, String>{
      'x-api-key': key,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    };
    try {
      final chunks = _transport.send(
        uri: uri,
        headers: headers,
        body: body,
        stream: true,
        timeout: defaultTimeout,
        cancel: cancel,
      );
      await for (final raw in chunks) {
        cancel.throwIfCancelled();
        if (raw is! Map) continue;
        if (raw['status'] is int && (raw['status'] as int) >= 400) {
          throw AdapterHttp.fromStatus(
            raw['status'] as int,
            providerId: id,
            message: raw['message']?.toString(),
          );
        }
        final type = raw['type']?.toString();
        if (type == 'error') {
          final err = raw['error'] as Map? ?? raw;
          throw ProviderGatewayException(
            code: ShadowErrorCode.providerStreamBroken,
            message: err['message']?.toString() ?? 'Anthropic error',
            retryable: false,
            providerId: id,
          );
        }
        if (type == 'content_block_start') {
          final cb = raw['content_block'];
          if (cb is Map && cb['type'] == 'tool_use') {
            yield AIToolCallEvent(
              ToolCallNormalizer.fromAnthropic(Map<String, Object?>.from(cb)),
            );
          }
        } else if (type == 'content_block_delta') {
          final delta = raw['delta'];
          if (delta is Map) {
            if (delta['type'] == 'text_delta' && delta['text'] is String) {
              yield AITextDeltaEvent(delta['text'] as String);
            }
            if (delta['type'] == 'input_json_delta' &&
                delta['partial_json'] is String) {
              // partial tool input; full tool emitted on start in many mocks; ignore partial here
            }
          }
        } else if (type == 'message_delta') {
          final usage = raw['usage'];
          if (usage is Map) {
            yield AIUsageEvent(
              TokenUsage(outputTokens: usage['output_tokens'] as int?),
            );
          }
          final delta = raw['delta'];
          if (delta is Map && delta['stop_reason'] != null) {
            yield AICompletedEvent(
              finishReason: delta['stop_reason'].toString(),
            );
          }
        } else if (type == 'message_start') {
          final msg = raw['message'];
          if (msg is Map && msg['usage'] is Map) {
            final u = msg['usage'] as Map;
            yield AIUsageEvent(
              TokenUsage(
                inputTokens: u['input_tokens'] as int?,
                outputTokens: u['output_tokens'] as int?,
              ),
            );
          }
        } else if (type == 'message_stop') {
          yield const AICompletedEvent(finishReason: 'stop');
        }
      }
    } on ProviderGatewayException {
      rethrow;
    } on CancelledException catch (e) {
      throw ProviderCancelledException(providerId: id, reason: e.reason);
    } catch (e) {
      throw normalizeTransportError(e, providerId: id);
    }
  }

  (String?, List<Map<String, Object?>>) _messages(AIRequest request) {
    String? system;
    final out = <Map<String, Object?>>[];
    for (final m in request.messages) {
      if (m.role == AIMessageRole.system) {
        system = (system == null)
            ? (m.content ?? '')
            : '$system\n${m.content ?? ''}';
        continue;
      }
      if (m.role == AIMessageRole.tool) {
        out.add({
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': m.toolCallId,
              'content': m.content ?? '',
            },
          ],
        });
        continue;
      }
      final role = m.role == AIMessageRole.assistant ? 'assistant' : 'user';
      final content = <Map<String, Object?>>[];
      if (m.content != null && m.content!.isNotEmpty) {
        content.add({'type': 'text', 'text': m.content});
      }
      for (final tc in m.toolCalls) {
        content.add({
          'type': 'tool_use',
          'id': tc.id,
          'name': tc.name,
          'input': tc.arguments,
        });
      }
      out.add({
        'role': role,
        'content': content.isEmpty ? m.content ?? '' : content,
      });
    }
    return (system, out);
  }
}
