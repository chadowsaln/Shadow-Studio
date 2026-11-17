import 'dart:convert';

import 'local_database.dart';

class SessionMemoryEntry {
  const SessionMemoryEntry({
    this.id,
    required this.sessionId,
    this.projectId,
    required this.kind,
    required this.content,
    this.metadata = const <String, Object?>{},
    required this.createdAt,
    this.expiresAt,
  });

  final int? id;
  final String sessionId;
  final String? projectId;
  final String kind; // e.g. context_snapshot_ref, note (non-secret)
  final String content;
  final Map<String, Object?> metadata;
  final DateTime createdAt;
  final DateTime? expiresAt;
}

/// Repository interface for session-scoped memory.
abstract class SessionMemoryRepository {
  int save(SessionMemoryEntry entry);
  List<SessionMemoryEntry> listBySession(String sessionId, {int limit = 50, DateTime? now});
  int cleanupExpired({DateTime? now});
  void close();
}

class SqliteSessionMemoryRepository implements SessionMemoryRepository {
  SqliteSessionMemoryRepository(this._db);
  final LocalDatabase _db;

  @override
  int save(SessionMemoryEntry entry) {
    final stmt = _db.raw.prepare('''
      INSERT INTO session_memory
        (session_id, project_id, kind, content, metadata, created_at, expires_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    ''');
    try {
      stmt.execute([
        entry.sessionId,
        entry.projectId,
        entry.kind,
        entry.content,
        jsonEncode(entry.metadata),
        entry.createdAt.millisecondsSinceEpoch,
        entry.expiresAt?.millisecondsSinceEpoch,
      ]);
      return _db.raw.lastInsertRowId;
    } finally {
      stmt.close();
    }
  }

  @override
  List<SessionMemoryEntry> listBySession(String sessionId, {int limit = 50, DateTime? now}) {
    final ts = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final rows = _db.raw.select('''
      SELECT id, session_id, project_id, kind, content, metadata, created_at, expires_at
      FROM session_memory
      WHERE session_id = ? AND (expires_at IS NULL OR expires_at > ?)
      ORDER BY created_at DESC
      LIMIT ?
    ''', [sessionId, ts, limit]);
    return rows.map((r) {
      Map<String, Object?> meta = const <String, Object?>{};
      final ms = r['metadata'] as String?;
      if (ms != null && ms.isNotEmpty) {
        final v = jsonDecode(ms);
        if (v is Map) meta = v.cast<String, Object?>();
      }
      final exp = r['expires_at'] as int?;
      return SessionMemoryEntry(
        id: r['id'] as int,
        sessionId: r['session_id'] as String,
        projectId: r['project_id'] as String?,
        kind: r['kind'] as String,
        content: r['content'] as String? ?? '',
        metadata: meta,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int, isUtc: true),
        expiresAt: exp == null ? null : DateTime.fromMillisecondsSinceEpoch(exp, isUtc: true),
      );
    }).toList(growable: false);
  }

  @override
  int cleanupExpired({DateTime? now}) {
    final ts = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final stmt = _db.raw.prepare(
      'DELETE FROM session_memory WHERE expires_at IS NOT NULL AND expires_at <= ?',
    );
    try {
      stmt.execute([ts]);
      final changed = _db.raw.select('SELECT changes() AS c').first['c'] as int;
      return changed;
    } finally {
      stmt.close();
    }
  }

  @override
  void close() => _db.close();
}
