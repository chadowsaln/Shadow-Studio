import 'dart:async';

import 'package:shadow_agent_runtime/agent_runtime.dart';
import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:shadow_provider_gateway/provider_gateway.dart';
import 'package:test/test.dart';

import 'test_support.dart';

const _planningMarker = 'planning stage';

/// Provider that answers the planning prompt with [planText] and every other
/// prompt with the next entry of [decisions].
MockProvider _scriptedProvider({
  required String planText,
  required List<Object?> decisions,
}) {
  var decisionIndex = 0;
  return MockProvider(
    id: 'mock',
    onStream: (request, cancel) async* {
      final system = request.messages.first.content ?? '';
      if (system.contains(_planningMarker)) {
        yield AITextDeltaEvent(planText);
        yield const AICompletedEvent(finishReason: 'stop');
        return;
      }
      final next = decisions[decisionIndex.clamp(0, decisions.length - 1)];
      decisionIndex++;
      if (next is ProviderGatewayException) throw next;
      if (next is List<AIStreamEvent>) {
        yield* Stream<AIStreamEvent>.fromIterable(next);
        return;
      }
      yield AITextDeltaEvent(next as String);
      yield const AICompletedEvent(finishReason: 'stop');
    },
  );
}

ProviderRouter _router(MockProvider provider, {CredentialStore? store}) {
  final credentials = store ?? InMemoryCredentialStore();
  return ProviderRouter(
    providers: <AIProvider>[provider],
    credentialStore: credentials,
  );
}

ProviderAgentBrain _brain(
  ProviderRouter router, {
  List<AgentTool> tools = const <AgentTool>[],
}) {
  return ProviderAgentBrain(
    router: router,
    model: 'mock-model',
    providerId: 'mock',
    tools: tools,
  );
}

Future<void> _withKey(InMemoryCredentialStore store) =>
    store.saveApiKey(providerId: 'mock', apiKey: 'test-key');

void main() {
  group('ProviderAgentBrain plan', () {
    test('parses a JSON plan even when wrapped in markdown', () async {
      final store = InMemoryCredentialStore();
      await _withKey(store);
      final brain = _brain(
        _router(
          _scriptedProvider(
            planText: '''```json
{"steps":[
  {"description":"Probe the source video","expected_outcome":"metadata known"},
  {"description":"Cut a 30s timeline","expected_outcome":"revision bumped"}
]}
```''',
            decisions: const <Object?>[],
          ),
          store: store,
        ),
      );

      final plan = await brain.plan(request: 'Make a 30s ad', taskId: 't1');

      expect(plan.steps, hasLength(2));
      expect(plan.steps.first.description, 'Probe the source video');
      expect(plan.steps.last.expectedOutcome, 'revision bumped');
      expect(plan.goal, 'Make a 30s ad');
    });

    test(
      'falls back to the deterministic planner on unusable output',
      () async {
        final store = InMemoryCredentialStore();
        await _withKey(store);
        final brain = _brain(
          _router(
            _scriptedProvider(
              planText: 'I think we should probably start with the footage.',
              decisions: const <Object?>[],
            ),
            store: store,
          ),
        );

        final plan = await brain.plan(request: 'Make a 30s ad', taskId: 't1');

        expect(plan.steps, hasLength(1));
        expect(plan.steps.single.description, contains('Make a 30s ad'));
      },
    );

    test('falls back when the provider has no credentials', () async {
      final brain = _brain(
        _router(
          _scriptedProvider(planText: '{}', decisions: const <Object?>[]),
        ),
      );

      final plan = await brain.plan(request: 'Make a 30s ad', taskId: 't1');

      expect(plan.steps, hasLength(1));
    });
  });

  group('ProviderAgentBrain nextDecision', () {
    test('parses a tool_calls decision from text', () async {
      final store = InMemoryCredentialStore();
      await _withKey(store);
      final brain = _brain(
        _router(
          _scriptedProvider(
            planText: '{}',
            decisions: <Object?>[
              '{"action":"tool_calls","calls":[{"name":"media_probe",'
                  '"arguments":{"path":"intro-4k.mp4"}}]}',
            ],
          ),
          store: store,
        ),
        tools: <AgentTool>[FakeTool(name: 'media_probe')],
      );

      final decision = await brain.nextDecision(
        plan: AgentPlan(goal: 'probe', revision: 1, steps: const <PlanStep>[]),
        currentStepId: 'step_1',
        history: const <AIMessage>[],
      );

      expect(decision, isA<ToolCallsDecision>());
      final calls = (decision as ToolCallsDecision).calls;
      expect(calls.single.name, 'media_probe');
      expect(calls.single.arguments['path'], 'intro-4k.mp4');
    });

    test('prefers native provider tool calls over text', () async {
      final store = InMemoryCredentialStore();
      await _withKey(store);
      final brain = _brain(
        _router(
          _scriptedProvider(
            planText: '{}',
            decisions: <Object?>[
              <AIStreamEvent>[
                const AIToolCallEvent(
                  AIToolCall(
                    id: 'native_1',
                    name: 'media_probe',
                    arguments: {},
                  ),
                ),
                const AICompletedEvent(finishReason: 'tool_calls'),
              ],
            ],
          ),
          store: store,
        ),
      );

      final decision = await brain.nextDecision(
        plan: AgentPlan(goal: 'probe', revision: 1, steps: const <PlanStep>[]),
        currentStepId: 'step_1',
        history: const <AIMessage>[],
      );

      expect(decision, isA<ToolCallsDecision>());
      expect(((decision as ToolCallsDecision).calls.single.id), 'native_1');
    });

    test('parses a complete decision with a result payload', () async {
      final store = InMemoryCredentialStore();
      await _withKey(store);
      final brain = _brain(
        _router(
          _scriptedProvider(
            planText: '{}',
            decisions: <Object?>[
              '{"action":"complete","summary":"Ad delivered",'
                  '"result":{"output":"out/ad.mp4","revision":4}}',
            ],
          ),
          store: store,
        ),
      );

      final decision = await brain.nextDecision(
        plan: AgentPlan(goal: 'ship', revision: 1, steps: const <PlanStep>[]),
        currentStepId: 'step_1',
        history: const <AIMessage>[],
      );

      expect(decision, isA<CompleteDecision>());
      final complete = decision as CompleteDecision;
      expect(complete.summary, 'Ad delivered');
      expect(complete.result['revision'], 4);
    });

    test('parses a fail decision', () async {
      final store = InMemoryCredentialStore();
      await _withKey(store);
      final brain = _brain(
        _router(
          _scriptedProvider(
            planText: '{}',
            decisions: <Object?>[
              '{"action":"fail","code":"MEDIA_CORRUPT","message":"source is broken"}',
            ],
          ),
          store: store,
        ),
      );

      final decision = await brain.nextDecision(
        plan: AgentPlan(goal: 'ship', revision: 1, steps: const <PlanStep>[]),
        currentStepId: 'step_1',
        history: const <AIMessage>[],
      );

      expect(decision, isA<FailDecision>());
      expect(((decision as FailDecision)).code, 'MEDIA_CORRUPT');
    });

    test(
      'rejects a malformed tool_calls decision instead of succeeding',
      () async {
        final store = InMemoryCredentialStore();
        await _withKey(store);
        final brain = _brain(
          _router(
            _scriptedProvider(
              planText: '{}',
              decisions: const <Object?>['{"action":"tool_calls","calls":[]}'],
            ),
            store: store,
          ),
        );

        final decision = await brain.nextDecision(
          plan: AgentPlan(goal: 'ship', revision: 1, steps: const <PlanStep>[]),
          currentStepId: 'step_1',
          history: const <AIMessage>[],
        );

        expect(decision, isA<FailDecision>());
        expect(
          ((decision as FailDecision)).code,
          ShadowErrorCode.providerToolCallMalformed,
        );
      },
    );

    test('treats plain prose as a completion summary', () async {
      final store = InMemoryCredentialStore();
      await _withKey(store);
      final brain = _brain(
        _router(
          _scriptedProvider(
            planText: '{}',
            decisions: const <Object?>['The timeline is ready.'],
          ),
          store: store,
        ),
      );

      final decision = await brain.nextDecision(
        plan: AgentPlan(goal: 'ship', revision: 1, steps: const <PlanStep>[]),
        currentStepId: 'step_1',
        history: const <AIMessage>[],
      );

      expect(decision, isA<CompleteDecision>());
      expect(
        ((decision as CompleteDecision)).summary,
        'The timeline is ready.',
      );
    });

    test('surfaces provider auth failures', () async {
      final brain = _brain(
        _router(
          _scriptedProvider(planText: '{}', decisions: const <Object?>[]),
        ),
      );

      await expectLater(
        brain.nextDecision(
          plan: AgentPlan(goal: 'ship', revision: 1, steps: const <PlanStep>[]),
          currentStepId: 'step_1',
          history: const <AIMessage>[],
        ),
        throwsA(isA<ProviderAgentBrainException>()),
      );
    });
  });

  group('ProviderAgentBrain replan', () {
    test('produces a revised plan from provider steps', () async {
      final store = InMemoryCredentialStore();
      await _withKey(store);
      final brain = _brain(
        _router(
          _scriptedProvider(
            planText:
                '{"steps":[{"description":"Retry with a shorter probe"}]}',
            decisions: const <Object?>[],
          ),
          store: store,
        ),
      );

      final replanned = await brain.replan(
        currentPlan: AgentPlan(
          goal: 'ship',
          revision: 2,
          steps: const <PlanStep>[],
        ),
        taskId: 't1',
        failureReason: 'probe timed out',
        recentObservations: const <ToolResult>[],
      );

      expect(replanned.revision, 3);
      expect(replanned.steps.single.description, 'Retry with a shorter probe');
    });

    test(
      'falls back to the default planner when replanning output is junk',
      () async {
        final store = InMemoryCredentialStore();
        await _withKey(store);
        final brain = _brain(
          _router(
            _scriptedProvider(planText: 'no json here', decisions: const []),
            store: store,
          ),
        );

        final replanned = await brain.replan(
          currentPlan: AgentPlan(
            goal: 'ship',
            revision: 1,
            steps: const <PlanStep>[],
          ),
          taskId: 't1',
          failureReason: 'boom',
          recentObservations: const <ToolResult>[],
        );

        expect(replanned.revision, 2);
      },
    );
  });
}
