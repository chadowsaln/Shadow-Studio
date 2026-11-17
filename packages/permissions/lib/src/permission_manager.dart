import 'dart:async';

import 'package:shadow_contracts/shadow_contracts.dart' as c;

import 'approval_request.dart';
import 'approval_token.dart';
import 'audit_logger.dart';
import 'path_validator.dart';
import 'permission_policy.dart';
import 'workspace_guard.dart';

/// Explicit, separate consent for AI data egress (never implied by file-operation approvals).
abstract interface class AiEgressConsentManager {
  Future<bool> hasConsent({
    required String providerId,
    required String resourceKind,
    required List<String> resourceRefs,
    String? purpose,
  });

  Future<void> grantConsent({
    required String providerId,
    required String resourceKind,
    required List<String> resourceRefs,
    String? purpose,
    Duration? ttl,
  });

  Future<void> revokeAll();
}

class InMemoryAiEgressConsentManager implements AiEgressConsentManager {
  final Set<String> _grants = <String>{};

  String _key(String providerId, String resourceKind, List<String> refs, String? purpose) {
    final sorted = [...refs]..sort();
    return '$providerId|$resourceKind|${sorted.join(',')}|${purpose ?? ''}';
  }

  @override
  Future<bool> hasConsent({required String providerId, required String resourceKind, required List<String> resourceRefs, String? purpose}) async {
    return _grants.contains(_key(providerId, resourceKind, resourceRefs, purpose));
  }

  @override
  Future<void> grantConsent({required String providerId, required String resourceKind, required List<String> resourceRefs, String? purpose, Duration? ttl}) async {
    _grants.add(_key(providerId, resourceKind, resourceRefs, purpose));
  }

  @override
  Future<void> revokeAll() async {
    _grants.clear();
  }
}

/// Independent permission enforcement (not controllable by model responses).
class PermissionManager implements c.PermissionService {
  PermissionManager({
    PermissionPolicy? policy,
    WorkspaceGuard? workspaceGuard,
    AuditLogger? auditLogger,
    AiEgressConsentManager? egressConsent,
    Duration approvalTtl = const Duration(minutes: 10),
  })  : _policy = policy ?? const PermissionPolicy(),
        _workspaceGuard = workspaceGuard ?? WorkspaceGuard(),
        _audit = auditLogger ?? InMemoryAuditLogger(),
        _egressConsent = egressConsent ?? InMemoryAiEgressConsentManager(),
        _approvalTtl = approvalTtl;

  final PermissionPolicy _policy;
  final WorkspaceGuard _workspaceGuard;
  final AuditLogger _audit;
  final AiEgressConsentManager _egressConsent;
  final Duration _approvalTtl;

  final Map<String, _PendingApproval> _pending = <String, _PendingApproval>{}; // requestId -> pending
  final Set<String> _usedTokenIds = <String>{};

  int _seq = 0;

  /// Create an approval request (to be shown to user). Never auto-approved.
  ApprovalRequest requestApproval({
    required String toolName,
    required c.ToolRiskLevel riskLevel,
    required Map<String, Object?> arguments,
    required String workspaceRoot,
    String? reason,
  }) {
    final now = DateTime.now().toUtc();
    final hash = hashToolCallBinding(toolName: toolName, arguments: arguments);
    final req = ApprovalRequest(
      requestId: 'apr_${now.microsecondsSinceEpoch}_${++_seq}',
      toolName: toolName,
      riskLevel: riskLevel,
      arguments: Map<String, Object?>.unmodifiable(Map<String, Object?>.from(arguments)),
      argumentsHash: hash,
      workspaceRoot: workspaceRoot,
      requestedAt: now,
      expiresAt: now.add(_approvalTtl),
      reason: reason,
      reasonCode: c.ShadowErrorCode.permApprovalRequired,
    );
    _pending[req.requestId] = _PendingApproval(req);
    unawaited(_audit.logSensitive(action: 'approval_requested', outcome: 'pending', details: req.toAudit()));
    return req;
  }

  /// Mint a single-use token for an explicitly approved request. Binds to tool+args hash.
  ApprovalToken? approve(String requestId) {
    final pending = _pending[requestId];
    if (pending == null) return null;
    final req = pending.request;
    if (req.isExpired) {
      _pending.remove(requestId);
      unawaited(_audit.logSensitive(action: 'approval_grant', outcome: 'denied', details: {
        'request_id': requestId,
        'reason_code': c.ShadowErrorCode.permApprovalTimeout,
      }));
      return null;
    }
    final now = DateTime.now().toUtc();
    final token = ApprovalToken(
      id: 'atk_${now.microsecondsSinceEpoch}_${++_seq}',
      toolName: req.toolName,
      inputHash: req.argumentsHash,
      issuedAt: now,
      expiresAt: req.expiresAt,
      singleUse: true,
    );
    pending.grantedToken = token;
    unawaited(_audit.logSensitive(action: 'approval_grant', outcome: 'allowed', details: {
      'request_id': requestId,
      'token_id': token.id,
      'tool': token.toolName,
      'arguments_hash': token.inputHash,
    }));
    return token;
  }

  TokenValidationResult validateToken({
    required ApprovalToken token,
    required String toolName,
    required Map<String, Object?> arguments,
  }) {
    // single-use / replay
    if (_usedTokenIds.contains(token.id)) {
      return const TokenValidationResult.reject(TokenRejectionReason.replayed, c.ShadowErrorCode.permApprovalInvalid);
    }
    // expiry / timeout
    if (token.isExpired) {
      return const TokenValidationResult.reject(TokenRejectionReason.expired, c.ShadowErrorCode.permApprovalTimeout);
    }
    // binding to exact tool call
    if (token.toolName != toolName) {
      return const TokenValidationResult.reject(TokenRejectionReason.invalidBinding, c.ShadowErrorCode.permApprovalInvalid);
    }
    final expectedHash = hashToolCallBinding(toolName: toolName, arguments: arguments);
    if (token.inputHash != expectedHash) {
      return const TokenValidationResult.reject(TokenRejectionReason.modifiedArguments, c.ShadowErrorCode.permApprovalInvalid);
    }
    if (token.singleUse != true) {
      return const TokenValidationResult.reject(TokenRejectionReason.invalidBinding, c.ShadowErrorCode.permApprovalInvalid);
    }
    return const TokenValidationResult.ok();
  }

  void consumeToken(String tokenId) {
    _usedTokenIds.add(tokenId);
  }

  @override
  Future<c.PermissionDecision> authorizeToolCall({
    required String toolName,
    required c.ToolRiskLevel riskLevel,
    required Map<String, Object?> arguments,
    required String workspaceRoot,
    c.ApprovalToken? approval,
  }) async {
    // Cancellation gate: if caller passes a cancelled context they must not execute; here we cannot see token,
    // but engine is used with ToolContext in executor which checks cancel before execute. We defensively allow
    // manager to be used directly too via guard method below.

    // 1) Path validation (canonical, no traversal/symlink escape)
    try {
      await _workspaceGuard.validateArgumentsPaths(arguments: arguments, workspaceRoot: workspaceRoot);
    } on PathSecurityException catch (e) {
      await _audit.logSensitive(action: 'authorize_tool', outcome: 'denied', details: {
        'tool': toolName,
        'reason_code': e.code,
      });
      return c.PermissionDecision.deny(reason: e.message, reasonCode: e.code);
    }

    final insideDefault = await _isInsideWorkspaceRoot(workspaceRoot: workspaceRoot, arguments: arguments);
    final involvesSpending = arguments['declaredAiSpending'] == true || arguments['involvesAiSpending'] == true;

    final effectiveRisk = _policy.classify(toolName, declared: riskLevel);

    // 2) Approval validation if provided
    ApprovalToken? validToken;
    if (approval != null) {
      final engineToken = ApprovalToken.fromContract(approval);
      final vr = validateToken(token: engineToken, toolName: toolName, arguments: arguments);
      if (!vr.ok) {
        await _audit.logSensitive(action: 'authorize_tool', outcome: 'denied', details: {
          'tool': toolName,
          'reason_code': vr.code,
          'token_id': approval.id,
        });
        return c.PermissionDecision.deny(reason: 'Approval token invalid', reasonCode: vr.code ?? c.ShadowErrorCode.permApprovalInvalid);
      }
      validToken = engineToken;
    }

    final policy = _policy.evaluate(
      toolName: toolName,
      riskLevel: effectiveRisk,
      arguments: arguments,
      insideDefaultWorkspace: insideDefault,
      hasValidApproval: validToken != null,
      involvesDeclaredSpending: involvesSpending,
    );

    switch (policy.effect) {
      case PolicyEffect.allow:
        if (validToken != null) {
          consumeToken(validToken.id);
          _pending.removeWhere((_, p) => p.grantedToken?.id == validToken!.id);
        }
        await _audit.logSensitive(action: 'authorize_tool', outcome: 'allowed', details: {
          'tool': toolName,
          'risk': effectiveRisk.name,
          'approval_used': validToken != null,
        });
        return const c.PermissionDecision.allow();
      case PolicyEffect.requireApproval:
        await _audit.logSensitive(action: 'authorize_tool', outcome: 'denied', details: {
          'tool': toolName,
          'risk': effectiveRisk.name,
          'reason_code': policy.reasonCode ?? c.ShadowErrorCode.permApprovalRequired,
        });
        return c.PermissionDecision.requireApproval(
          reason: policy.reason,
          reasonCode: policy.reasonCode ?? c.ShadowErrorCode.permApprovalRequired,
        );
      case PolicyEffect.deny:
        await _audit.logSensitive(action: 'authorize_tool', outcome: 'denied', details: {
          'tool': toolName,
          'risk': effectiveRisk.name,
          'reason_code': policy.reasonCode,
        });
        return c.PermissionDecision.deny(reason: policy.reason, reasonCode: policy.reasonCode);
    }
  }

  @override
  Future<c.PermissionDecision> authorizeEgress(c.EgressRequest request) async {
    // Separate explicit consent mechanism; file-operation approvals do not apply.
    final has = await _egressConsent.hasConsent(
      providerId: request.providerId,
      resourceKind: request.resourceKind,
      resourceRefs: request.resourceRefs,
      purpose: request.purpose,
    );
    if (!has) {
      await _audit.logSensitive(action: 'ai_egress', outcome: 'denied', details: {
        'provider': request.providerId,
        'kind': request.resourceKind,
        'count': request.resourceRefs.length,
        'reason_code': c.ShadowErrorCode.permApprovalRequired,
      });
      return const c.PermissionDecision.requireApproval(
        reason: 'Explicit AI data egress consent required',
        reasonCode: c.ShadowErrorCode.permApprovalRequired,
      );
    }
    await _audit.logSensitive(action: 'ai_egress', outcome: 'allowed', details: {
      'provider': request.providerId,
      'kind': request.resourceKind,
      'count': request.resourceRefs.length,
    });
    return const c.PermissionDecision.allow();
  }

  @override
  Future<void> validatePath({required String path, required String workspaceRoot, required bool write}) async {
    try {
      await _workspaceGuard.ensurePathAllowed(path: path, workspaceRoot: workspaceRoot);
    } on PathSecurityException catch (e) {
      await _audit.logSensitive(action: 'validate_path', outcome: 'denied', details: {
        'reason_code': e.code,
        'write': write,
      });
      throw PathSecurityException(code: e.code, message: e.message);
    }
  }

  Future<bool> _isInsideWorkspaceRoot({required String workspaceRoot, required Map<String, Object?> arguments}) async {
    final paths = _workspaceGuard.collectPathValues(arguments);
    if (paths.isEmpty) return true;
    final validator = const PathValidator();
    for (final path in paths) {
      try {
        await validator.canonicalizeWithinWorkspace(targetPath: path, workspaceRoot: workspaceRoot);
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// Cancellation must prevent subsequent tool execution: call before executing a tool.
  void assertNotCancelled(c.CancellationToken cancel) {
    if (cancel.isCancelled) {
      throw c.CancelledException(reason: cancel.reason);
    }
  }

  /// No permanent approval mode. Clear pending grants (keeps used-token replay protection).
  void clearPendingApprovals() {
    _pending.clear();
  }

  AiEgressConsentManager get egressConsent => _egressConsent;
}

class _PendingApproval {
  _PendingApproval(this.request);
  final ApprovalRequest request;
  ApprovalToken? grantedToken;
}
