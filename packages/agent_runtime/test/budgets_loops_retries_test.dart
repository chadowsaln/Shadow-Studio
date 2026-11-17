import 'package:shadow_agent_runtime/agent_runtime.dart';
import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:test/test.dart';

import 'test_support.dart';

void main() {
  test('enforces max tool calls budget in code', () async {
    final tool = FakeTool(name: 't');
    final executor = FakeToolExecutor([tool]);
    var n = 0;
    final brain = CallbackAgentBrain(
      onNextDecision:
          ({required plan, required currentStepId, required history}) async {
            n++;
            return ToolCallsDecision([
              AIToolCall(id: 'c$n', name: 't', arguments: {'n': n}),
            ]);
          },
    );
    final controller = AgentController(
      brain: brain,
      toolExecutor: executor,
      limits: const AgentRuntimeLimits(
        maxToolCalls: 2,
        maxConsecutiveIdenticalToolCalls: 10,
      ),
    );
    final events = <AgentRuntimeEvent>[];
    controller.events.listen(events.add);
    controller.createTask(
      request: 'x',
      workspaceRoot: '/w',
      projectRevision: 0,
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final failed = events.whereType<TaskFailed>().first;
    expect(failed.code, ShadowErrorCode.agentBudgetExceeded);
    expect(tool.calls, 2);
    await controller.dispose();
  });

  test('detects 3 consecutive identical tool calls', () async {
    final tool = FakeTool(name: 't');
    final executor = FakeToolExecutor([tool]);
    final brain = CallbackAgentBrain(
      onNextDecision:
          ({required plan, required currentStepId, required history}) async {
            return ToolCallsDecision([
              const AIToolCall(id: 'same', name: 't', arguments: {'k': 1}),
            ]);
          },
    );
    final controller = AgentController(
      brain: brain,
      toolExecutor: executor,
      limits: const AgentRuntimeLimits(
        maxConsecutiveIdenticalToolCalls: 3,
        maxToolCalls: 40,
      ),
    );
    final events = <AgentRuntimeEvent>[];
    controller.events.listen(events.add);
    controller.createTask(
      request: 'x',
      workspaceRoot: '/w',
      projectRevision: 0,
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final failed = events.whereType<TaskFailed>().first;
    expect(failed.code, ShadowErrorCode.agentLoopDetected);
    // 1st executes, 2nd executes, 3rd detected before execution
    expect(tool.calls, 2);
    await controller.dispose();
  });

  test('retries idempotent tool up to 3 times (4 attempts total)', () async {
    final tool = FakeTool(
      name: 'flaky',
      idempotent: true,
      handler: (ctx, args) async =>
          const ToolResult(success: false, errorCode: 'X', errorMessage: 'no'),
    );
    final executor = FakeToolExecutor([tool]);
    var decisions = 0;
    final brain = CallbackAgentBrain(
      onNextDecision:
          ({required plan, required currentStepId, required history}) async {
            decisions++;
            if (decisions == 1) {
              return ToolCallsDecision([
                const AIToolCall(id: 'c1', name: 'flaky', arguments: {}),
              ]);
            }
            return const FailDecision(ShadowErrorCode.toolFailed, 'stop');
          },
    );
    final controller = AgentController(
      brain: brain,
      toolExecutor: executor,
      limits: const AgentRuntimeLimits(maxRetriesPerTool: 3),
    );
    controller.createTask(
      request: 'x',
      workspaceRoot: '/w',
      projectRevision: 0,
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(tool.calls, 4);
    await controller.dispose();
  });

  test('does not retry non-idempotent tool', () async {
    final tool = FakeTool(
      name: 'once',
      idempotent: false,
      handler: (ctx, args) async =>
          const ToolResult(success: false, errorCode: 'X', errorMessage: 'no'),
    );
    final executor = FakeToolExecutor([tool]);
    var decisions = 0;
    final brain = CallbackAgentBrain(
      onNextDecision:
          ({required plan, required currentStepId, required history}) async {
            decisions++;
            if (decisions == 1) {
              return ToolCallsDecision([
                const AIToolCall(id: 'c1', name: 'once', arguments: {}),
              ]);
            }
            return const FailDecision(ShadowErrorCode.toolFailed, 'stop');
          },
    );
    final controller = AgentController(brain: brain, toolExecutor: executor);
    controller.createTask(
      request: 'x',
      workspaceRoot: '/w',
      projectRevision: 0,
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(tool.calls, 1);
    await controller.dispose();
  });

  test('enforces max task duration', () async {
    final tool = FakeTool(
      name: 't',
      handler: (ctx, args) async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        return const ToolResult(success: true);
      },
    );
    final executor = FakeToolExecutor([tool]);
    var n = 0;
    final brain = CallbackAgentBrain(
      onNextDecision:
          ({required plan, required currentStepId, required history}) async {
            n++;
            return ToolCallsDecision([
              AIToolCall(id: 'c$n', name: 't', arguments: {'n': n}),
            ]);
          },
    );
    final controller = AgentController(
      brain: brain,
      toolExecutor: executor,
      limits: const AgentRuntimeLimits(
        maxDuration: Duration(milliseconds: 50),
        maxConsecutiveIdenticalToolCalls: 10,
        maxToolCalls: 40,
      ),
    );
    final events = <AgentRuntimeEvent>[];
    controller.events.listen(events.add);
    controller.createTask(
      request: 'x',
      workspaceRoot: '/w',
      projectRevision: 0,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      events.whereType<TaskFailed>().any(
        (e) => e.code == ShadowErrorCode.agentTimeout,
      ),
      isTrue,
    );
    await controller.dispose();
  });
}
