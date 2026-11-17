import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('AgentPlan', () {
    final step = PlanStep(
      id: 's1',
      description: 'do work',
      expectedOutcome: 'work done',
    );

    test('PlanStep JSON round-trips identity, status and outcome', () {
      final json = step.toJson();
      expect(json['id'], 's1');
      final restored = PlanStep.fromJson(json);
      expect(restored.id, step.id);
      expect(restored.description, step.description);
      expect(restored.expectedOutcome, step.expectedOutcome);
      expect(restored.status, PlanStepStatus.pending);
      expect(restored.isTerminal, isFalse);
    });

    test('PlanStep parses unknown status as pending', () {
      final restored = PlanStep.fromJson(<String, Object?>{
        'id': 's',
        'description': 'd',
        'expectedOutcome': 'e',
        'status': 'not-a-status',
      });
      expect(restored.status, PlanStepStatus.pending);
    });

    test('updateStep only changes the matching step and keeps revision', () {
      final plan = AgentPlan(
        goal: 'g',
        revision: 3,
        steps: [
          step,
          PlanStep(
            id: 's2',
            description: 'second',
            expectedOutcome: 'second done',
          ),
        ],
      );
      final updated = plan.updateStep('s2', (s) {
        return s.copyWith(
          status: PlanStepStatus.completed,
          resultSummary: 'ok',
        );
      });
      expect(updated.revision, 3);
      expect(updated.steps.first.status, PlanStepStatus.pending);
      expect(updated.steps[1].status, PlanStepStatus.completed);
      expect(updated.completedSteps.single.id, 's2');
      expect(updated.isComplete, isFalse);
    });

    test('AgentPlan JSON round-trips steps and revision', () {
      final plan = AgentPlan(
        goal: 'ship',
        revision: 7,
        steps: [step.copyWith(status: PlanStepStatus.completed)],
      );
      final restored = AgentPlan.fromJson(plan.toJson());
      expect(restored.goal, 'ship');
      expect(restored.revision, 7);
      expect(restored.steps.single.id, 's1');
      expect(restored.isComplete, isTrue);
    });

    test('withRevision bumps revision without mutating the original', () {
      final plan = AgentPlan(revision: 1, steps: [step]);
      final next = plan.withRevision(2, newSteps: [step]);
      expect(next.revision, 2);
      expect(plan.revision, 1);
    });
  });

  group('AgentDecision', () {
    test('decisions expose their payloads', () {
      const complete = CompleteDecision(summary: 'done');
      final tools = ToolCallsDecision(const <AIToolCall>[
        AIToolCall(id: 'c1', name: 'noop', arguments: <String, Object?>{}),
      ]);
      const replan = ReplanDecision('retry');
      const fail = FailDecision('CODE', 'bad');

      expect(complete.summary, 'done');
      expect(tools.calls.single.name, 'noop');
      expect(replan.reason, 'retry');
      expect(fail.code, 'CODE');
      expect(fail.retryable, isFalse);
    });
  });

  group('AgentCheckpoint', () {
    test('JSON round-trips plan, tool state and task state', () {
      final cp = AgentCheckpoint(
        taskId: 'task-1',
        sequence: 4,
        createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
        contextHash: 'abc123',
        projectRevision: 9,
        workspaceRoot: '/tmp/ws',
        plan: AgentPlan(
          revision: 2,
          steps: [PlanStep(id: 's1', description: 'd', expectedOutcome: 'e')],
        ),
        toolCallCount: 2,
        pendingStepId: 's1',
        lastToolName: 'save',
        lastToolIdempotent: true,
        lastToolArgumentsHash: 'h',
        state: AgentTaskState.acting,
      );
      final restored = AgentCheckpoint.fromJson(cp.toJson());
      expect(restored.taskId, 'task-1');
      expect(restored.sequence, 4);
      expect(restored.createdAt, cp.createdAt);
      expect(restored.contextHash, 'abc123');
      expect(restored.plan.revision, 2);
      expect(restored.toolCallCount, 2);
      expect(restored.lastToolIdempotent, isTrue);
      expect(restored.state, AgentTaskState.acting);
    });
  });
}
