import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:shadow_provider_gateway/provider_gateway.dart';
import 'package:test/test.dart';

void main() {
  test(
    'adapters preserve the configured base path when appending endpoints',
    () async {
      final creds = InMemoryCredentialStore();
      for (final id in <String>[
        'openai',
        'openrouter',
        'anthropic',
        'gemini',
      ]) {
        await creds.saveApiKey(providerId: id, apiKey: 'k');
      }
      final transport = MockProviderTransport(
        handler:
            ({
              required uri,
              required headers,
              required body,
              required stream,
              required timeout,
              required cancel,
            }) => Stream<Object?>.empty(),
      );
      final base = Uri.parse('http://127.0.0.1:9/v1');
      const request = AIRequest(
        model: 'm',
        messages: <AIMessage>[
          AIMessage(role: AIMessageRole.user, content: 'hi'),
        ],
      );

      await OpenAIAdapter(
        transport: transport,
        credentialStore: creds,
        baseUri: base,
      ).stream(request: request, cancel: CancellationToken()).drain<void>();
      await OpenRouterAdapter(
        transport: transport,
        credentialStore: creds,
        baseUri: base,
      ).stream(request: request, cancel: CancellationToken()).drain<void>();
      await AnthropicAdapter(
        transport: transport,
        credentialStore: creds,
        baseUri: base,
      ).stream(request: request, cancel: CancellationToken()).drain<void>();
      await GeminiAdapter(
        transport: transport,
        credentialStore: creds,
        baseUri: base,
      ).stream(request: request, cancel: CancellationToken()).drain<void>();

      expect(transport.requests.map((request) => request.uri.path), <String>[
        '/v1/chat/completions',
        '/v1/chat/completions',
        '/v1/messages',
        '/v1/models/m:streamGenerateContent',
      ]);
      expect(transport.requests.last.uri.queryParameters['alt'], 'sse');
    },
  );
}
