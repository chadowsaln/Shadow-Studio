import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:shadow_contracts/shadow_contracts.dart';

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

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt.toUtc());

  Map<String, Object?> toAudit() => <String, Object?>{
        'request_id': requestId,
        'tool': toolName,
        'risk': riskLevel.name,
        'arguments_hash': argumentsHash,
        'workspace_root': workspaceRoot,
        'requested_at': requestedAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        if (reasonCode != null) 'reason_code': reasonCode,
      };
}

/// Deterministic hash for binding approvals to exact tool call + arguments.
String hashToolCallBinding({required String toolName, required Map<String, Object?> arguments}) {
  final canonical = _canonicalize(<String, Object?>{'tool': toolName, 'args': arguments});
  final payload = jsonEncode(canonical);
  return _fnv1a64Hex(payload);
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((e) => e.toString()).toList()..sort();
    return <String, Object?>{for (final k in keys) k: _canonicalize(value[k])};
  }
  if (value is List) return value.map(_canonicalize).toList();
  return value;
}

String _fnv1a64Hex(String input) {
  const int offset = 0xcbf29ce484222325;
  const int prime = 0x100000001b3;
  const int mask = 0xFFFFFFFFFFFFFFFF;
  var hash = offset;
  for (final byte in utf8.encode(input)) {
    hash ^= byte;
    hash = (hash * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
