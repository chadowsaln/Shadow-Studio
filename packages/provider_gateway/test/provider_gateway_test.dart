import 'dart:async';

import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:shadow_provider_gateway/provider_gateway.dart';
import 'package:test/test.dart';

void main() {
  group('Unified contracts re-exported/available', () {
    test('AIRequest/AIResponse/AIMessage/AIModel/AIToolDefinition/AIToolCall/AIStreamEvent/ProviderFeature/RequestBudget types exist', () {
      const req = AIRequest(model: 'm', messages: [AIMessage(role: AIMessageRole.user, content: 'hi')]);
      const resp = AIResponse(providerId: 'p', model: 'm', messages: []);
      const model = AIModel(id: 'm', providerId: 'p', displayName: 'M', features: {ProviderFeature.textGeneration});
      const tool = AIToolDefinition(name: 't', description: 'd', inputSchema: {'type': 'object', 'properties': {}});
      const call = AIToolCall(id: 'c', name: 't', arguments: {});
      const ev = AITextDeltaEvent('x');
      const budget = RequestBudget(maxInputTokens: 10);
      expect(req.model, 'm');
      expect(resp.providerId, 'p');
      expect(model.supports(ProviderFeature.textGeneration), isTrue);
      expect(tool.name, 't');
      expect(call.name, 't');
      expect(ev, isA<AIStreamEvent>());
      expect(budget.maxInputTokens, 10);
    });
  });

  group('Mock provider streaming & tool calls', () {
    test('streams text and normalized tool calls', () async {
      final creds = InMemoryCredentialStore();
      await creds.saveApiKey(providerId: 'mock', apiKey: 'test-key');
      final mock = MockProvider(
        id: 'mock',
        models: const [
          AIModel(id: 'mock-model', providerId: 'mock', displayName: 'Mock', features: {ProviderFeature.streaming, ProviderFeature.toolCalling, ProviderFeature.textGeneration}, contextWindowTokens: 1000)
        ],
        onStream: (req, cancel) async* {
          yield const AITextDeltaEvent('hello');
          yield const AIToolCallEvent(AIToolCall(id: 'tc1', name: 'do', arguments: {'a': 1}));
          yield const AICompletedEvent(finishReason: 'tool_calls', usage: TokenUsage(inputTokens: 5, outputTokens: 3, totalTokens: 8));
        },
      );
      final router = ProviderRouter(providers: [mock], credentialStore: creds);
      final req = const AIRequest(model: 'mock-model', messages: [AIMessage(role: AIMessageRole.user, content: 'hi')]);
      final events = await router.stream(request: req, providerId: 'mock', cancel: CancellationToken()).toList();
      expect(events.whereType<AITextDeltaEvent>().single.delta, 'hello');
      expect(events.whereType<AIToolCallEvent>().single.call.name, 'do');
      expect(events.whereType<AICompletedEvent>().single.finishReason, 'tool_calls');
    });
  });

  group('Capability detection & model selection', () {
    test('omits tools when model lacks tool calling and selects capable model', () async {
      final creds = InMemoryCredentialStore();
      await creds.saveApiKey(providerId: 'p', apiKey: 'k');
      final p = MockProvider(id: 'p', models: const [
        AIModel(id: 'plain', providerId: 'p', displayName: 'Plain', features: {ProviderFeature.streaming, ProviderFeature.textGeneration}),
        AIModel(id: 'tools', providerId: 'p', displayName: 'Tools', features: {ProviderFeature.streaming, ProviderFeature.textGeneration, ProviderFeature.toolCalling}),
      ], onStream: (req, cancel) async* {
        yield AICompletedEvent(finishReason: 'stop', usage: const TokenUsage(inputTokens: 1, outputTokens: 1));
      });
      final router = ProviderRouter(providers: [p], credentialStore: creds);
      // explicit plain model: tools omitted per capability map
      final req = AIRequest(model: 'plain', messages: const [AIMessage(role: AIMessageRole.user, content: 'hi')], tools: const [
        AIToolDefinition(name: 't', description: 'd', inputSchema: {'type': 'object'})
      ]);
      await router.stream(request: req, providerId: 'p', cancel: CancellationToken()).drain<void>();
      expect(p.requests.single.tools, isEmpty);
      expect(p.requests.single.metadata['tools_omitted'], isTrue);

      final target = await router.resolveTarget(providerId: 'p', requiredFeatures: {ProviderFeature.toolCalling}, cancel: CancellationToken());
      expect(target.model.id, 'tools');
    });

    test('rejects vision request for model without vision', () async {
      final creds = InMemoryCredentialStore();
      await creds.saveApiKey(providerId: 'p', apiKey: 'k');
      final p = MockProvider(id: 'p', models: const [
        AIModel(id: 'novision', providerId: 'p', displayName: 'NV', features: {ProviderFeature.streaming, ProviderFeature.textGeneration}),
      ]);
      final router = ProviderRouter(providers: [p], credentialStore: creds);
      final req = const AIRequest(model: 'novision', messages: [AIMessage(role: AIMessageRole.user, content: 'hi', metadata: {'has_vision': true})]);
      await expectLater(
        router.stream(request: req, providerId: 'p', cancel: CancellationToken()).drain<void>(),
        throwsA(isA<ProviderGatewayException>().having((e) => e.code, 'code', ShadowErrorCode.providerUnsupported)),
      );
    });
  });

  group('Fallback policy', () {
    test('falls back on 5xx/network retryable errors', () async {
      final creds = InMemoryCredentialStore();
      await creds.saveApiKey(providerId: 'a', apiKey: 'k1');
      await creds.saveApiKey(providerId: 'b', apiKey: 'k2');
      final bad = MockProvider(id: 'a', models: const [AIModel(id: 'm', providerId: 'a', displayName: 'A', features: {ProviderFeature.streaming, ProviderFeature.textGeneration})],
        failWith: ProviderGatewayException(code: ShadowErrorCode.providerRateLimit, message: 'boom', retryable: true, statusCode: 500, providerId: 'a'));
      final good = MockProvider(id: 'b', models: const [AIModel(id: 'm', providerId: 'b', displayName: 'B', features: {ProviderFeature.streaming, ProviderFeature.textGeneration})]);
      final router = ProviderRouter(providers: [bad, good], credentialStore: creds);
      final req = const AIRequest(model: 'm', messages: [AIMessage(role: AIMessageRole.user, content: 'hi')]);
      final events = await router.stream(request: req, providerId: 'a', fallbackProviderIds: ['b'], cancel: CancellationToken()).toList();
      expect(events.whereType<AITextDeltaEvent>(), isNotEmpty);
      expect(good.requests.length, 1);
    });

    test('does NOT fallback on authentication errors', () async {
      final creds = InMemoryCredentialStore();
      await creds.saveApiKey(providerId: 'a', apiKey: 'k1');
      await creds.saveApiKey(providerId: 'b', apiKey: 'k2');
      final bad = MockProvider(id: 'a', models: const [AIModel(id: 'm', providerId: 'a', displayName: 'A', features: {ProviderFeature.streaming, ProviderFeature.textGeneration})],
        failWith: ProviderGatewayException(code: ShadowErrorCode.providerAuth, message: 'bad key', retryable: false, statusCode: 401, providerId: 'a'));
      final good = MockProvider(id: 'b', models: const [AIModel(id: 'm', providerId: 'b', displayName: 'B', features: {ProviderFeature.streaming, ProviderFeature.textGeneration})]);
      final router = ProviderRouter(providers: [bad, good], credentialStore: creds);
      final req = const AIRequest(model: 'm', messages: [AIMessage(role: AIMessageRole.user, content: 'hi')]);
      await expectLater(
        router.stream(request: req, providerId: 'a', fallbackProviderIds: ['b'], cancel: CancellationToken()).drain<void>(),
        throwsA(isA<ProviderGatewayException>().having((e) => e.code, 'code', ShadowErrorCode.providerAuth)),
      );
      expect(good.requests, isEmpty);
    });
  });

  group('Budgets, accounting, timeout, cancellation', () {
    test('enforces input budget pre-request', () async {
      final creds = InMemoryCredentialStore();
      await creds.saveApiKey(providerId: 'p', apiKey: 'k');
      final p = MockProvider(id: 'p');
      final router = ProviderRouter(providers: [p], credentialStore: creds, accounting: ProviderBudgetAccounting(maxInputTokensPerTask: 5));
      final req = const AIRequest(model: 'p-model', messages: [AIMessage(role: AIMessageRole.user, content: 'this is a long message that should exceed tiny budget')]);
      await expectLater(
        router.stream(request: req, providerId: 'p', cancel: CancellationToken()).drain<void>(),
        throwsA(isA<BudgetExceededException>()),
      );
    });

    test('accounts token usage post-stream', () async {
      final creds = InMemoryCredentialStore();
      await creds.saveApiKey(providerId: 'p', apiKey: 'k');
      final p = MockProvider(id: 'p', onStream: (r, c) async* {
        yield const AICompletedEvent(finishReason: 'stop', usage: TokenUsage(inputTokens: 10, outputTokens: 5, totalTokens: 15));
      });
      final acc = ProviderBudgetAccounting();
      final router = ProviderRouter(providers: [p], credentialStore: creds, accounting: acc);
      await router.stream(request: const AIRequest(model: 'p-model', messages: [AIMessage(role: AIMessageRole.user, content: 'hi')]), providerId: 'p', cancel: CancellationToken()).drain<void>();
      expect(acc.inputTokensUsed, 10);
      expect(acc.outputTokensUsed, 5);
    });

    test('cancellation stops stream', () async {
      final creds = InMemoryCredentialStore();
      await creds.saveApiKey(providerId: 'p', apiKey: 'k');
      final p = MockProvider(id: 'p', onStream: (r, c) async* {
        yield const AITextDeltaEvent('a');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        c.throwIfCancelled();
        yield const AITextDeltaEvent('b');
      });
      final router = ProviderRouter(providers: [p], credentialStore: creds);
      final cancel = CancellationToken();
      final fut = router.stream(request: const AIRequest(model: 'p-model', messages: [AIMessage(role: AIMessageRole.user, content: 'hi')]), providerId: 'p', cancel: cancel).toList();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      cancel.cancel('stop');
      await expectLater(fut, throwsA(anyOf(isA<ProviderCancelledException>(), isA<CancelledException>())));
    });

    test('timeout surfaces retryable provider error', () async {
      final creds = InMemoryCredentialStore();
      await creds.saveApiKey(providerId: 'p', apiKey: 'k');
      final p = MockProvider(id: 'p', latency: const Duration(milliseconds: 200));
      final router = ProviderRouter(providers: [p], credentialStore: creds, defaultTimeout: const Duration(milliseconds: 20));
      await expectLater(
        router.stream(request: const AIRequest(model: 'p-model', messages: [AIMessage(role: AIMessageRole.user, content: 'hi')]), providerId: 'p', cancel: CancellationToken()).drain<void>(),
        throwsA(isA<ProviderGatewayException>().having((e) => e.retryable, 'retryable', isTrue)),
      );
    });
  });

  group('Security: credentials and egress consent', () {
    test('missing API key fails with auth error (no silent fallback)', () async {
      final p = MockProvider(id: 'p');
      final router = ProviderRouter(providers: [p], credentialStore: InMemoryCredentialStore());
      await expectLater(
        router.stream(request: const AIRequest(model: 'p-model', messages: [AIMessage(role: AIMessageRole.user, content: 'hi')]), providerId: 'p', cancel: CancellationToken()).drain<void>(),
        throwsA(isA<ProviderGatewayException>().having((e) => e.code, 'code', ShadowErrorCode.providerAuth)),
      );
    });

    test('requires explicit egress consent before sending media/file payloads', () async {
      final creds = InMemoryCredentialStore();
      await creds.saveApiKey(providerId: 'p', apiKey: 'k');
      final p = MockProvider(id: 'p', models: const [AIModel(id: 'm', providerId: 'p', displayName: 'M', features: {ProviderFeature.streaming, ProviderFeature.textGeneration, ProviderFeature.vision})]);
      final router = ProviderRouter(providers: [p], credentialStore: creds, egressConsent: const DenyAllEgressConsentService());
      final req = const AIRequest(model: 'm', messages: [AIMessage(role: AIMessageRole.user, content: 'see', metadata: {'egress_payloads': [{'kind': 'image', 'ref': 'frame.png'}]})]);
      await expectLater(
        router.stream(request: req, providerId: 'p', cancel: CancellationToken()).drain<void>(),
        throwsA(isA<EgressConsentRequiredException>()),
      );
      expect(p.requests, isEmpty);

      final okRouter = ProviderRouter(providers: [p], credentialStore: creds, egressConsent: const AllowAllEgressConsentService());
      await okRouter.stream(request: req, providerId: 'p', cancel: CancellationToken()).drain<void>();
      expect(p.requests.length, 1);
    });
  });

  group('Tool call normalization', () {
    test('normalizes OpenAI/Anthropic/Gemini tool call shapes', () {
      final openai = ToolCallNormalizer.fromOpenAi({'id': '1', 'function': {'name': 'a', 'arguments': '{"x":1}'}});
      expect(openai.name, 'a');
      expect(openai.arguments['x'], 1);
      final anthropic = ToolCallNormalizer.fromAnthropic({'id': '2', 'name': 'b', 'input': {'y': 2}});
      expect(anthropic.name, 'b');
      expect(anthropic.arguments['y'], 2);
      final gemini = ToolCallNormalizer.fromGemini({'name': 'c', 'args': {'z': 3}});
      expect(gemini.name, 'c');
      expect(gemini.arguments['z'], 3);
    });
  });
}
