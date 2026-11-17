import 'dart:io';

import 'package:local_storage/local_storage.dart';
import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:test/test.dart';

AgentCheckpoint _checkpoint({
  required String taskId,
  required int sequence,
  AgentTaskState state = AgentTaskState.acting,
  DateTime? at,
  DateTime? heartbeat,
  String? request,
  CheckpointToolStatus toolStatus = CheckpointToolStatus.succeeded,
  List<String> partialArtifacts = const <String>[],
}) {
  final createdAt = at ?? DateTime.utc(2026, 1, 1, 12);
  return AgentCheckpoint(
    taskId: taskId,
    sequence: sequence,
    createdAt: createdAt,
    contextHash: 'hash-$taskId',
    projectRevision: 7,
    workspaceRoot: '/ws',
    plan: const AgentPlan(
      revision: 1,
      steps: <PlanStep>[
        PlanStep(id: 's1', description: 'd', expectedOutcome: 'e'),
      ],
    ),
    toolCallCount: 2,
    pendingStepId: 's1',
    request: request,
    metadata: const <String, Object?>{'source': 'test'},
    lastToolName: 'scan',
    lastToolIdempotent: true,
    lastToolArgumentsHash: 'args',
    lastToolStatus: toolStatus,
    lastHeartbeatAt: heartbeat ?? createdAt,
    runId: 'run-1',
    processId: 42,
    resumeCount: 1,
    partialArtifacts: partialArtifacts,
    state: state,
  );
}

void main() {
  group('SqliteCheckpointStore', () {
    late Directory tempDir;
    late LocalDatabase db;
    late SqliteCheckpointStore store;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ss_checkpoints_');
      db = LocalDatabase.open('${tempDir.path}/shadow.sqlite');
      store = SqliteCheckpointStore(db);
    });

    tearDown(() {
      db.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('round-trips every recovery field and survives reopen', () async {
      await store.save(
        _checkpoint(
          taskId: 't1',
          sequence: 1,
          request: 'do the thing',
          partialArtifacts: const <String>['out/part.mp4'],
        ),
      );
      var latest = await store.latest('t1');
      expect(latest, isNotNull);
      expect(latest!.request, 'do the thing');
      expect(latest.metadata, <String, Object?>{'source': 'test'});
      expect(latest.lastToolStatus, CheckpointToolStatus.succeeded);
      expect(latest.resumeCount, 1);
      expect(latest.runId, 'run-1');
      expect(latest.processId, 42);
      expect(latest.partialArtifacts, <String>['out/part.mp4']);
      expect(latest.plan.steps.single.id, 's1');

      db.close();
      db = LocalDatabase.open('${tempDir.path}/shadow.sqlite');
      store = SqliteCheckpointStore(db);
      latest = await store.latest('t1');
      expect(latest!.request, 'do the thing');
      expect(latest.lastHeartbeatAt, DateTime.utc(2026, 1, 1, 12));
    });

    test('latest returns the highest sequence and history is newest first',
        () async {
      await store.save(_checkpoint(taskId: 't', sequence: 1));
      await store.save(_checkpoint(taskId: 't', sequence: 3));
      await store.save(_checkpoint(taskId: 't', sequence: 2));

      expect((await store.latest('t'))!.sequence, 3);
      final history = await store.history('t', limit: 2);
      expect(history.map((c) => c.sequence), <int>[3, 2]);
    });

    test('latestAll returns one row per task ordered by heartbeat', () async {
      await store.save(
        _checkpoint(
          taskId: 'old',
          sequence: 1,
          heartbeat: DateTime.utc(2026, 1, 1, 10),
        ),
      );
      await store.save(
        _checkpoint(
          taskId: 'new',
          sequence: 1,
          heartbeat: DateTime.utc(2026, 1, 1, 11),
        ),
      );
      final all = await store.latestAll();
      expect(all.map((c) => c.taskId), <String>['new', 'old']);
    });

    test(
        'malformed checkpoint JSON fails closed on latest but is skipped in '
        'history', () async {
      db.raw.execute('''
        INSERT INTO agent_tasks
          (id, state, request, project_revision, workspace_root, created_at, updated_at)
        VALUES ('bad', 'acting', 'x', 1, '/ws', 0, 0)
      ''');
      db.raw.execute('''
        INSERT INTO execution_checkpoints
          (task_id, sequence, created_at, context_hash, project_revision,
           workspace_root, plan_json, tool_call_count, state)
        VALUES ('bad', 1, 0, 'h', 1, '/ws', '{', 0, 'acting')
      ''');

      await expectLater(
        store.latest('bad'),
        throwsA(isA<CheckpointCorruptException>()),
      );
      expect(await store.history('bad'), isEmpty);
      expect(await store.latestAll(), isEmpty);
    });

    test('clear removes only the requested task history', () async {
      await store.save(_checkpoint(taskId: 'a', sequence: 1));
      await store.save(_checkpoint(taskId: 'b', sequence: 1));
      await store.clear('a');
      expect(await store.latest('a'), isNull);
      expect(await store.latest('b'), isNotNull);
      expect(await store.history('a'), isEmpty);
    });

    test('saving a checkpoint creates its owner task row for the foreign key',
        () async {
      await store.save(
        _checkpoint(taskId: 'fk', sequence: 1, request: 'owner request'),
      );
      final rows = db.raw.select(
        'SELECT * FROM agent_tasks WHERE id = ?',
        <Object?>['fk'],
      );
      expect(rows, hasLength(1));
      expect(rows.first['request'], 'owner request');
      expect(rows.first['workspace_root'], '/ws');
    });
  });
}
