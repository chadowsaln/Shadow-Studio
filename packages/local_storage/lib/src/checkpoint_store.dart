import 'dart:convert';

import 'package:shadow_contracts/shadow_contracts.dart';
import 'local_database.dart';

/// SQLite checkpoint store.
///
/// Every save is a single committed INSERT, so a process kill leaves either the
/// previous checkpoint or the new one, never a partial row. Reads are strict:
/// a malformed row raises [CheckpointCorruptException] for `latest` (recovery
/// must not silently resume from stale state). History and `latestAll` skip
/// corrupt rows so one bad task cannot hide the others.
class SqliteCheckpointStore implements CheckpointStore {
  SqliteCheckpointStore(this._db);
  final LocalDatabase _db;

  static const String _columns = '''
    task_id, sequence, created_at, context_hash, project_revision, workspace_root,
    plan_json, tool_call_count, pending_step_id, last_tool_name, last_tool_idempotent,
    last_tool_arguments_hash, state, request, metadata_json, last_tool_status,
    last_tool_error_code, last_tool_error_message, error_code, error_message, summary,
    resume_count, partial_artifacts_json, last_heartbeat_at, run_id, process_id
  ''';

  @override
  Future<void> save(AgentCheckpoint checkpoint) async {
    final stmt = _db.raw.prepare('''
      INSERT INTO execution_checkpoints ($_columns)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''');
    try {
      // `execution_checkpoints.task_id` references `agent_tasks`; make sure the
      // owning row exists so checkpoints remain writable for embedders that did
      // not create a task record first. Never overwrite an existing task row.
      _db.raw.execute('''
        INSERT OR IGNORE INTO agent_tasks
          (id, state, request, project_revision, workspace_root, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      ''', <Object?>[
        checkpoint.taskId,
        checkpoint.state.name,
        checkpoint.request,
        checkpoint.projectRevision,
        checkpoint.workspaceRoot,
        checkpoint.createdAt.millisecondsSinceEpoch,
        checkpoint.createdAt.millisecondsSinceEpoch,
      ]);
      stmt.execute(<Object?>[
        checkpoint.taskId,
        checkpoint.sequence,
        checkpoint.createdAt.millisecondsSinceEpoch,
        checkpoint.contextHash,
        checkpoint.projectRevision,
        checkpoint.workspaceRoot,
        jsonEncode(checkpoint.plan.toJson()),
        checkpoint.toolCallCount,
        checkpoint.pendingStepId,
        checkpoint.lastToolName,
        checkpoint.lastToolIdempotent == null
            ? null
            : (checkpoint.lastToolIdempotent! ? 1 : 0),
        checkpoint.lastToolArgumentsHash,
        checkpoint.state.name,
        checkpoint.request,
        jsonEncode(checkpoint.metadata),
        checkpoint.lastToolStatus.name,
        checkpoint.lastToolErrorCode,
        checkpoint.lastToolErrorMessage,
        checkpoint.errorCode,
        checkpoint.errorMessage,
        checkpoint.summary,
        checkpoint.resumeCount,
        jsonEncode(checkpoint.partialArtifacts),
        checkpoint.lastHeartbeatAt?.millisecondsSinceEpoch,
        checkpoint.runId,
        checkpoint.processId,
      ]);
    } finally {
      stmt.close();
    }
  }

  @override
  Future<AgentCheckpoint?> latest(String taskId) async {
    final rows = _db.raw.select('''
      SELECT * FROM execution_checkpoints
      WHERE task_id = ?
      ORDER BY sequence DESC
      LIMIT 1
    ''', <Object?>[taskId]);
    if (rows.isEmpty) return null;
    return _parseStrict(rows.first);
  }

  @override
  Future<List<AgentCheckpoint>> history(
    String taskId, {
    int limit = 50,
  }) async {
    if (limit <= 0) return const <AgentCheckpoint>[];
    final rows = _db.raw.select('''
      SELECT * FROM execution_checkpoints
      WHERE task_id = ?
      ORDER BY sequence DESC
      LIMIT ?
    ''', <Object?>[taskId, limit]);
    final out = <AgentCheckpoint>[];
    for (final row in rows) {
      final cp = _parseLenient(row);
      if (cp != null) out.add(cp);
    }
    return out;
  }

  @override
  Future<List<AgentCheckpoint>> latestAll() async {
    final rows = _db.raw.select('''
      SELECT c.* FROM execution_checkpoints c
      JOIN (
        SELECT task_id, MAX(sequence) AS seq
        FROM execution_checkpoints
        GROUP BY task_id
      ) m ON c.task_id = m.task_id AND c.sequence = m.seq
      ORDER BY COALESCE(c.last_heartbeat_at, c.created_at) DESC
    ''');
    final out = <AgentCheckpoint>[];
    for (final row in rows) {
      final cp = _parseLenient(row);
      if (cp != null) out.add(cp);
    }
    return out;
  }

  @override
  Future<void> clear(String taskId) async {
    final stmt =
        _db.raw.prepare('DELETE FROM execution_checkpoints WHERE task_id = ?');
    try {
      stmt.execute(<Object?>[taskId]);
    } finally {
      stmt.close();
    }
  }

  AgentCheckpoint _parseStrict(Map<String, Object?> row) {
    final json = _rowToJson(row);
    return AgentCheckpoint.fromJson(json);
  }

  AgentCheckpoint? _parseLenient(Map<String, Object?> row) {
    try {
      return _parseStrict(row);
    } on CheckpointCorruptException {
      return null;
    }
  }

  Map<String, Object?> _rowToJson(Map<String, Object?> row) {
    final taskId = row['task_id'];
    Object? plan;
    Object? metadata;
    Object? partialArtifacts;
    try {
      plan = jsonDecode((row['plan_json'] as String?) ?? '{}');
    } catch (error) {
      throw CheckpointCorruptException(
        taskId: taskId is String ? taskId : null,
        message: 'Checkpoint plan_json is not valid JSON: $error',
      );
    }
    try {
      metadata = jsonDecode((row['metadata_json'] as String?) ?? '{}');
    } catch (error) {
      throw CheckpointCorruptException(
        taskId: taskId is String ? taskId : null,
        message: 'Checkpoint metadata_json is not valid JSON: $error',
      );
    }
    try {
      partialArtifacts = jsonDecode(
        (row['partial_artifacts_json'] as String?) ?? '[]',
      );
    } catch (error) {
      throw CheckpointCorruptException(
        taskId: taskId is String ? taskId : null,
        message: 'Checkpoint partial_artifacts_json is not valid JSON: $error',
      );
    }

    final createdMs = row['created_at'];
    final heartbeatMs = row['last_heartbeat_at'];
    final idempotent = row['last_tool_idempotent'];
    return <String, Object?>{
      'taskId': taskId,
      'sequence': row['sequence'],
      'createdAt': createdMs is int
          ? DateTime.fromMillisecondsSinceEpoch(createdMs, isUtc: true)
              .toIso8601String()
          : null,
      'contextHash': row['context_hash'],
      'projectRevision': row['project_revision'],
      'workspaceRoot': row['workspace_root'],
      'plan': plan,
      'toolCallCount': row['tool_call_count'],
      'pendingStepId': row['pending_step_id'],
      'request': row['request'],
      'metadata': metadata,
      'lastToolName': row['last_tool_name'],
      'lastToolIdempotent': idempotent is int ? idempotent == 1 : null,
      'lastToolArgumentsHash': row['last_tool_arguments_hash'],
      'lastToolStatus': row['last_tool_status'],
      'lastToolErrorCode': row['last_tool_error_code'],
      'lastToolErrorMessage': row['last_tool_error_message'],
      'lastHeartbeatAt': heartbeatMs is int
          ? DateTime.fromMillisecondsSinceEpoch(heartbeatMs, isUtc: true)
              .toIso8601String()
          : null,
      'runId': row['run_id'],
      'processId': row['process_id'],
      'resumeCount': row['resume_count'],
      'partialArtifacts': partialArtifacts,
      'errorCode': row['error_code'],
      'errorMessage': row['error_message'],
      'summary': row['summary'],
      'state': row['state'],
    };
  }
}
