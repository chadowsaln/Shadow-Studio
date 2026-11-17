import 'package:local_storage/local_storage.dart';

/// Coordinates local agent memory (session + task) backed by SQLite repositories.
class MemoryManager {
  MemoryManager({
    required TaskMemoryRepository taskRepository,
    SessionMemoryRepository? sessionRepository,
  }) : _tasks = taskRepository,
       _sessions = sessionRepository;

  final TaskMemoryRepository _tasks;
  final SessionMemoryRepository? _sessions;

  /// Stores a task summary/outcome locally. Model-generated memory is marked
  /// untrusted and must never be treated as permissions. Provider secrets must
  /// never be stored (repositories apply redaction; callers must still avoid).
  int storeTaskSummary({
    required String? projectId,
    required String? taskId,
    required String summary,
    required String outcome,
    Map<String, Object?> context = const <String, Object?>{},
    Map<String, Object?> metadata = const <String, Object?>{},
    Duration? ttl,
    DateTime? now,
  }) {
    final ts = (now ?? DateTime.now()).toUtc();
    return _tasks.save(
      TaskMemoryEntry(
        projectId: projectId,
        taskId: taskId,
        summary: summary,
        outcome: outcome,
        context: context,
        metadata: metadata,
        createdAt: ts,
        expiresAt: ttl == null ? null : ts.add(ttl),
        untrusted: true,
      ),
    );
  }

  /// Retrieves relevant previous task summaries for project context.
  /// Returned entries are untrusted memory, never permissions.
  List<Map<String, Object?>> retrieveRelevantSummaries({
    String? projectId,
    String? query,
    int limit = 10,
    DateTime? now,
  }) {
    final entries = _tasks.retrieveRelevant(
      projectId: projectId,
      query: query,
      limit: limit,
      now: now,
    );
    return entries
        .map(
          (e) => <String, Object?>{
            'id': e.id,
            'projectId': e.projectId,
            'taskId': e.taskId,
            'summary': e.summary,
            'outcome': e.outcome,
            'createdAt': e.createdAt.toIso8601String(),
            'untrusted': e.untrusted,
            'source': 'task_memory',
          },
        )
        .toList(growable: false);
  }

  int storeSessionNote({
    required String sessionId,
    String? projectId,
    required String kind,
    required String content,
    Map<String, Object?> metadata = const <String, Object?>{},
    Duration? ttl,
    DateTime? now,
  }) {
    final repo = _sessions;
    if (repo == null) return -1;
    final ts = (now ?? DateTime.now()).toUtc();
    return repo.save(
      SessionMemoryEntry(
        sessionId: sessionId,
        projectId: projectId,
        kind: kind,
        content: content,
        metadata: metadata,
        createdAt: ts,
        expiresAt: ttl == null ? null : ts.add(ttl),
      ),
    );
  }

  /// Supports memory expiration and cleanup.
  CleanupResult cleanupExpired({DateTime? now}) {
    final taskDeleted = _tasks.cleanupExpired(now: now);
    final sessionDeleted = _sessions?.cleanupExpired(now: now) ?? 0;
    return CleanupResult(
      taskDeleted: taskDeleted,
      sessionDeleted: sessionDeleted,
    );
  }

  void close() {
    _tasks.close();
    _sessions?.close();
  }
}

class CleanupResult {
  const CleanupResult({
    required this.taskDeleted,
    required this.sessionDeleted,
  });
  final int taskDeleted;
  final int sessionDeleted;
}
