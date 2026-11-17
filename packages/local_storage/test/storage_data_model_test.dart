import 'dart:io';

import 'package:local_storage/local_storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  group('LocalDatabase data model (D2)', () {
    late Directory tempDir;
    late LocalDatabase db;
    late StorageRepositories repos;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ss_d2_test_');
      db = LocalDatabase.open('${tempDir.path}/shadow.sqlite');
      repos = StorageRepositories(db);
    });

    tearDown(() {
      db.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    DateTime ts(int minute) => DateTime.utc(2026, 1, 1, 0, minute);

    test('schema is migrated to version 3 with all required tables', () {
      expect(db.schemaVersion, 3);
      final names = db.raw
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'] as String)
          .toSet();
      for (final expected in <String>[
        'projects',
        'media_assets',
        'timelines',
        'agent_sessions',
        'agent_tasks',
        'tool_executions',
        'approvals',
        'execution_checkpoints',
        'provider_configs',
        'execution_logs',
        'permission_decisions',
      ]) {
        expect(names, contains(expected), reason: 'missing table $expected');
      }
    });

    test('project records round-trip and update revision', () {
      repos.projects.upsert(ProjectRecord(
        id: 'p1',
        name: 'Demo',
        workspaceRoot: '/tmp/demo',
        filePath: '/tmp/demo/demo.ssproj',
        revision: 1,
        createdAt: ts(0),
        updatedAt: ts(0),
      ));
      final loaded = repos.projects.get('p1');
      expect(loaded, isNotNull);
      expect(loaded!.name, 'Demo');
      expect(loaded.revision, 1);

      repos.projects.updateRevision('p1', 4);
      expect(repos.projects.get('p1')!.revision, 4);

      expect(repos.projects.list(), hasLength(1));
    });

    test('soft delete hides projects and cascades assets and timelines', () {
      repos.projects.upsert(ProjectRecord(
        id: 'p2',
        name: 'Doomed',
        workspaceRoot: '/tmp/doomed',
        filePath: '/tmp/doomed/doomed.ssproj',
        createdAt: ts(0),
        updatedAt: ts(0),
      ));
      repos.mediaAssets.save(MediaAsset(
        id: 'a1',
        projectId: 'p2',
        kind: 'video',
        path: '/tmp/doomed/a.mp4',
        createdAt: ts(1),
      ));
      repos.timelines.save(TimelineRecord(
        id: 't1',
        projectId: 'p2',
        name: 'main',
        revision: 1,
        tracksJson: '{"tracks":[]}',
        createdAt: ts(1),
        updatedAt: ts(1),
      ));

      repos.projects.softDelete('p2');

      expect(repos.projects.get('p2')!.deletedAt, isNotNull);
      expect(repos.projects.list(), isEmpty);
      expect(repos.mediaAssets.listByProject('p2'), isEmpty);
      expect(repos.timelines.listByProject('p2'), isEmpty);

      repos.projects.purge('p2');
      expect(repos.projects.get('p2'), isNull);
    });

    test('media assets validate metadata and reject missing projects', () {
      repos.projects.upsert(ProjectRecord(
        id: 'p3',
        name: 'Media',
        workspaceRoot: '/tmp/media',
        filePath: '/tmp/media/media.ssproj',
        createdAt: ts(0),
        updatedAt: ts(0),
      ));
      repos.mediaAssets.save(MediaAsset(
        id: 'm1',
        projectId: 'p3',
        kind: 'audio',
        path: '/tmp/media/v.wav',
        mimeType: 'audio/wav',
        durationMs: 1500,
        metadata: const <String, Object?>{'channels': 2},
        createdAt: ts(2),
      ));
      final loaded = repos.mediaAssets.get('m1')!;
      expect(loaded.durationMs, 1500);
      expect(loaded.metadata['channels'], 2);
      expect(repos.mediaAssets.listByProject('p3'), hasLength(1));

      expect(
        () => repos.mediaAssets.save(MediaAsset(
          id: 'm2',
          projectId: 'missing',
          kind: 'video',
          path: '/tmp/media/bad.mp4',
          createdAt: ts(2),
        )),
        throwsA(isA<SqliteException>()),
      );
    });

    test('timelines round-trip tracks json and list by project', () {
      repos.projects.upsert(ProjectRecord(
        id: 'p4',
        name: 'Timeline',
        workspaceRoot: '/tmp/tl',
        filePath: '/tmp/tl/tl.ssproj',
        createdAt: ts(0),
        updatedAt: ts(0),
      ));
      repos.timelines.save(TimelineRecord(
        id: 'tl1',
        projectId: 'p4',
        name: 'v1',
        revision: 3,
        tracksJson: '{"tracks":[{"id":"tr1"}]}',
        createdAt: ts(1),
        updatedAt: ts(2),
      ));
      final loaded = repos.timelines.get('tl1')!;
      expect(loaded.revision, 3);
      expect(loaded.tracks()['tracks'], isList);
      expect(repos.timelines.listByProject('p4').single.id, 'tl1');
    });

    test('execution logs append, filter and purge by age', () {
      final id = repos.executionLogs.append(ExecutionLog(
        sessionId: 's1',
        taskId: 'task-1',
        level: 'info',
        event: 'tool.started',
        message: 'started',
        correlationId: 'c1',
        metadata: const <String, Object?>{'tool': 'save'},
        createdAt: ts(1),
      ));
      expect(id, greaterThan(0));
      repos.executionLogs.append(ExecutionLog(
        sessionId: 's1',
        level: 'error',
        event: 'tool.failed',
        message: 'boom',
        createdAt: ts(2),
      ));

      expect(repos.executionLogs.listBySession('s1'), hasLength(2));
      expect(repos.executionLogs.listByTask('task-1'), hasLength(1));
      expect(
        repos.executionLogs.purgeBefore(DateTime.utc(2026, 1, 1, 0, 1, 30)),
        1,
      );
      expect(repos.executionLogs.listBySession('s1'), hasLength(1));
    });

    test('permission decisions support resolve and expiry queries', () {
      repos.permissions.save(PermissionDecision(
        id: 'perm-1',
        taskId: 'task-1',
        toolName: 'delete',
        action: 'delete_media',
        status: 'pending',
        createdAt: ts(1),
        expiresAt: DateTime.utc(2026, 1, 1, 1),
      ));
      repos.permissions.save(PermissionDecision(
        id: 'perm-2',
        taskId: 'task-1',
        toolName: 'export',
        action: 'render',
        status: 'pending',
        createdAt: ts(1),
        expiresAt: DateTime.utc(2026, 1, 1, 0, 0, 30),
      ));

      expect(repos.permissions.listByTask('task-1'), hasLength(2));
      final expired = repos.permissions.listExpired(
        now: DateTime.utc(2026, 1, 1, 0, 0, 45),
      );
      expect(expired.single.id, 'perm-2');

      repos.permissions
          .resolve('perm-1', status: 'approved', reason: 'user clicked');
      final resolved = repos.permissions.get('perm-1')!;
      expect(resolved.status, 'approved');
      expect(resolved.resolvedAt, isNotNull);
    });

    test('agent sessions, tasks and tool executions persist', () {
      repos.agentSessions.save(AgentSessionRecord(
        id: 'sess-1',
        projectRevision: 1,
        workspaceRoot: '/tmp/ws',
        state: 'running',
        createdAt: ts(0),
        updatedAt: ts(0),
      ));
      repos.agentSessions.updateState('sess-1', 'paused', projectRevision: 2);

      repos.agentTasks.save(AgentTaskRecord(
        id: 'task-1',
        sessionId: 'sess-1',
        state: 'acting',
        request: 'export the video',
        projectRevision: 1,
        workspaceRoot: '/tmp/ws',
        createdAt: ts(1),
        updatedAt: ts(1),
      ));
      repos.agentTasks.updateState('task-1', 'done');

      repos.toolExecutions.save(ToolExecutionRecord(
        taskId: 'task-1',
        toolName: 'save',
        idempotent: true,
        argumentsHash: 'abc',
        result: '{}',
        status: 'succeeded',
        startedAt: ts(2),
        finishedAt: ts(2),
      ));

      expect(repos.agentSessions.get('sess-1')!.state, 'paused');
      expect(repos.agentSessions.get('sess-1')!.projectRevision, 2);
      expect(repos.agentTasks.listBySession('sess-1').single.state, 'done');
      expect(repos.toolExecutions.listByTask('task-1').single.toolName, 'save');
    });

    test('provider configs persist enabled flags and metadata', () {
      repos.providerConfigs.save(ProviderConfig(
        id: 'cfg-1',
        provider: 'openai',
        model: 'gpt-5',
        baseUrl: 'https://api.openai.com/v1',
        apiKeyRef: null,
        metadata: const <String, Object?>{'temperature': 0.2},
        createdAt: ts(0),
        updatedAt: ts(0),
      ));
      repos.providerConfigs.save(ProviderConfig(
        id: 'cfg-2',
        provider: 'ollama',
        enabled: false,
        createdAt: ts(0),
        updatedAt: ts(0),
      ));

      expect(repos.providerConfigs.get('cfg-1')!.enabled, isTrue);
      expect(repos.providerConfigs.get('cfg-2')!.enabled, isFalse);
      expect(repos.providerConfigs.list(enabledOnly: true).single.id, 'cfg-1');
      repos.providerConfigs.delete('cfg-2');
      expect(repos.providerConfigs.get('cfg-2'), isNull);
    });

    test('transaction rolls back all writes on failure', () {
      repos.projects.upsert(ProjectRecord(
        id: 'tx-1',
        name: 'Before',
        workspaceRoot: '/tmp/tx',
        filePath: '/tmp/tx/tx.ssproj',
        createdAt: ts(0),
        updatedAt: ts(0),
      ));

      expect(
        () => db.transaction<void>(() {
          repos.projects.updateRevision('tx-1', 9);
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );

      expect(repos.projects.get('tx-1')!.revision, 0);
    });

    test('integrity check passes and committed data survives reopen', () {
      expect(db.integrityCheck(), isTrue);
      repos.projects.upsert(ProjectRecord(
        id: 'persist-1',
        name: 'Persisted',
        workspaceRoot: '/tmp/persist',
        filePath: '/tmp/persist/p.ssproj',
        createdAt: ts(0),
        updatedAt: ts(0),
      ));
      db.close();

      db = LocalDatabase.open('${tempDir.path}/shadow.sqlite');
      repos = StorageRepositories(db);
      expect(repos.projects.get('persist-1')!.name, 'Persisted');
      expect(db.schemaVersion, 3);
      expect(db.integrityCheck(), isTrue);
    });

    test('migrates a v1 database forward without losing rows', () {
      db.close();
      final path = '${tempDir.path}/legacy.sqlite';
      final legacy = sqlite3.open(path);
      legacy.execute('''
        CREATE TABLE session_memory (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          project_id TEXT,
          kind TEXT NOT NULL,
          content TEXT NOT NULL,
          metadata TEXT,
          created_at INTEGER NOT NULL,
          expires_at INTEGER
        );
      ''');
      legacy.execute(
        "INSERT INTO session_memory (session_id, kind, content, created_at) "
        "VALUES ('old-session', 'note', 'legacy row', 1767225600000)",
      );
      legacy.execute('''
        CREATE TABLE schema_migrations (
          version INTEGER PRIMARY KEY,
          applied_at INTEGER NOT NULL
        );
      ''');
      legacy.execute('INSERT INTO schema_migrations VALUES (1, 1767225600000)');
      legacy.close();

      db = LocalDatabase.open(path);
      repos = StorageRepositories(db);
      expect(db.schemaVersion, 3);
      final row = db.raw.select('SELECT * FROM session_memory').first;
      expect(row['content'], 'legacy row');
      final columns = db.raw
          .select('PRAGMA table_info(provider_configs)')
          .map((r) => r['name'] as String);
      expect(columns, contains('enabled'));
      expect(db.integrityCheck(), isTrue);
    });
  });
}
