import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:shadow_contracts/shadow_contracts.dart';

/// Recursively removes secret material before anything reaches an audit sink.
///
/// Redaction is key-based (api keys, tokens, passwords, credentials,
/// authorization headers) plus a few well-known value patterns. Audit events
/// should never carry raw tool arguments in the first place; this is defense in
/// depth for accidental logging.
Object? redactForAudit(Object? value) {
  if (value is Map) {
    final out = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key.toString();
      if (_sensitiveKeyPattern.hasMatch(key)) {
        out[key] = '[REDACTED]';
      } else {
        out[key] = redactForAudit(entry.value);
      }
    }
    return out;
  }
  if (value is Iterable) {
    return value.map(redactForAudit).toList();
  }
  if (value is String) {
    var redacted = value;
    for (final pattern in _sensitiveValuePatterns) {
      redacted = redacted.replaceAll(pattern, '[REDACTED]');
    }
    return redacted;
  }
  return value;
}

final RegExp _sensitiveKeyPattern = RegExp(
  r'(api[_-]?key|secret|token|password|passwd|authorization|auth[_-]?header|credential|private[_-]?key|bearer|session[_-]?id)',
  caseSensitive: false,
);

final List<RegExp> _sensitiveValuePatterns = <RegExp>[
  RegExp(r'sk-[A-Za-z0-9_\-]{8,}'),
  RegExp(r'Bearer\s+[A-Za-z0-9._\-]+', caseSensitive: false),
  RegExp(r'AKIA[0-9A-Z]{16}'),
  RegExp(r'AIza[0-9A-Za-z_\-]{20,}'),
];

/// Append-only audit record. `prevHash`/`hash` turn the log into a hash chain.
@immutable
class AuditRecord {
  const AuditRecord({
    required this.timestamp,
    required this.action,
    required this.outcome,
    required this.details,
    this.prevHash,
    this.hash,
  });

  final DateTime timestamp;
  final String action;
  final String outcome; // allowed|denied|error|pending
  final Map<String, Object?> details;
  final String? prevHash;
  final String? hash;

  AuditRecord withChain({required String prevHash, required String hash}) =>
      AuditRecord(
        timestamp: timestamp,
        action: action,
        outcome: outcome,
        details: details,
        prevHash: prevHash,
        hash: hash,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'ts': timestamp.toUtc().toIso8601String(),
    'action': action,
    'outcome': outcome,
    'details': redactForAudit(details),
    if (prevHash != null) 'prev_hash': prevHash,
    if (hash != null) 'hash': hash,
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

/// Filesystem audit sink.
///
/// * append-only (`FileMode.append`, flush per record);
/// * secret values redacted before serialization;
/// * SHA-256 hash chain so truncation/modification is detectable via
///   [verifyChain];
/// * writes serialized through a future queue to keep the chain consistent
///   under concurrent tool calls;
/// * best-effort `0600` permissions on POSIX.
///
/// The chain is tamper-*evident*, not tamper-*proof*: a local attacker who can
/// rewrite the whole file can recompute it. Documented in the security model.
class AppendOnlyAuditLogger implements AuditLogger, AuditSink {
  AppendOnlyAuditLogger({required this.logFilePath});

  final String logFilePath;

  static final String genesisHash = List<String>.filled(64, '0').join();

  String? _lastHash;
  Future<void> _writeQueue = Future<void>.value();

  @override
  Future<void> record(Map<String, Object?> event) async {
    await log(
      AuditRecord(
        timestamp: DateTime.now().toUtc(),
        action: (event['type'] ?? 'event').toString(),
        outcome: (event['outcome'] ?? 'recorded').toString(),
        details: Map<String, Object?>.from(event),
      ),
    );
  }

  @override
  Future<void> log(AuditRecord record) {
    final operation = _writeQueue.then((_) => _append(record));
    // Keep the queue alive even if one append fails; the failed future is
    // still returned to the caller.
    _writeQueue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<void> _append(AuditRecord record) async {
    final file = File(logFilePath);
    await file.parent.create(recursive: true);
    final prevHash = _lastHash ?? await _readLastHash(file);
    final safeDetails = redactForAudit(record.details) as Map<String, Object?>;
    final payload = <String, Object?>{
      'ts': record.timestamp.toUtc().toIso8601String(),
      'action': record.action,
      'outcome': record.outcome,
      'details': safeDetails,
      'prev_hash': prevHash,
    };
    final hash = sha256.convert(utf8.encode(jsonEncode(payload))).toString();
    final line = '${jsonEncode(<String, Object?>{...payload, 'hash': hash})}\n';
    await file.writeAsString(line, mode: FileMode.append, flush: true);
    _lastHash = hash;
    _bestEffortRestrictPermissions(file);
  }

  Future<String> _readLastHash(File file) async {
    if (!await file.exists()) return genesisHash;
    try {
      final lines = await file.readAsLines();
      for (var i = lines.length - 1; i >= 0; i--) {
        final trimmed = lines[i].trim();
        if (trimmed.isEmpty) continue;
        final decoded = jsonDecode(trimmed);
        if (decoded is Map && decoded['hash'] is String) {
          return decoded['hash'] as String;
        }
        break;
      }
    } on FileSystemException {
      // Unreadable log: start a new chain segment rather than blocking audits.
    }
    return genesisHash;
  }

  /// Recomputes the whole chain. Returns the first broken record, if any.
  Future<AuditChainVerification> verifyChain() async {
    final file = File(logFilePath);
    if (!await file.exists()) {
      return const AuditChainVerification(
        valid: true,
        recordCount: 0,
        brokenAtLine: null,
        reason: null,
      );
    }
    final lines = await file.readAsLines();
    var expectedPrev = genesisHash;
    var index = 0;
    for (final line in lines) {
      index++;
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        return AuditChainVerification(
          valid: false,
          recordCount: index - 1,
          brokenAtLine: index,
          reason: 'Record is not a JSON object',
        );
      }
      final claimedHash = decoded['hash'];
      final claimedPrev = decoded['prev_hash'];
      if (claimedHash is! String || claimedPrev is! String) {
        return AuditChainVerification(
          valid: false,
          recordCount: index - 1,
          brokenAtLine: index,
          reason: 'Missing hash fields',
        );
      }
      if (claimedPrev != expectedPrev) {
        return AuditChainVerification(
          valid: false,
          recordCount: index - 1,
          brokenAtLine: index,
          reason: 'Previous-hash mismatch (truncated or reordered log)',
        );
      }
      final payload = Map<String, Object?>.from(decoded)..remove('hash');
      final computed = sha256
          .convert(utf8.encode(jsonEncode(payload)))
          .toString();
      if (computed != claimedHash) {
        return AuditChainVerification(
          valid: false,
          recordCount: index - 1,
          brokenAtLine: index,
          reason: 'Record hash mismatch (modified record)',
        );
      }
      expectedPrev = claimedHash;
    }
    return AuditChainVerification(
      valid: true,
      recordCount: index,
      brokenAtLine: null,
      reason: null,
    );
  }

  void _bestEffortRestrictPermissions(File file) {
    if (Platform.isWindows) return;
    try {
      Process.runSync('chmod', <String>['600', file.path]);
    } on ProcessException {
      // Best effort only; the file is still append-only and redacted.
    }
  }

  @override
  Future<void> logSensitive({
    required String action,
    required String outcome,
    Map<String, Object?> details = const <String, Object?>{},
  }) async {
    await log(
      AuditRecord(
        timestamp: DateTime.now().toUtc(),
        action: action,
        outcome: outcome,
        details: details,
      ),
    );
  }
}

@immutable
class AuditChainVerification {
  const AuditChainVerification({
    required this.valid,
    required this.recordCount,
    this.brokenAtLine,
    this.reason,
  });

  final bool valid;
  final int recordCount;
  final int? brokenAtLine;
  final String? reason;
}

/// In-memory sink for tests and embedding. Applies the same redaction.
class InMemoryAuditLogger implements AuditLogger, AuditSink {
  final List<AuditRecord> records = <AuditRecord>[];

  @override
  Future<void> record(Map<String, Object?> event) async {
    await log(
      AuditRecord(
        timestamp: DateTime.now().toUtc(),
        action: (event['type'] ?? 'event').toString(),
        outcome: (event['outcome'] ?? 'recorded').toString(),
        details: Map<String, Object?>.from(event),
      ),
    );
  }

  @override
  Future<void> log(AuditRecord record) async {
    records.add(
      AuditRecord(
        timestamp: record.timestamp,
        action: record.action,
        outcome: record.outcome,
        details: (redactForAudit(record.details) as Map<String, Object?>),
        prevHash: record.prevHash,
        hash: record.hash,
      ),
    );
  }

  @override
  Future<void> logSensitive({
    required String action,
    required String outcome,
    Map<String, Object?> details = const <String, Object?>{},
  }) async {
    await log(
      AuditRecord(
        timestamp: DateTime.now().toUtc(),
        action: action,
        outcome: outcome,
        details: details,
      ),
    );
  }
}
