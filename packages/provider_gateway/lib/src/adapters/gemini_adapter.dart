import 'dart:async';

import 'package:shadow_contracts/shadow_contracts.dart';

import '../credential_store.dart';
import '../provider_exception.dart';
import '../provider_transport.dart';
import '../tool_call_normalizer.dart';
import 'adapter_utils.dart';

class GeminiAdapter implements AIProvider {
  GeminiAdapter({
    ProviderTransport? transport,
    CredentialStore? credentialStore,
    Uri? baseUri,
    this.defaultTimeout = const Duration(seconds: 60),
  }) : _transport = transport ?? MockProviderTransport(),
       _credentials = ProviderCredentialResolver(
         credentialStore ?? InMemoryCredentialStore(),
       ),
       _baseUri =
           baseUri ??
           Uri.parse('https://generativelanguage.googleapis.com/v1beta');

  static const provider = 'gemini';
  final ProviderTransport _transport;
  final ProviderCredentialResolver _credentials;
  final Uri _baseUri;
  final Duration defaultTimeout;

  @override
  String get id => provider;
  @override
  String get displayName => 'Google Gemini';
  @override
  Set<ProviderFeature> get features => const {
    ProviderFeature.textGeneration,
    ProviderFeature.streaming,
    ProviderFeature.toolCalling,
    ProviderFeature.vision,
    ProviderFeature.jsonMode,
    ProviderFeature.promptCaching,
  };

  static const _models = <AIModel>[
    AIModel(
      id: 'gemini-1.5-pro',
      providerId: provider,
      displayName: 'Gemini 1.5 Pro',
      features: {
        ProviderFeature.textGeneration,
        ProviderFeature.streaming,
        ProviderFeature.toolCalling,
        ProviderFeature.vision,
        ProviderFeature.jsonMode,
      },
      contextWindowTokens: 2000000,
    ),
    AIModel(
      id: 'gemini-1.5-flash',
      providerId: provider,
      displayName: 'Gemini 1.5 Flash',
      features: {
        ProviderFeature.textGeneration,
        ProviderFeature.streaming,
        ProviderFeature.toolCalling,
        ProviderFeature.vision,
        ProviderFeature.jsonMode,
      },
      contextWindowTokens: 1000000,
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
    final uri = resolveProviderEndpoint(
      _baseUri,
      'models/${request.model}:streamGenerateContent',
    ).replace(queryParameters: {'key': key, 'alt': 'sse'});
    final body = _body(request);
    final headers = <String, String>{'Content-Type': 'application/json'};
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
        final err = raw['error'];
        if (err is Map) {
          throw ProviderGatewayException(
            code: ShadowErrorCode.providerStreamBroken,
            message: err['message']?.toString() ?? 'Gemini error',
            retryable: false,
            providerId: id,
          );
        }
        final usage = raw['usageMetadata'];
        if (usage is Map) {
          yield AIUsageEvent(
            TokenUsage(
              inputTokens: usage['promptTokenCount'] as int?,
              outputTokens: usage['candidatesTokenCount'] as int?,
              totalTokens: usage['totalTokenCount'] as int?,
            ),
          );
        }
        final candidates = raw['candidates'];
        if (candidates is List && candidates.isNotEmpty) {
          final cand = candidates.first as Map;
          final content = cand['content'];
          if (content is Map) {
            final parts = content['parts'];
            if (parts is List) {
              for (final part in parts) {
                if (part is! Map) continue;
                if (part['text'] is String)
                  yield AITextDeltaEvent(part['text'] as String);
                final fc = part['functionCall'];
                if (fc is Map) {
                  yield AIToolCallEvent(
                    ToolCallNormalizer.fromGemini(
                      Map<String, Object?>.from(fc),
                    ),
                  );
                }
              }
            }
          }
          final finish = cand['finishReason'];
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

  Map<String, Object?> _body(AIRequest request) {
    final contents = <Map<String, Object?>>[];
    String? system;
    for (final m in request.messages) {
      if (m.role == AIMessageRole.system) {
        system = (system == null)
            ? (m.content ?? '')
            : '$system\n${m.content ?? ''}';
        continue;
      }
      if (m.role == AIMessageRole.tool) {
        contents.add({
          'role': 'user',
          'parts': [
            {
              'functionResponse': {
                'name': m.name ?? 'tool',
                'response': {
                  'content': m.content ?? '',
                  'tool_call_id': m.toolCallId,
                },
              },
            },
          ],
        });
        continue;
      }
      final role = m.role == AIMessageRole.assistant ? 'model' : 'user';
      final parts = <Map<String, Object?>>[];
      if (m.content != null && m.content!.isNotEmpty)
        parts.add({'text': m.content});
      for (final tc in m.toolCalls) {
        parts.add({
          'functionCall': {'name': tc.name, 'args': tc.arguments},
        });
      }
      contents.add({
        'role': role,
        'parts': parts.isEmpty
            ? [
                {'text': ''},
              ]
            : parts,
      });
    }
    final body = <String, Object?>{
      'contents': contents,
      'generationConfig': {
        'temperature': request.temperature,
        'maxOutputTokens': request.maxOutputTokens,
      },
    };
    if (system != null) {
      body['systemInstruction'] = {
        'parts': [
          {'text': system},
        ],
      };
    }
    if (request.tools.isNotEmpty) {
      body['tools'] = [
        {
          'functionDeclarations': [
            for (final t in request.tools)
              {
                'name': t.name,
                'description': t.description,
                'parameters': t.inputSchema,
              },
          ],
        },
      ];
    }
    return body;
  }
}
