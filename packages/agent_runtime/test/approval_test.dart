import 'package:shadow_agent_runtime/agent_runtime.dart';
import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:test/test.dart';

import 'test_support.dart';

void main() {
  test('dangerous tool requests approval and proceeds when granted', () async {
    final tool = FakeTool(
      name: 'danger',
      riskLevel: ToolRiskLevel.dangerous,
      idempotent: false,
    );
    final executor = FakeToolExecutor([tool]);
    final gate = GrantAllApprovalGate();
    var turn = 0;
    final brain = CallbackAgentBrain(
      onNextDecision:
          ({required plan, required currentStepId, required history}) async {
            turn++;
            if (turn == 1) {
              return ToolCallsDecision([
                const AIToolCall(id: 'c1', name: 'danger', arguments: {'a': 1}),
              ]);
            }
            return const CompleteDecision(summary: 'ok');
          },
    );
    final controller = AgentController(
      brain: brain,
      toolExecutor: executor,
      approvalGate: gate,
    );
    final events = <AgentRuntimeEvent>[];
    controller.events.listen(events.add);
    controller.createTask(
      request: 'x',
      workspaceRoot: '/w',
      projectRevision: 0,
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(events.whereType<ApprovalRequested>().length, 1);
    expect(gate.count, 1);
    expect(tool.calls, 1);
    expect(controller.tasks.first.state, ManagedTaskState.succeeded);
    await controller.dispose();
  });

  test(
    'denied approval is surfaced as tool observation and task can fail/replan',
    () async {
      final tool = FakeTool(
        name: 'danger',
        riskLevel: ToolRiskLevel.dangerous,
        idempotent: false,
      );
      final executor = FakeToolExecutor([tool]);
      final gate = DenyApprovalGate();
      var turn = 0;
      final brain = CallbackAgentBrain(
        onNextDecision:
            ({required plan, required currentStepId, required history}) async {
              turn++;
              if (turn == 1) {
                return ToolCallsDecision([
                  const AIToolCall(id: 'c1', name: 'danger', arguments: {}),
                ]);
              }
              return const FailDecision(
                ShadowErrorCode.permApprovalRequired,
                'denied',
              );
            },
      );
      final controller = AgentController(
        brain: brain,
        toolExecutor: executor,
        approvalGate: gate,
      );
      final events = <AgentRuntimeEvent>[];
      controller.events.listen(events.add);
      controller.createTask(
        request: 'x',
        workspaceRoot: '/w',
        projectRevision: 0,
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(tool.calls, 0);
      expect(events.whereType<ApprovalRequested>().length, 1);
      expect(events.whereType<TaskFailed>().isNotEmpty, isTrue);
      await controller.dispose();
    },
  );
}
