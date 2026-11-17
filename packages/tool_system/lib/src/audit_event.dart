import 'dart:convert';

import 'package:shadow_contracts/shadow_contracts.dart';

class ToolExecutionRecord {
  const ToolExecutionRecord({
    required this.toolName,
    required this.taskId,
    required this.correlationId,
    required this.revisionBefore,
    required this.revisionAfter,
    required this.argumentsHash,
    required this.success,
    required this.startedAt,
    required this.endedAt,
    this.errorCode,
    this.truncated = false,
  });

  final String toolName;
  final String taskId;
  final String correlationId;
  final int revisionBefore;
  final int? revisionAfter;
  final String argumentsHash;
  final bool success;
  final DateTime startedAt;
  final DateTime endedAt;
  final String? errorCode;
  final bool truncated;

  Map<String, Object?> toAuditEvent() => <String, Object?>{
        'type': 'tool_execution',
        'tool': toolName,
        'task_id': taskId,
        'correlation_id': correlationId,
        'revision_before': revisionBefore,
        'revision_after': revisionAfter,
        'arguments_hash': argumentsHash,
        'success': success,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'duration_ms': endedAt.difference(startedAt).inMilliseconds,
        if (errorCode != null) 'error_code': errorCode,
        'truncated': truncated,
      };
}

String hashArguments(Map<String, Object?> args) {
  final s = jsonEncode(_canonical(args));
  // simple deterministic hash (FNV-1a 64-bit) without crypto dep
  var h = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * prime) & 0xFFFFFFFFFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(16, '0');
}

Object? _canonical(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _canonical(v[k])};
  }
  if (v is List) return [for (final e in v) _canonical(e)];
  return v;
}
