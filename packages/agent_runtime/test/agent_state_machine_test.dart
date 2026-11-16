import 'dart:async';
import 'package:shadow_agent_runtime/agent_runtime.dart';
import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:test/test.dart';

import 'test_support.dart';

void main() {
  group('TaskScheduler state/queue', () {
    test('single active task in v1 and queues pending', () {
      final s = TaskScheduler();
      final a = s.enqueue(id: 'a', request: '1', workspaceRoot: '/w', projectRevision: 1);
      final b = s.enqueue(id: 'b', request: '2', workspaceRoot: '/w', projectRevision: 1);
      expect(s.active?.id, 'a');
      expect(s.pending.map((t) => t.id), ['b']);
      s.completeActive('a');
      expect(s.active?.id, 'b');
      expect(s.pending, isEmpty);
      s.completeActive('b');
      expect(s.isIdle, isTrue);
    });

    test('cancel queued task removes it', () {
      final s = TaskScheduler();
      s.enqueue(id: 'a', request: '1', workspaceRoot: '/w', projectRevision: 1);
      s.enqueue(id: 'b', request: '2', workspaceRoot: '/w', projectRevision: 1);
      expect(s.cancel('b'), isTrue);
      s.completeActive('a');
      expect(s.active, isNull);
      expect(s.isCancelled('b'), isTrue);
    });
  });

  group('AgentController task lifecycle', () {
    test('creates, plans, executes and completes task', () async {
      final tool = FakeTool(name: 'scan');
      final executor = FakeToolExecutor([tool]);
      var turn = 0;
      final brain = CallbackAgentBrain(onNextDecision: ({required plan, required currentStepId, required history}) async {
        turn++;
        if (turn == 1) {
          return ToolCallsDecision([AIToolCall(id: 'c1', name: 'scan', arguments: const {'x': 1})]);
        }
        return const CompleteDecision(summary: 'done');
      });
      final controller = AgentController(brain: brain, toolExecutor: executor);
      final events = <AgentRuntimeEvent>[];
      controller.events.listen(events.add);

      final task = controller.createTask(request: 'do it', workspaceRoot: '/w', projectRevision: 3);
      expect(task.state, ManagedTaskState.queued);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(controller.task(task.id)?.state, ManagedTaskState.succeeded);
      expect(tool.calls, 1);
      expect(events.whereType<TaskStarted>(), isNotEmpty);
      expect(events.whereType<PlanUpdated>(), isNotEmpty);
      expect(events.whereType<ToolCallRequested>().single.toolName, 'scan');
      expect(events.whereType<ToolExecutionCompleted>().single.result.success, isTrue);
      expect(events.whereType<TaskCompleted>().single.summary, 'done');
      await controller.dispose();
    });

    test('cancellation moves task to cancelled', () async {
      final blocker = Completer<ToolResult>();
      final tool = FakeTool(name: 'slow', handler: (ctx, args) => blocker.future);
      final executor = FakeToolExecutor([tool]);
      final brain = CallbackAgentBrain(onNextDecision: ({required plan, required currentStepId, required history}) async {
        return ToolCallsDecision([AIToolCall(id: 'c1', name: 'slow', arguments: const {})]);
      });
      final controller = AgentController(brain: brain, toolExecutor: executor);
      final events = <AgentRuntimeEvent>[];
      controller.events.listen(events.add);

      final task = controller.createTask(request: 'x', workspaceRoot: '/w', projectRevision: 0);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await controller.cancelTask(task.id, reason: 'user');
      blocker.complete(const ToolResult(success: false, errorMessage: 'aborted'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(controller.task(task.id)?.state, ManagedTaskState.cancelled);
      expect(events.whereType<TaskCancelled>(), isNotEmpty);
      await controller.dispose();
    });
  });
}
