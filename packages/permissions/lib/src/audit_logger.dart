import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:shadow_contracts/shadow_contracts.dart';

/// Append-only audit log. Never truncates/rewrites existing entries.
@immutable
class AuditRecord {
  const AuditRecord({
    required this.timestamp,
    required this.action,
    required this.outcome,
    required this.details,
  });

  final DateTime timestamp;
  final String action;
  final String outcome; // allowed|denied|error|consent_granted|consent_denied
  final Map<String, Object?> details;

  Map<String, Object?> toJson() => <String, Object?>{
        'ts': timestamp.toUtc().toIso8601String(),
        'action': action,
        'outcome': outcome,
        'details': details,
      };
}

abstract interface class AuditLogger {
  Future<void> log(AuditRecord record);
  Future<void> logSensitive({
    required String action,
    required String outcome,
    Map<String, Object?> details = const <String, Object?>{},
  });
}

class AppendOnlyAuditLogger implements AuditLogger, AuditSink {
  AppendOnlyAuditLogger({required this.logFilePath});

  final String logFilePath;

  @override
  Future<void> record(Map<String, Object?> event) async {
    await log(AuditRecord(
      timestamp: DateTime.now().toUtc(),
      action: (event['type'] ?? 'event').toString(),
      outcome: (event['outcome'] ?? 'recorded').toString(),
      details: Map<String, Object?>.from(event),
    ));
  }

  @override
  Future<void> log(AuditRecord record) async {
    final file = File(logFilePath);
    await file.parent.create(recursive: true);
    final line = '${jsonEncode(record.toJson())}\n';
    // Append-only.
    await file.writeAsString(line, mode: FileMode.append, flush: true);
  }

  @override
  Future<void> logSensitive({
    required String action,
    required String outcome,
    Map<String, Object?> details = const <String, Object?>{},
  }) async {
    await log(AuditRecord(
      timestamp: DateTime.now().toUtc(),
      action: action,
      outcome: outcome,
      details: details,
    ));
  }
}

class InMemoryAuditLogger implements AuditLogger, AuditSink {
  final List<AuditRecord> records = <AuditRecord>[];

  @override
  Future<void> record(Map<String, Object?> event) async {
    records.add(AuditRecord(
      timestamp: DateTime.now().toUtc(),
      action: (event['type'] ?? 'event').toString(),
      outcome: (event['outcome'] ?? 'recorded').toString(),
      details: Map<String, Object?>.from(event),
    ));
  }

  @override
  Future<void> log(AuditRecord record) async {
    records.add(record);
  }

  @override
  Future<void> logSensitive({required String action, required String outcome, Map<String, Object?> details = const <String, Object?>{}}) async {
    records.add(AuditRecord(timestamp: DateTime.now().toUtc(), action: action, outcome: outcome, details: details));
  }
}
