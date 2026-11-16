import '../tools/tool_contracts.dart';

class ApprovalToken {
  const ApprovalToken({
    required this.id,
    required this.toolName,
    required this.inputHash,
    required this.issuedAt,
    required this.expiresAt,
    required this.singleUse,
  });

  final String id;
  final String toolName;
  final String inputHash;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final bool singleUse;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt.toUtc());
}

class PermissionDecision {
  const PermissionDecision._({
    required this.allowed,
    required this.requiresApproval,
    this.approvalToken,
    this.reasonCode,
    this.reason,
  });

  const PermissionDecision.allow()
      : this._(allowed: true, requiresApproval: false);

  const PermissionDecision.requireApproval({String? reason, String? reasonCode})
      : this._(
          allowed: false,
          requiresApproval: true,
          reason: reason,
          reasonCode: reasonCode,
        );

  const PermissionDecision.deny({String? reason, String? reasonCode})
      : this._(
          allowed: false,
          requiresApproval: false,
          reason: reason,
          reasonCode: reasonCode,
        );

  final bool allowed;
  final bool requiresApproval;
  final ApprovalToken? approvalToken;
  final String? reasonCode;
  final String? reason;
}

class EgressRequest {
  const EgressRequest({
    required this.providerId,
    required this.resourceKind,
    required this.resourceRefs,
    this.purpose,
  });

  final String providerId;
  final String resourceKind; // e.g. frame, audio, text, metadata
  final List<String> resourceRefs; // file names/ids only, no contents
  final String? purpose;
}

abstract interface class PermissionService {
  Future<PermissionDecision> authorizeToolCall({
    required String toolName,
    required ToolRiskLevel riskLevel,
    required Map<String, Object?> arguments,
    required String workspaceRoot,
    ApprovalToken? approval,
  });

  Future<PermissionDecision> authorizeEgress(EgressRequest request);

  Future<void> validatePath({
    required String path,
    required String workspaceRoot,
    required bool write,
  });
}
