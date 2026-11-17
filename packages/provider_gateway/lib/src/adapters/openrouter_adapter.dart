import 'dart:async';

import 'package:shadow_contracts/shadow_contracts.dart';

import '../credential_store.dart';
import '../provider_exception.dart';
import '../provider_transport.dart';
import '../tool_call_normalizer.dart';
import 'adapter_utils.dart';

/// OpenRouter is OpenAI-compatible; capabilities vary per model.
class OpenRouterAdapter implements AIProvider {
  OpenRouterAdapter({
    ProviderTransport? transport,
    CredentialStore? credentialStore,
    Uri? baseUri,
    this.defaultTimeout = const Duration(seconds: 60),
  }) : _transport = transport ?? MockProviderTransport(),
       _credentials = ProviderCredentialResolver(
         credentialStore ?? InMemoryCredentialStore(),
       ),
       _baseUri = baseUri ?? Uri.parse('https://openrouter.ai/api/v1');

  static const provider = 'openrouter';
  final ProviderTransport _transport;
  final ProviderCredentialResolver _credentials;
  final Uri _baseUri;
  final Duration defaultTimeout;

  @override
  String get id => provider;
  @override
  String get displayName => 'OpenRouter';
  @override
  Set<ProviderFeature> get features => const {
    ProviderFeature.textGeneration,
    ProviderFeature.streaming,
    ProviderFeature
        .toolCalling, // per-model in reality; detected via model entry
    ProviderFeature.vision,
    ProviderFeature.jsonMode,
  };

  static const _models = <AIModel>[
    AIModel(
      id: 'openai/gpt-4o-mini',
      providerId: provider,
      displayName: 'OpenAI GPT-4o mini (via OpenRouter)',
      features: {
        ProviderFeature.textGeneration,
        ProviderFeature.streaming,
        ProviderFeature.toolCalling,
        ProviderFeature.vision,
        ProviderFeature.jsonMode,
      },
      contextWindowTokens: 128000,
    ),
    AIModel(
      id: 'anthropic/claude-3.5-sonnet',
      providerId: provider,
      displayName: 'Claude 3.5 Sonnet (via OpenRouter)',
      features: {
        ProviderFeature.textGeneration,
        ProviderFeature.streaming,
        ProviderFeature.toolCalling,
        ProviderFeature.vision,
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
    final uri = resolveProviderEndpoint(_baseUri, 'chat/completions');
    final body = <String, Object?>{
      'model': request.model,
      'messages': openAiMessages(request),
      'temperature': request.temperature,
      'max_tokens': request.maxOutputTokens,
      'stream': true,
    };
    if (request.tools.isNotEmpty) body['tools'] = openAiTools(request);
    final headers = <String, String>{
      'Authorization': 'Bearer $key',
      'Content-Type': 'application/json',
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
        if (raw['error'] is Map) {
          final err = raw['error'] as Map;
          final status =
              raw['status'] as int? ??
              (err['code'] is int ? err['code'] as int : 500);
          throw AdapterHttp.fromStatus(
            status,
            providerId: id,
            message: err['message']?.toString(),
          );
        }
        if (raw['status'] is int && (raw['status'] as int) >= 400) {
          throw AdapterHttp.fromStatus(
            raw['status'] as int,
            providerId: id,
            message: raw['message']?.toString(),
          );
        }
        final usage = raw['usage'];
        if (usage is Map) {
          yield AIUsageEvent(
            TokenUsage(
              inputTokens: usage['prompt_tokens'] as int?,
              outputTokens: usage['completion_tokens'] as int?,
              totalTokens: usage['total_tokens'] as int?,
            ),
          );
        }
        final choices = raw['choices'];
        if (choices is List && choices.isNotEmpty) {
          final choice = choices.first as Map;
          final delta = choice['delta'] as Map? ?? choice['message'] as Map?;
          if (delta != null) {
            final content = delta['content'];
            if (content is String && content.isNotEmpty)
              yield AITextDeltaEvent(content);
            final tcs = delta['tool_calls'];
            if (tcs is List) {
              for (final tc in tcs) {
                if (tc is Map) {
                  try {
                    yield AIToolCallEvent(
                      ToolCallNormalizer.fromOpenAi(
                        Map<String, Object?>.from(tc),
                      ),
                    );
                  } catch (_) {}
                }
              }
            }
          }
          final finish = choice['finish_reason'];
          if (finish != null)
            yield AICompletedEvent(finishReason: finish.toString());
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
}
