import 'dart:async';

import 'package:shadow_contracts/shadow_contracts.dart';

import '../credential_store.dart';
import '../provider_exception.dart';
import '../provider_transport.dart';
import '../tool_call_normalizer.dart';
import 'adapter_utils.dart';

class OpenAIAdapter implements AIProvider {
  OpenAIAdapter({
    ProviderTransport? transport,
    CredentialStore? credentialStore,
    Uri? baseUri,
    this.defaultTimeout = const Duration(seconds: 60),
  }) : _transport = transport ?? MockProviderTransport(),
       _credentials = ProviderCredentialResolver(
         credentialStore ?? InMemoryCredentialStore(),
       ),
       _baseUri = baseUri ?? Uri.parse('https://api.openai.com/v1');

  static const provider = 'openai';
  final ProviderTransport _transport;
  final ProviderCredentialResolver _credentials;
  final Uri _baseUri;
  final Duration defaultTimeout;

  @override
  String get id => provider;
  @override
  String get displayName => 'OpenAI';
  @override
  Set<ProviderFeature> get features => const {
    ProviderFeature.textGeneration,
    ProviderFeature.streaming,
    ProviderFeature.toolCalling,
    ProviderFeature.structuredOutput,
    ProviderFeature.vision,
    ProviderFeature.jsonMode,
    ProviderFeature.promptCaching,
  };

  static const _models = <AIModel>[
    AIModel(
      id: 'gpt-4o',
      providerId: provider,
      displayName: 'GPT-4o',
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
      id: 'gpt-4o-mini',
      providerId: provider,
      displayName: 'GPT-4o mini',
      features: {
        ProviderFeature.textGeneration,
        ProviderFeature.streaming,
        ProviderFeature.toolCalling,
        ProviderFeature.vision,
        ProviderFeature.jsonMode,
      },
      contextWindowTokens: 128000,
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
    final uri = _baseUri.resolve('chat/completions');
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
        if (raw is Map) {
          final err = raw['error'];
          if (err is Map) {
            final status = raw['status'] as int?;
            final msg = err['message']?.toString() ?? 'OpenAI error';
            throw AdapterHttp.fromStatus(
              status ?? 500,
              providerId: id,
              message: msg,
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
              if (content is String && content.isNotEmpty) {
                yield AITextDeltaEvent(content);
              }
              final tcs = delta['tool_calls'];
              if (tcs is List) {
                for (final tc in tcs) {
                  if (tc is Map) {
                    // streaming deltas may be partial; normalizer tolerates missing args
                    final norm = _safeNormalize(
                      Map<String, Object?>.from(tc),
                      ToolCallNormalizer.fromOpenAi,
                    );
                    if (norm != null) yield AIToolCallEvent(norm);
                  }
                }
              }
              final fc = delta['function_call'];
              if (fc is Map) {
                final norm = _safeNormalize(<String, Object?>{
                  'id': raw['id'] ?? 'call',
                  'function': fc,
                }, ToolCallNormalizer.fromOpenAi);
                if (norm != null) yield AIToolCallEvent(norm);
              }
            }
            final finish = choice['finish_reason'];
            if (finish != null) {
              yield AICompletedEvent(finishReason: finish.toString());
            }
          }
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

  AIToolCall? _safeNormalize(
    Map<String, Object?> raw,
    AIToolCall Function(Map<String, Object?>) fn,
  ) {
    try {
      return fn(raw);
    } catch (_) {
      return null; // partial streaming delta; ignore until complete in real impl
    }
  }
}
