import 'package:shadow_agent_runtime/agent_runtime.dart';
import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:test/test.dart';

import 'test_support.dart';

void main() {
  group('RecoveryManager', () {
    test('saves checkpoint after every tool call with context hash', () async {
      final tool = FakeTool(name: 'scan');
      final executor = FakeToolExecutor([tool]);
      var turn = 0;
      final brain = CallbackAgentBrain(onNextDecision: ({required plan, required currentStepId, required history}) async {
        turn++;
        if (turn <= 2) {
          return ToolCallsDecision([AIToolCall(id: 'c$turn', name: 'scan', arguments: {'i': turn})]);
        }
        return const CompleteDecision(summary: 'ok');
      });
      final recovery = RecoveryManager();
      final controller = AgentController(brain: brain, toolExecutor: executor, recoveryManager: recovery);
      final task = controller.createTask(request: 'x', workspaceRoot: '/ws', projectRevision: 7);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final cp = await recovery.restore(task.id);
      expect(cp, isNotNull);
      expect(cp!.toolCallCount, 2);
      expect(cp.projectRevision, 7);
      expect(cp.workspaceRoot, '/ws');
      expect(cp.contextHash, isNotEmpty);
      expect(cp.lastToolName, 'scan');
      expect(cp.lastToolIdempotent, isTrue);
      await controller.dispose();
    });

    test('detects invalid project revision on restore', () async {
      final recovery = RecoveryManager();
      final context = AgentContext(taskId: 't1', workspaceRoot: '/w', projectRevision: 5);
      final plan = AgentPlan(steps: const [PlanStep(id: 's', description: 'd', expectedOutcome: 'e')], revision: 1);
      await recovery.saveAfterToolCall(
        taskId: 't1',
        context: context,
        plan: plan,
        toolCallCount: 1,
        pendingStepId: 's',
        toolName: 'x',
        toolIdempotent: true,
        argumentsHash: 'h',
      );
      final cp = await recovery.restore('t1');
      expect(
        () => recovery.validateForResume(checkpoint: cp!, currentProjectRevision: 6, currentWorkspaceRoot: '/w'),
        throwsA(isA<StateError>().having((e) => e.message, 'msg', contains(ShadowErrorCode.editRevisionMismatch))),
      );
    });

    test('never silently repeats non-idempotent operation', () async {
      final recovery = RecoveryManager();
      final context = AgentContext(taskId: 't2', workspaceRoot: '/w', projectRevision: 1);
      final plan = AgentPlan(steps: const [PlanStep(id: 's', description: 'd', expectedOutcome: 'e')], revision: 1);
      await recovery.saveAfterToolCall(
        taskId: 't2',
        context: context,
        plan: plan,
        toolCallCount: 1,
        pendingStepId: 's',
        toolName: 'danger',
        toolIdempotent: false,
        argumentsHash: 'h',
      );
      final cp = await recovery.restore('t2');
      expect(
        () => recovery.assertSafeToRepeatLastTool(cp!),
        throwsA(isA<StateError>().having((e) => e.message, 'msg', contains(ShadowErrorCode.toolNotIdempotentRetry))),
      );
    });

    test('controller restoreTask resumes queued task from valid checkpoint', () async {
      final tool = FakeTool(name: 'scan');
      final executor = FakeToolExecutor([tool]);
      final recovery = RecoveryManager();
      final context = AgentContext(taskId: 'rt', workspaceRoot: '/w', projectRevision: 2);
      final plan = AgentPlan(steps: const [PlanStep(id: 's1', description: 'd', expectedOutcome: 'e')], revision: 1);
      await recovery.saveAfterToolCall(
        taskId: 'rt',
        context: context,
        plan: plan,
        toolCallCount: 1,
        pendingStepId: 's1',
        toolName: 'scan',
        toolIdempotent: true,
        argumentsHash: 'h',
      );
      final brain = CallbackAgentBrain(onNextDecision: ({required plan, required currentStepId, required history}) async {
        return const CompleteDecision(summary: 'resumed');
      });
      final controller = AgentController(brain: brain, toolExecutor: executor, recoveryManager: recovery);
      final restored = await controller.restoreTask(
        taskId: 'rt',
        request: 'resume',
        workspaceRoot: '/w',
        currentProjectRevision: 2,
      );
      expect(restored.plan, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(controller.task('rt')?.state, ManagedTaskState.succeeded);
      await controller.dispose();
    });
  });
}
