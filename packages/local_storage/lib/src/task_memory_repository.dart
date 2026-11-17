import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'local_database.dart';

/// A locally stored summary/outcome of a previous task.
class TaskMemoryEntry {
  const TaskMemoryEntry({
    this.id,
    required this.projectId,
    required this.taskId,
    required this.summary,
    required this.outcome,
    this.context = const <String, Object?>{},
    this.metadata = const <String, Object?>{},
    required this.createdAt,
    this.expiresAt,
    this.untrusted = true,
  });

  final int? id;
  final String? projectId;
  final String? taskId;
  final String summary;
  final String outcome;
  final Map<String, Object?> context;
  final Map<String, Object?> metadata;
  final DateTime createdAt;
  final DateTime? expiresAt;

  /// Memory derived from model/agent output is never treated as trusted
  /// permissions or security policy.
  final bool untrusted;

  bool isExpired(DateTime now) => expiresAt != null && !now.isBefore(expiresAt!);

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'projectId': projectId,
        'taskId': taskId,
        'summary': summary,
        'outcome': outcome,
        'context': context,
        'metadata': metadata,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
        'untrusted': untrusted,
      };
}

/// Repository interface for task-scoped memory.
abstract class TaskMemoryRepository {
  int save(TaskMemoryEntry entry);

  /// Retrieves relevant previous task summaries for [projectId], most recent first.
  List<TaskMemoryEntry> retrieveRelevant({
    String? projectId,
    String? query,
    int limit = 10,
    DateTime? now,
  });

  int cleanupExpired({DateTime? now});

  void close();
}

/// SQLite-backed implementation.
class SqliteTaskMemoryRepository implements TaskMemoryRepository {
  SqliteTaskMemoryRepository(this._db);

  final LocalDatabase _db;

  @override
  int save(TaskMemoryEntry entry) {
    final stmt = _db.raw.prepare('''
      INSERT INTO task_memory
        (project_id, task_id, summary, outcome, context_json, metadata, untrusted, created_at, expires_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''');
    try {
      stmt.execute([
        entry.projectId,
        entry.taskId,
        _redactSecrets(entry.summary),
        _redactSecrets(entry.outcome),
        jsonEncode(_redactMap(entry.context)),
        jsonEncode(_redactMap(entry.metadata)),
        entry.untrusted ? 1 : 0,
        entry.createdAt.millisecondsSinceEpoch,
        entry.expiresAt?.millisecondsSinceEpoch,
      ]);
      return _db.raw.lastInsertRowId;
    } finally {
      stmt.close();
    }
  }

  @override
  List<TaskMemoryEntry> retrieveRelevant({
    String? projectId,
    String? query,
    int limit = 10,
    DateTime? now,
  }) {
    final ts = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final clauses = <String>['(expires_at IS NULL OR expires_at > ?)'];
    final args = <Object?>[ts];
    if (projectId != null) {
      clauses.add('project_id = ?');
      args.add(projectId);
    }
    final q = query?.trim();
    if (q != null && q.isNotEmpty) {
      clauses.add('(summary LIKE ? OR outcome LIKE ?)');
      final like = '%${q.replaceAll('%', '')}%';
      args..add(like)..add(like);
    }
    args.add(limit);
    final sql = '''
      SELECT id, project_id, task_id, summary, outcome, context_json, metadata, untrusted, created_at, expires_at
      FROM task_memory
      WHERE ${clauses.join(' AND ')}
      ORDER BY created_at DESC
      LIMIT ?
    ''';
    final rows = _db.raw.select(sql, args);
    return rows.map(_rowToEntry).toList(growable: false).cast<TaskMemoryEntry>();
  }

  @override
  int cleanupExpired({DateTime? now}) {
    final ts = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final stmt = _db.raw.prepare(
      'DELETE FROM task_memory WHERE expires_at IS NOT NULL AND expires_at <= ?',
    );
    try {
      stmt.execute([ts]);
      // sqlite3 package: changes available via updated rows on select changes()
      final changed = _db.raw.select('SELECT changes() AS c').first['c'] as int;
      return changed;
    } finally {
      stmt.close();
    }
  }

  @override
  void close() => _db.close();

  TaskMemoryEntry _rowToEntry(Row row) {
    Map<String, Object?> decode(String? s) {
      if (s == null || s.isEmpty) return const <String, Object?>{};
      final v = jsonDecode(s);
      return v is Map ? v.cast<String, Object?>() : const <String, Object?>{};
    }

    final expires = row['expires_at'] as int?;
    return TaskMemoryEntry(
      id: row['id'] as int,
      projectId: row['project_id'] as String?,
      taskId: row['task_id'] as String?,
      summary: row['summary'] as String? ?? '',
      outcome: row['outcome'] as String? ?? '',
      context: decode(row['context_json'] as String?),
      metadata: decode(row['metadata'] as String?),
      untrusted: (row['untrusted'] as int? ?? 1) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int, isUtc: true),
      expiresAt: expires == null ? null : DateTime.fromMillisecondsSinceEpoch(expires, isUtc: true),
    );
  }
}

const _secretKeyFragments = <String>[
  'api_key', 'apikey', 'secret', 'token', 'password', 'credential', 'private_key', 'bearer',
];

String _redactSecrets(String input) {
  // Conservative: redact obvious bearer/key-like patterns.
  var out = input.replaceAll(RegExp(r'(sk-[A-Za-z0-9_-]{8,})'), '[REDACTED_SECRET]');
  out = out.replaceAll(RegExp(r'(Bearer\s+)[A-Za-z0-9._\-]+', caseSensitive: false), r'$1[REDACTED_SECRET]');
  return out;
}

Map<String, Object?> _redactMap(Map<String, Object?> input) {
  Object? redact(Object? v) {
    if (v is Map) {
      return _redactMap(v.cast<String, Object?>());
    } else if (v is List) {
      return v.map(redact).toList(growable: false);
    } else if (v is String) {
      return _redactSecrets(v);
    }
    return v;
  }

  final out = <String, Object?>{};
  for (final e in input.entries) {
    final lower = e.key.toLowerCase();
    if (_secretKeyFragments.any((f) => lower.contains(f))) {
      out[e.key] = '[REDACTED_SECRET]';
    } else {
      out[e.key] = redact(e.value);
    }
  }
  return out;
}
