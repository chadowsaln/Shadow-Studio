import 'dart:convert';

import 'package:shadow_agent_runtime/agent_runtime.dart';
import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:shadow_provider_gateway/provider_gateway.dart';
import 'package:test/test.dart';

import 'test_support.dart';

void main() {
  group('Agent context snapshot', () {
    test(
      'loop rebuilds a budgeted snapshot and emits ContextUpdated',
      () async {
        final holder = AgentContextHolder();
        final tool = FakeTool(name: 'scan');
        final executor = FakeToolExecutor([tool]);
        var turn = 0;
        final brain = CallbackAgentBrain(
          onNextDecision:
              ({
                required plan,
                required currentStepId,
                required history,
              }) async {
                turn++;
                if (turn == 1) {
                  return ToolCallsDecision([
                    AIToolCall(
                      id: 'c1',
                      name: 'scan',
                      arguments: const {'x': 1},
                    ),
                  ]);
                }
                return const CompleteDecision(summary: 'done');
              },
        );
        final controller = AgentController(
          brain: brain,
          toolExecutor: executor,
          contextHolder: holder,
        );
        final events = <AgentRuntimeEvent>[];
        controller.events.listen(events.add);

        final task = controller.createTask(
          request: 'scan the workspace',
          workspaceRoot: '/w',
          projectRevision: 3,
          metadata: const <String, Object?>{
            'media_assets': <Map<String, Object?>>[
              {
                'id': 'a1',
                'name': 'clip.mp4',
                'duration_ticks': 100,
                'bytes': 'AA',
              },
            ],
          },
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));

        final snapshot = controller.contextSnapshot;
        expect(snapshot, isNotNull);
        expect(snapshot!.projectId, task.id);
        expect(snapshot.projectRevision, 3);
        expect(
          snapshot.estimatedTokens,
          lessThanOrEqualTo(snapshot.tokenBudget),
        );
        expect(snapshot.mediaAssets, hasLength(1));
        expect(
          jsonEncode(snapshot.mediaAssets).contains('"bytes"'),
          isFalse,
          reason: 'raw media bytes must never enter context',
        );
        expect(
          snapshot.previousToolExecutionResults,
          isNotEmpty,
          reason: 'the executed scan result is part of the next turn',
        );
        expect(
          events.whereType<ContextUpdated>(),
          isNotEmpty,
          reason: 'one ContextUpdated per tool result',
        );
      },
    );

    test('controller clears the snapshot before a new task turn', () async {
      final holder = AgentContextHolder();
      final brain = CallbackAgentBrain(
        onNextDecision:
            ({required plan, required currentStepId, required history}) async =>
                const CompleteDecision(summary: 'done'),
      );
      final controller = AgentController(
        brain: brain,
        toolExecutor: FakeToolExecutor(const <AgentTool>[]),
        contextHolder: holder,
      );

      controller.createTask(
        request: 'a',
        workspaceRoot: '/w',
        projectRevision: 1,
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(controller.contextSnapshot, isNull);

      controller.createTask(
        request: 'b',
        workspaceRoot: '/w',
        projectRevision: 1,
      );
      expect(controller.contextSnapshot, isNull);
    });
  });

  group('ProviderAgentBrain context', () {
    test('decision prompt carries the compact project context', () async {
      final holder = AgentContextHolder();
      var decisionPrompt = '';
      final provider = MockProvider(
        id: 'mock',
        onStream: (request, cancel) async* {
          final content = request.messages.map((m) => m.content).join('\n');
          if (content.contains('execution stage')) {
            decisionPrompt = content;
            yield const AITextDeltaEvent(
              '{"action":"complete","summary":"ok"}',
            );
            yield const AICompletedEvent(finishReason: 'stop');
            return;
          }
          yield const AITextDeltaEvent('{"steps":[]}');
          yield const AICompletedEvent(finishReason: 'stop');
        },
      );
      final store = InMemoryCredentialStore();
      await store.saveApiKey(providerId: 'mock', apiKey: 'test-key');
      final router = ProviderRouter(
        providers: <AIProvider>[provider],
        credentialStore: store,
      );
      final brain = ProviderAgentBrain(
        router: router,
        model: 'mock-model',
        providerId: 'mock',
        context: holder,
      );

      final plan = await brain.plan(request: 'x', taskId: 't1');
      await brain.nextDecision(
        plan: plan,
        currentStepId: plan.steps.isEmpty ? '' : plan.steps.first.id,
        history: const <AIMessage>[],
      );

      expect(decisionPrompt, isNotEmpty);
      expect(decisionPrompt, contains('project_context'));
      expect(decisionPrompt, isNot(contains('"bytes"')));
    });
  });
}
