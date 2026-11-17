import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:shadow_contracts/shadow_contracts.dart';

final Random _secureRandom = Random.secure();

/// Unguessable identifier for approvals/tokens (128 bits, base64url).
String newSecurityId(String prefix) {
  final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
  return '${prefix}_${base64Url.encode(bytes).replaceAll('=', '')}';
}

@immutable
class ApprovalRequest {
  const ApprovalRequest({
    required this.requestId,
    required this.toolName,
    required this.riskLevel,
    required this.arguments,
    required this.argumentsHash,
    required this.workspaceRoot,
    required this.requestedAt,
    required this.expiresAt,
    this.reason,
    this.reasonCode,
  });

  final String requestId;
  final String toolName;
  final ToolRiskLevel riskLevel;
  final Map<String, Object?> arguments;
  final String argumentsHash;
  final String workspaceRoot;
  final DateTime requestedAt;
  final DateTime expiresAt;
  final String? reason;
  final String? reasonCode;

  bool isExpiredAt(DateTime now) => now.toUtc().isAfter(expiresAt.toUtc());

  bool get isExpired => isExpiredAt(DateTime.now().toUtc());

  /// Audit representation: never contains argument values, only their hash.
  Map<String, Object?> toAudit() => <String, Object?>{
    'request_id': requestId,
    'tool': toolName,
    'risk': riskLevel.name,
    'arguments_hash': argumentsHash,
    'workspace_root': workspaceRoot,
    'requested_at': requestedAt.toUtc().toIso8601String(),
    'expires_at': expiresAt.toUtc().toIso8601String(),
    if (reasonCode != null) 'reason_code': reasonCode,
  };
}

/// Deterministic hash binding an approval to an exact tool call + arguments.
///
/// Canonical JSON (sorted keys) prevents key-order tricks. The hash is an
/// integrity binding, not a secret; argument *values* never enter the audit log.
String hashToolCallBinding({
  required String toolName,
  required Map<String, Object?> arguments,
}) {
  final canonical = _canonicalize(<String, Object?>{
    'tool': toolName,
    'args': arguments,
  });
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((e) => e.toString()).toList()..sort();
    return <String, Object?>{for (final k in keys) k: _canonicalize(value[k])};
  }
  if (value is List) return value.map(_canonicalize).toList();
  return value;
}
