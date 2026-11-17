import 'dart:async';
import 'dart:io';

import 'package:local_storage/local_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shadow_agent_runtime/agent_runtime.dart';
import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:test/test.dart';

import 'test_support.dart';

AgentContext _context(
  String taskId, {
  String workspace = '/ws',
  int revision = 1,
  Map<String, Object?> metadata = const <String, Object?>{},
}) => AgentContext(
  taskId: taskId,
  workspaceRoot: workspace,
  projectRevision: revision,
  metadata: metadata,
);

AgentPlan _plan({
  String stepId = 'step-1',
  PlanStepStatus status = PlanStepStatus.pending,
}) => AgentPlan(
  revision: 1,
  steps: <PlanStep>[
    PlanStep(
      id: stepId,
      description: 'do work',
      expectedOutcome: 'work done',
      status: status,
    ),
  ],
);

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(reason ?? 'condition not met in time');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _waitForAsync(
  Future<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(reason ?? 'condition not met in time');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _CorruptStore implements CheckpointStore {
  @override
  Future<void> save(AgentCheckpoint checkpoint) async {}

  @override
  Future<AgentCheckpoint?> latest(String taskId) async {
    throw const CheckpointCorruptException(
      taskId: 'corrupt',
      message: 'bad row',
    );
  }

  @override
  Future<List<AgentCheckpoint>> history(
    String taskId, {
    int limit = 50,
  }) async => const <AgentCheckpoint>[];

  @override
  Future<List<AgentCheckpoint>> latestAll() async => const <AgentCheckpoint>[];

  @override
  Future<void> clear(String taskId) async {}
}

void main() {
  group('crash simulation', () {
    test(
      'a checkpoint from a dead process is detected as interrupted',
      () async {
        final store = InMemoryCheckpointStore();
        final now = DateTime.utc(2026, 1, 1, 12);
        final crashed = RecoveryManager(
          store: store,
          processId: 100,
          runId: 'run-old',
          now: () => now,
        );
        await crashed.saveBeforeToolCall(
          taskId: 't',
          context: _context('t'),
          plan: _plan(),
          toolCallCount: 0,
          pendingStepId: 'step-1',
          toolName: 'render_video',
          toolIdempotent: false,
          argumentsHash: 'h',
          request: 'render',
        );

        final restarted = RecoveryManager(
          store: store,
          processId: 200,
          runId: 'run-new',
          now: () => now.add(const Duration(seconds: 2)),
        );
        final interrupted = await restarted.detectInterrupted();

        expect(interrupted, hasLength(1));
        expect(interrupted.single.checkpoint.taskId, 't');
        expect(interrupted.single.reason, 'process_restart');
        expect(interrupted.single.checkpoint.mayHaveInFlightTool, isTrue);

        final inspection = await restarted.inspect(taskId: 't');
        expect(inspection.isInterrupted, isTrue);
        expect(inspection.safeToResume, isFalse);
        expect(
          inspection.blockers.map((b) => b.code),
          contains(ShadowErrorCode.toolNotIdempotentRetry),
        );
      },
    );

    test('a stale heartbeat from the same process is interrupted', () async {
      final store = InMemoryCheckpointStore();
      final now = DateTime.utc(2026, 1, 1, 12);
      final oldRun = RecoveryManager(
        store: store,
        processId: 200,
        runId: 'run-old',
        now: () => now,
      );
      await oldRun.saveBeforeToolCall(
        taskId: 't',
        context: _context('t'),
        plan: _plan(),
        toolCallCount: 0,
        pendingStepId: 'step-1',
        toolName: 'scan',
        toolIdempotent: true,
        argumentsHash: 'h',
      );

      final later = RecoveryManager(
        store: store,
        processId: 200,
        runId: 'run-new',
        staleAfter: const Duration(minutes: 5),
        now: () => now.add(const Duration(minutes: 6)),
      );
      final interrupted = await later.detectInterrupted();
      expect(interrupted, hasLength(1));
      expect(interrupted.single.reason, 'heartbeat_stale');
    });

    test('terminal tasks are not reported as interrupted', () async {
      final store = InMemoryCheckpointStore();
      final now = DateTime.utc(2026, 1, 1, 12);
      final oldRun = RecoveryManager(
        store: store,
        processId: 1,
        runId: 'old',
        now: () => now,
      );
      await oldRun.saveTaskState(
        taskId: 'done',
        context: _context('done'),
        state: AgentTaskState.succeeded,
        plan: _plan(status: PlanStepStatus.completed),
        summary: 'ok',
      );
      final restarted = RecoveryManager(
        store: store,
        processId: 2,
        runId: 'new',
        now: () => now.add(const Duration(days: 1)),
      );
      expect(await restarted.detectInterrupted(), isEmpty);
    });

    test(
      'non-idempotent in-flight tool requires explicit replay consent',
      () async {
        final store = InMemoryCheckpointStore();
        final crashed = RecoveryManager(store: store, processId: 10);
        await crashed.saveBeforeToolCall(
          taskId: 't',
          context: _context('t'),
          plan: _plan(),
          toolCallCount: 0,
          pendingStepId: 'step-1',
          toolName: 'delete_asset',
          toolIdempotent: false,
          argumentsHash: 'h',
        );
        final cp = (await crashed.restore('t'))!;

        await expectLater(
          crashed.planResume(
            checkpoint: cp,
            workspaceRoot: '/ws',
            currentProjectRevision: 1,
          ),
          throwsA(
            isA<RecoveryException>().having(
              (e) => e.code,
              'code',
              ShadowErrorCode.toolNotIdempotentRetry,
            ),
          ),
        );

        final plan = await crashed.planResume(
          checkpoint: cp,
          workspaceRoot: '/ws',
          currentProjectRevision: 1,
          allowNonIdempotentReplay: true,
        );
        expect(plan.resumeCount, 1);
        expect(plan.plan.steps.single.id, 'step-1');
      },
    );

    test('idempotent in-flight tool resumes without confirmation', () async {
      final store = InMemoryCheckpointStore();
      final crashed = RecoveryManager(store: store, processId: 10);
      await crashed.saveBeforeToolCall(
        taskId: 't',
        context: _context('t'),
        plan: _plan(),
        toolCallCount: 0,
        pendingStepId: 'step-1',
        toolName: 'scan',
        toolIdempotent: true,
        argumentsHash: 'h',
      );
      final cp = (await crashed.restore('t'))!;
      final plan = await crashed.planResume(
        checkpoint: cp,
        workspaceRoot: '/ws',
        currentProjectRevision: 1,
      );
      expect(plan.plan.steps.single.status, PlanStepStatus.pending);
    });

    test(
      'a corrupt checkpoint fails closed instead of resuming stale state',
      () async {
        final recovery = RecoveryManager(store: _CorruptStore());
        final inspection = await recovery.inspect(taskId: 'corrupt');
        expect(inspection.errorCode, ShadowErrorCode.storeCorrupt);
        expect(inspection.safeToResume, isFalse);
        await expectLater(
          recovery.restore('corrupt'),
          throwsA(isA<RecoveryException>()),
        );
      },
    );

    test(
      'failed tool error and partial output are persisted for inspection',
      () async {
        final dir = await Directory.systemTemp.createTemp('ss_recovery_');
        addTearDown(() => dir.delete(recursive: true));
        final partial = File(p.join(dir.path, 'render.part.mp4'));
        await partial.writeAsString('partial');

        final store = InMemoryCheckpointStore();
        final recovery = RecoveryManager(store: store);
        final context = _context('failed', workspace: dir.path);
        await recovery.saveAfterToolCall(
          taskId: 'failed',
          context: context,
          plan: _plan(),
          toolCallCount: 1,
          pendingStepId: 'step-1',
          toolName: 'render_video',
          toolIdempotent: true,
          argumentsHash: 'h',
          toolSucceeded: false,
          toolErrorCode: ShadowErrorCode.mediaEngineCrash,
          toolErrorMessage: 'ffmpeg exited',
          partialArtifacts: <String>['render.part.mp4'],
        );

        final cp = (await recovery.restore('failed'))!;
        expect(cp.lastToolStatus, CheckpointToolStatus.failed);
        expect(cp.lastToolErrorCode, ShadowErrorCode.mediaEngineCrash);

        final inspection = await recovery.inspect(taskId: 'failed');
        expect(inspection.partialArtifacts, <String>['render.part.mp4']);
        expect(inspection.checkpoint!.lastToolErrorMessage, 'ffmpeg exited');
      },
    );
    test(
      'a delayed non-terminal write cannot resurrect a terminal task',
      () async {
        final recovery = RecoveryManager(store: InMemoryCheckpointStore());
        final context = _context('t');
        final plan = _plan(status: PlanStepStatus.completed);
        await recovery.saveTaskState(
          taskId: 't',
          context: context,
          state: AgentTaskState.succeeded,
          plan: plan,
          summary: 'done',
        );
        final after = await recovery.saveTaskState(
          taskId: 't',
          context: context,
          state: AgentTaskState.acting,
          plan: plan,
        );
        expect(after.state, AgentTaskState.succeeded);
        expect(after.summary, 'done');
        expect((await recovery.restore('t'))!.state, AgentTaskState.succeeded);
      },
    );

    test('a later successful tool clears the previous tool error', () async {
      final recovery = RecoveryManager(store: InMemoryCheckpointStore());
      final context = _context('t');
      final plan = _plan();
      await recovery.saveAfterToolCall(
        taskId: 't',
        context: context,
        plan: plan,
        toolCallCount: 1,
        pendingStepId: 'step-1',
        toolName: 'scan',
        toolIdempotent: true,
        argumentsHash: 'h1',
        toolSucceeded: false,
        toolErrorCode: ShadowErrorCode.toolTimeout,
        toolErrorMessage: 'timed out',
      );
      await recovery.saveAfterToolCall(
        taskId: 't',
        context: context,
        plan: plan,
        toolCallCount: 2,
        pendingStepId: 'step-1',
        toolName: 'scan',
        toolIdempotent: true,
        argumentsHash: 'h2',
      );
      final cp = (await recovery.restore('t'))!;
      expect(cp.lastToolStatus, CheckpointToolStatus.succeeded);
      expect(cp.lastToolErrorCode, isNull);
      expect(cp.lastToolErrorMessage, isNull);
    });

    test(
      'partial outputs are only deleted when explicitly discarded',
      () async {
        final dir = await Directory.systemTemp.createTemp('ss_recovery_');
        addTearDown(() => dir.delete(recursive: true));
        final partial = File(p.join(dir.path, 'out', 'part.mp4'));
        await partial.create(recursive: true);
        await partial.writeAsString('partial');

        final recovery = RecoveryManager(store: InMemoryCheckpointStore());
        final context = _context('p', workspace: dir.path);
        await recovery.saveTaskState(
          taskId: 'p',
          context: context,
          state: AgentTaskState.acting,
          plan: _plan(),
          partialArtifacts: const <String>['out/part.mp4'],
        );
        final cp = (await recovery.restore('p'))!;

        final keep = await recovery.planResume(
          checkpoint: cp,
          workspaceRoot: dir.path,
          currentProjectRevision: 1,
        );
        expect(keep.partialArtifacts, <String>['out/part.mp4']);
        expect(keep.warnings.single, contains('discardPartialOutputs'));
        expect(await partial.exists(), isTrue);

        final discard = await recovery.planResume(
          checkpoint: cp,
          workspaceRoot: dir.path,
          currentProjectRevision: 1,
          discardPartialOutputs: true,
        );
        expect(discard.discardedPartialArtifacts, <String>['out/part.mp4']);
        expect(await partial.exists(), isFalse);
      },
    );

    test('partial output paths escaping the workspace are rejected', () async {
      final dir = await Directory.systemTemp.createTemp('ss_recovery_');
      addTearDown(() => dir.delete(recursive: true));
      final outside = File(p.join(dir.path, 'escape.mp4'));
      await outside.writeAsString('x');
      final workspace = Directory(p.join(dir.path, 'ws'))..createSync();

      final recovery = RecoveryManager(store: InMemoryCheckpointStore());
      final context = _context('escape', workspace: workspace.path);
      await recovery.saveTaskState(
        taskId: 'escape',
        context: context,
        state: AgentTaskState.acting,
        plan: _plan(),
        partialArtifacts: const <String>['../escape.mp4'],
      );
      final cp = (await recovery.restore('escape'))!;
      final inspection = await recovery.inspect(taskId: 'escape');
      expect(
        inspection.blockers.map((b) => b.code),
        contains(ShadowErrorCode.permPathEscape),
      );
      await expectLater(
        recovery.planResume(
          checkpoint: cp,
          workspaceRoot: workspace.path,
          currentProjectRevision: 1,
        ),
        throwsA(isA<RecoveryException>()),
      );
      expect(await outside.exists(), isTrue);
    });

    test('revision and workspace changes block resume', () async {
      final recovery = RecoveryManager(store: InMemoryCheckpointStore());
      await recovery.saveTaskState(
        taskId: 't',
        context: _context('t', workspace: '/ws', revision: 3),
        state: AgentTaskState.acting,
        plan: _plan(),
      );
      final cp = (await recovery.restore('t'))!;
      final inspection = await recovery.inspect(
        taskId: 't',
        currentProjectRevision: 4,
        workspaceRoot: '/other',
      );
      expect(
        inspection.blockers.map((b) => b.code),
        containsAll(<String>[
          ShadowErrorCode.editRevisionMismatch,
          ShadowErrorCode.agentCheckpointMissing,
        ]),
      );
      expect(inspection.safeToResume, isFalse);
      await expectLater(
        recovery.planResume(
          checkpoint: cp,
          workspaceRoot: '/other',
          currentProjectRevision: 4,
        ),
        throwsA(
          isA<RecoveryException>()
              .having(
                (e) => e.code,
                'code',
                ShadowErrorCode.agentCheckpointMissing,
              )
              .having((e) => e.message, 'message', contains('revision')),
        ),
      );
    });

    test('an empty plan is resumable only when no tool has run', () async {
      final recovery = RecoveryManager(store: InMemoryCheckpointStore());
      final context = _context('planning');
      await recovery.saveTaskState(
        taskId: 'planning',
        context: context,
        state: AgentTaskState.planning,
        request: 'plan me',
      );
      final cp = (await recovery.restore('planning'))!;
      final resume = await recovery.planResume(
        checkpoint: cp,
        workspaceRoot: '/ws',
        currentProjectRevision: 1,
      );
      expect(resume.plan.steps, isEmpty);

      await recovery.saveTaskState(
        taskId: 'planning',
        context: context,
        state: AgentTaskState.planning,
        toolCallCount: 1,
      );
      final lost = (await recovery.restore('planning'))!;
      final inspection = await recovery.inspect(taskId: 'planning');
      expect(inspection.safeToResume, isFalse);
      await expectLater(
        recovery.planResume(
          checkpoint: lost,
          workspaceRoot: '/ws',
          currentProjectRevision: 1,
        ),
        throwsA(isA<RecoveryException>()),
      );
    });

    test('checkpoint history is ordered and sequences stay monotonic under '
        'concurrent saves', () async {
      final store = InMemoryCheckpointStore();
      final recovery = RecoveryManager(store: store);
      final context = _context('t');
      final plan = _plan();
      await Future.wait<void>(<Future<void>>[
        recovery.saveTaskState(
          taskId: 't',
          context: context,
          state: AgentTaskState.planning,
          plan: plan,
        ),
        recovery.saveAfterToolCall(
          taskId: 't',
          context: context,
          plan: plan,
          toolCallCount: 1,
          pendingStepId: 'step-1',
          toolName: 'scan',
          toolIdempotent: true,
          argumentsHash: 'h',
        ),
        recovery.saveTaskState(
          taskId: 't',
          context: context,
          state: AgentTaskState.acting,
          plan: plan,
        ),
      ]);
      final history = await recovery.history('t');
      expect(history, hasLength(3));
      expect(history.first.sequence, greaterThan(history.last.sequence));
      expect(history.map((c) => c.sequence).toSet(), hasLength(3));
    });
  });

  group('recovery integration (process restart)', () {
    test(
      'SQLite checkpoint survives a restart and resumes to completion',
      () async {
        final dir = await Directory.systemTemp.createTemp('ss_restart_');
        addTearDown(() => dir.delete(recursive: true));
        final dbPath = p.join(dir.path, 'shadow.sqlite');
        final now = DateTime.utc(2026, 1, 1, 12);

        var db = LocalDatabase.open(dbPath);
        var store = SqliteCheckpointStore(db);
        expect(db.schemaVersion, 3);
        final crashed = RecoveryManager(
          store: store,
          processId: 111,
          runId: 'run-old',
          now: () => now,
        );
        final context = _context('task-1', workspace: dir.path, revision: 2);
        await crashed.saveBeforeToolCall(
          taskId: 'task-1',
          context: context,
          plan: _plan(),
          toolCallCount: 0,
          pendingStepId: 'step-1',
          toolName: 'scan',
          toolIdempotent: true,
          argumentsHash: 'h',
          request: 'scan the project',
        );
        db.close();

        // Application restart: reopen the same file with a new process identity.
        db = LocalDatabase.open(dbPath);
        store = SqliteCheckpointStore(db);
        final restarted = RecoveryManager(
          store: store,
          processId: 222,
          runId: 'run-new',
          now: () => now.add(const Duration(seconds: 30)),
        );
        final interrupted = await restarted.detectInterrupted();
        expect(interrupted, hasLength(1));

        final controller = AgentController(
          brain: CallbackAgentBrain(
            onNextDecision:
                ({
                  required plan,
                  required currentStepId,
                  required history,
                }) async => const CompleteDecision(summary: 'resumed'),
          ),
          toolExecutor: FakeToolExecutor(),
          recoveryManager: restarted,
        );
        addTearDown(controller.dispose);

        final task = await controller.resumeTask(taskId: 'task-1');
        expect(task.request, 'scan the project');
        expect(task.plan?.steps.single.id, 'step-1');

        await _waitFor(
          () => controller.task('task-1')?.state == ManagedTaskState.succeeded,
          reason: 'resumed task did not complete',
        );
        final terminal = (await restarted.restore('task-1'))!;
        expect(terminal.state, AgentTaskState.succeeded);
        expect(terminal.summary, 'resumed');
        expect(terminal.resumeCount, 1);

        final history = await restarted.history('task-1');
        expect(history.length, greaterThanOrEqualTo(3));
        expect(history.first.state, AgentTaskState.succeeded);
        db.close();
      },
    );
    test(
      'a task interrupted during initial planning replans on resume',
      () async {
        final store = InMemoryCheckpointStore();
        final recovery = RecoveryManager(store: store);
        await recovery.saveTaskState(
          taskId: 'planned-later',
          context: _context('planned-later'),
          state: AgentTaskState.planning,
          request: 'make a plan',
        );
        final controller = AgentController(
          brain: CallbackAgentBrain(),
          toolExecutor: FakeToolExecutor(),
          recoveryManager: recovery,
        );
        addTearDown(controller.dispose);

        final task = await controller.resumeTask(taskId: 'planned-later');
        expect(task.plan!.steps, isEmpty);
        await _waitFor(
          () =>
              controller.task('planned-later')?.state ==
              ManagedTaskState.succeeded,
        );
        final cp = (await recovery.restore('planned-later'))!;
        expect(cp.state, AgentTaskState.succeeded);
        expect(cp.plan.steps, isNotEmpty);
      },
    );

    test(
      'restart keeps terminal checkpoint and refuses to resume it',
      () async {
        final dir = await Directory.systemTemp.createTemp('ss_restart_');
        addTearDown(() => dir.delete(recursive: true));
        final dbPath = p.join(dir.path, 'shadow.sqlite');
        var db = LocalDatabase.open(dbPath);
        final store = SqliteCheckpointStore(db);
        final recovery = RecoveryManager(store: store, processId: 1);
        await recovery.saveTaskState(
          taskId: 'done',
          context: _context('done', workspace: dir.path),
          state: AgentTaskState.succeeded,
          plan: _plan(status: PlanStepStatus.completed),
          summary: 'finished',
        );
        db.close();

        db = LocalDatabase.open(dbPath);
        final restarted = RecoveryManager(
          store: SqliteCheckpointStore(db),
          processId: 2,
          runId: 'new',
        );
        final controller = AgentController(
          brain: CallbackAgentBrain(),
          toolExecutor: FakeToolExecutor(),
          recoveryManager: restarted,
        );
        addTearDown(controller.dispose);
        await expectLater(
          controller.resumeTask(taskId: 'done'),
          throwsA(isA<RecoveryException>()),
        );
        db.close();
      },
    );

    test(
      'cancelling an active task persists a terminal cancelled checkpoint',
      () async {
        final store = InMemoryCheckpointStore();
        final tool = FakeTool(
          name: 'slow',
          handler: (context, args) async {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            return const ToolResult(success: true, data: <String, Object?>{});
          },
        );
        final controller = AgentController(
          brain: CallbackAgentBrain(
            onNextDecision:
                ({
                  required plan,
                  required currentStepId,
                  required history,
                }) async => ToolCallsDecision(<AIToolCall>[
                  AIToolCall(
                    id: 'c1',
                    name: 'slow',
                    arguments: <String, Object?>{},
                  ),
                ]),
          ),
          toolExecutor: FakeToolExecutor(<AgentTool>[tool]),
          recoveryManager: RecoveryManager(store: store),
        );
        addTearDown(controller.dispose);

        final task = controller.createTask(
          request: 'slow',
          workspaceRoot: '/ws',
          projectRevision: 1,
        );
        await _waitFor(
          () => controller.task(task.id)?.state == ManagedTaskState.acting,
        );
        await controller.cancelTask(task.id, reason: 'user');
        await _waitFor(
          () => controller.task(task.id)?.state == ManagedTaskState.cancelled,
          reason: 'cancel was not observed',
        );
        await _waitForAsync(
          () async => await controller.recoveryManager.restore(task.id) != null,
          reason: 'terminal checkpoint was not written',
        );
        final cp = await controller.recoveryManager.restore(task.id);
        expect(cp!.state, AgentTaskState.cancelled);
        expect(cp.errorMessage, 'user');
      },
    );
  });
}
