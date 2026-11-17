import 'dart:convert';

import 'package:shadow_contracts/shadow_contracts.dart';
import 'local_database.dart';

class SqliteCheckpointStore implements CheckpointStore {
  SqliteCheckpointStore(this._db);
  final LocalDatabase _db;

  @override
  Future<void> save(AgentCheckpoint checkpoint) async {
    final stmt = _db.raw.prepare('''
      INSERT INTO execution_checkpoints
        (task_id, sequence, created_at, context_hash, project_revision, workspace_root,
         plan_json, tool_call_count, pending_step_id, last_tool_name, last_tool_idempotent,
         last_tool_arguments_hash, state)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''');
    try {
      stmt.execute([
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
      ]);
    } finally {
      stmt.close();
    }
  }

  @override
  Future<AgentCheckpoint?> latest(String taskId) async {
    final rows = _db.raw.select('''
      SELECT * FROM execution_checkpoints WHERE task_id = ? ORDER BY sequence DESC LIMIT 1
    ''', [taskId]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final planJson =
        jsonDecode(r['plan_json'] as String) as Map<String, dynamic>;
    final plan = AgentPlan.fromJson(planJson);
    final stateName = r['state'] as String;
    final state = AgentTaskState.values.firstWhere((s) => s.name == stateName,
        orElse: () => AgentTaskState.acting);
    final idemp = r['last_tool_idempotent'] as int?;
    return AgentCheckpoint(
      taskId: r['task_id'] as String,
      sequence: r['sequence'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int,
          isUtc: true),
      contextHash: r['context_hash'] as String,
      projectRevision: r['project_revision'] as int,
      workspaceRoot: r['workspace_root'] as String,
      plan: plan,
      toolCallCount: r['tool_call_count'] as int,
      pendingStepId: r['pending_step_id'] as String?,
      lastToolName: r['last_tool_name'] as String?,
      lastToolIdempotent: idemp == null ? null : idemp == 1,
      lastToolArgumentsHash: r['last_tool_arguments_hash'] as String?,
      state: state,
    );
  }

  @override
  Future<void> clear(String taskId) async {
    final stmt =
        _db.raw.prepare('DELETE FROM execution_checkpoints WHERE task_id = ?');
    try {
      stmt.execute([taskId]);
    } finally {
      stmt.close();
    }
  }
}
