import 'dart:async';

import 'package:shadow_contracts/shadow_contracts.dart' as c;

import 'approval_request.dart';
import 'approval_token.dart';
import 'audit_logger.dart';
import 'path_validator.dart';
import 'permission_policy.dart';
import 'secret_store.dart';
import 'shell_guard.dart';
import 'workspace_guard.dart';

/// Explicit, separate consent for AI data egress (never implied by
/// file-operation approvals).
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

/// Consent grants carry an expiry. Defaults to 30 minutes.
class InMemoryAiEgressConsentManager implements AiEgressConsentManager {
  InMemoryAiEgressConsentManager({
    this.defaultTtl = const Duration(minutes: 30),
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final Duration defaultTtl;
  final DateTime Function() _now;

  final Map<String, DateTime> _grants = <String, DateTime>{};

  String _key(
    String providerId,
    String resourceKind,
    List<String> refs,
    String? purpose,
  ) {
    final sorted = [...refs]..sort();
    return '$providerId|$resourceKind|${sorted.join(',')}|${purpose ?? ''}';
  }

  @override
  Future<bool> hasConsent({
    required String providerId,
    required String resourceKind,
    required List<String> resourceRefs,
    String? purpose,
  }) async {
    final key = _key(providerId, resourceKind, resourceRefs, purpose);
    final expiresAt = _grants[key];
    if (expiresAt == null) return false;
    if (!_now().isBefore(expiresAt)) {
      _grants.remove(key);
      return false;
    }
    return true;
  }

  @override
  Future<void> grantConsent({
    required String providerId,
    required String resourceKind,
    required List<String> resourceRefs,
    String? purpose,
    Duration? ttl,
  }) async {
    if (providerId.isEmpty || resourceKind.isEmpty) {
      throw const SecretStoreException(
        c.ShadowErrorCode.permInvalidArgument,
        'Egress consent requires a provider and resource kind',
      );
    }
    _grants[_key(providerId, resourceKind, resourceRefs, purpose)] = _now().add(
      ttl ?? defaultTtl,
    );
  }

  @override
  Future<void> revokeAll() async {
    _grants.clear();
  }
}

/// Independent permission enforcement. Policy and approval state live here;
/// model output can never mutate them.
///
/// Every [authorizeToolCall] decision fails closed: unknown tools require
/// approval, shell execution is always HIGH risk, path arguments are validated
/// before execution, and any unexpected error yields a denial.
class PermissionManager implements c.PermissionService {
  PermissionManager({
    PermissionPolicy? policy,
    WorkspaceGuard? workspaceGuard,
    AuditLogger? auditLogger,
    AiEgressConsentManager? egressConsent,
    ShellCommandGuard? shellGuard,
    Duration approvalTtl = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : _policy = policy ?? const PermissionPolicy(),
       _workspaceGuard = workspaceGuard ?? WorkspaceGuard(),
       _audit = auditLogger ?? InMemoryAuditLogger(),
       _egressConsent = egressConsent ?? InMemoryAiEgressConsentManager(),
       _shellGuard = shellGuard ?? const ShellCommandGuard(),
       _approvalTtl = approvalTtl,
       _now = now ?? (() => DateTime.now().toUtc());

  final PermissionPolicy _policy;
  final WorkspaceGuard _workspaceGuard;
  final AuditLogger _audit;
  final AiEgressConsentManager _egressConsent;
  final ShellCommandGuard _shellGuard;
  final Duration _approvalTtl;
  final DateTime Function() _now;

  /// requestId -> pending approval.
  final Map<String, _PendingApproval> _pending = <String, _PendingApproval>{};

  /// Tokens actually minted by this manager. A token that is not registered is
  /// forged and is rejected, regardless of its fields.
  final Map<String, c.ApprovalToken> _issuedTokens =
      <String, c.ApprovalToken>{};

  final Set<String> _usedTokenIds = <String>{};

  /// Create an approval request (to be shown to the user). Never auto-approved.
  ApprovalRequest requestApproval({
    required String toolName,
    required c.ToolRiskLevel riskLevel,
    required Map<String, Object?> arguments,
    required String workspaceRoot,
    String? reason,
    c.ToolRiskLevel? declaredRiskLevel,
  }) {
    final now = _now();
    _purgeExpired(now);
    final hash = hashToolCallBinding(toolName: toolName, arguments: arguments);
    final effectiveRisk = _policy.classify(
      toolName,
      declared: declaredRiskLevel ?? riskLevel,
    );
    final req = ApprovalRequest(
      requestId: newSecurityId('apr'),
      toolName: toolName,
      riskLevel: effectiveRisk,
      arguments: Map<String, Object?>.unmodifiable(
        Map<String, Object?>.from(arguments),
      ),
      argumentsHash: hash,
      workspaceRoot: workspaceRoot,
      requestedAt: now,
      expiresAt: now.add(_approvalTtl),
      reason: reason,
      reasonCode: c.ShadowErrorCode.permApprovalRequired,
    );
    _pending[req.requestId] = _PendingApproval(req);
    unawaited(
      _audit.logSensitive(
        action: 'approval_requested',
        outcome: 'pending',
        details: req.toAudit(),
      ),
    );
    return req;
  }

  /// Mint a single-use token for an explicitly approved request.
  ///
  /// Returns null (and audits the denial) when the request is unknown, expired,
  /// or already granted. A second approval never yields a second token.
  ApprovalToken? approve(String requestId) {
    final pending = _pending[requestId];
    if (pending == null) {
      unawaited(
        _audit.logSensitive(
          action: 'approval_grant',
          outcome: 'denied',
          details: <String, Object?>{
            'request_id': requestId,
            'reason_code': c.ShadowErrorCode.permApprovalInvalid,
          },
        ),
      );
      return null;
    }
    final req = pending.request;
    final now = _now();
    if (req.isExpiredAt(now)) {
      _pending.remove(requestId);
      unawaited(
        _audit.logSensitive(
          action: 'approval_grant',
          outcome: 'denied',
          details: <String, Object?>{
            'request_id': requestId,
            'reason_code': c.ShadowErrorCode.permApprovalTimeout,
          },
        ),
      );
      return null;
    }
    if (pending.grantedToken != null) {
      unawaited(
        _audit.logSensitive(
          action: 'approval_grant',
          outcome: 'denied',
          details: <String, Object?>{
            'request_id': requestId,
            'reason_code': c.ShadowErrorCode.permApprovalInvalid,
            'detail': 'request_already_granted',
          },
        ),
      );
      return null;
    }

    final token = c.ApprovalToken(
      id: newSecurityId('atk'),
      toolName: req.toolName,
      inputHash: req.argumentsHash,
      issuedAt: now,
      expiresAt: req.expiresAt,
      singleUse: true,
    );
    pending.grantedToken = token;
    _issuedTokens[token.id] = token;
    unawaited(
      _audit.logSensitive(
        action: 'approval_grant',
        outcome: 'allowed',
        details: <String, Object?>{
          'request_id': requestId,
          'token_id': token.id,
          'tool': token.toolName,
          'arguments_hash': token.inputHash,
          'expires_at': token.expiresAt.toUtc().toIso8601String(),
        },
      ),
    );
    return token;
  }

  /// Validate an approval token against the exact tool call about to run.
  TokenValidationResult validateToken({
    required c.ApprovalToken token,
    required String toolName,
    required Map<String, Object?> arguments,
  }) {
    if (_usedTokenIds.contains(token.id)) {
      return const TokenValidationResult.reject(
        TokenRejectionReason.replayed,
        c.ShadowErrorCode.permApprovalInvalid,
      );
    }
    if (!_now().isBefore(token.expiresAt.toUtc())) {
      return const TokenValidationResult.reject(
        TokenRejectionReason.expired,
        c.ShadowErrorCode.permApprovalTimeout,
      );
    }
    final registered = _issuedTokens[token.id];
    if (registered == null) {
      return const TokenValidationResult.reject(
        TokenRejectionReason.notIssuedByEngine,
        c.ShadowErrorCode.permApprovalInvalid,
      );
    }
    if (registered.toolName != toolName ||
        registered.inputHash != token.inputHash ||
        registered.expiresAt.toUtc() != token.expiresAt.toUtc()) {
      return const TokenValidationResult.reject(
        TokenRejectionReason.invalidBinding,
        c.ShadowErrorCode.permApprovalInvalid,
      );
    }
    if (token.toolName != toolName) {
      return const TokenValidationResult.reject(
        TokenRejectionReason.invalidBinding,
        c.ShadowErrorCode.permApprovalInvalid,
      );
    }
    final expectedHash = hashToolCallBinding(
      toolName: toolName,
      arguments: arguments,
    );
    if (token.inputHash != expectedHash) {
      return const TokenValidationResult.reject(
        TokenRejectionReason.modifiedArguments,
        c.ShadowErrorCode.permApprovalInvalid,
      );
    }
    if (!token.singleUse) {
      return const TokenValidationResult.reject(
        TokenRejectionReason.invalidBinding,
        c.ShadowErrorCode.permApprovalInvalid,
      );
    }
    return const TokenValidationResult.ok();
  }

  void consumeToken(String tokenId) {
    _usedTokenIds.add(tokenId);
    _issuedTokens.remove(tokenId);
    _pending.removeWhere((_, p) => p.grantedToken?.id == tokenId);
  }

  @override
  Future<c.PermissionDecision> authorizeToolCall({
    required String toolName,
    required c.ToolRiskLevel riskLevel,
    required Map<String, Object?> arguments,
    required String workspaceRoot,
    c.ApprovalToken? approval,
  }) async {
    try {
      final shellExecution = ShellCommandGuard.isShellTool(toolName);
      ShellCommand? shellCommand;
      if (shellExecution) {
        final parsed = ShellCommandGuard.fromToolArguments(arguments);
        final violation = parsed.violation;
        if (violation != null) {
          await _denyAudit(
            toolName,
            violation.code,
            risk: c.ToolRiskLevel.dangerous,
          );
          return c.PermissionDecision.deny(
            reason: violation.message,
            reasonCode: violation.code,
          );
        }
        shellCommand = parsed.command!;
        final shellViolation = _shellGuard.firstViolation(shellCommand);
        if (shellViolation != null) {
          await _denyAudit(
            toolName,
            shellViolation.code,
            risk: c.ToolRiskLevel.dangerous,
          );
          return c.PermissionDecision.deny(
            reason: shellViolation.message,
            reasonCode: shellViolation.code,
          );
        }
        final cwd = shellCommand.workingDirectory;
        if (cwd != null) {
          await _workspaceGuard.ensurePathAllowed(
            path: cwd,
            workspaceRoot: workspaceRoot,
            mustExist: true,
          );
        }
      }

      // Canonical path validation over every path-like argument.
      await _workspaceGuard.validateArgumentsPaths(
        arguments: arguments,
        workspaceRoot: workspaceRoot,
      );

      // Approval validation (forged/expired/replayed tokens denied).
      c.ApprovalToken? validToken;
      if (approval != null) {
        final vr = validateToken(
          token: approval,
          toolName: toolName,
          arguments: arguments,
        );
        if (!vr.ok) {
          await _denyAudit(
            toolName,
            vr.code ?? c.ShadowErrorCode.permApprovalInvalid,
            risk: riskLevel,
            extra: <String, Object?>{'token_id': approval.id},
          );
          return c.PermissionDecision.deny(
            reason: 'Approval token invalid',
            reasonCode: vr.code ?? c.ShadowErrorCode.permApprovalInvalid,
          );
        }
        validToken = approval;
      }

      final insideDefault = await _isInsideWorkspaceRoot(
        workspaceRoot: workspaceRoot,
        arguments: arguments,
      );
      final involvesSpending =
          arguments['declaredAiSpending'] == true ||
          arguments['involvesAiSpending'] == true;
      final effectiveRisk = _policy.classify(toolName, declared: riskLevel);
      final toolKnown = _policy.isKnown(toolName);

      final decision = _policy.evaluate(
        toolName: toolName,
        riskLevel: effectiveRisk,
        arguments: arguments,
        insideDefaultWorkspace: insideDefault,
        hasValidApproval: validToken != null,
        involvesDeclaredSpending: involvesSpending,
        toolKnown: toolKnown,
        shellExecution: shellExecution,
      );

      switch (decision.effect) {
        case PolicyEffect.allow:
          if (validToken != null) consumeToken(validToken.id);
          await _audit.logSensitive(
            action: 'authorize_tool',
            outcome: 'allowed',
            details: <String, Object?>{
              'tool': toolName,
              'risk': effectiveRisk.name,
              'approval_used': validToken != null,
              if (shellExecution) 'shell': true,
              if (shellCommand != null)
                'executable': _basename(shellCommand.executable),
            },
          );
          return const c.PermissionDecision.allow();
        case PolicyEffect.requireApproval:
          await _denyAudit(
            toolName,
            decision.reasonCode ?? c.ShadowErrorCode.permApprovalRequired,
            risk: effectiveRisk,
            extra: <String, Object?>{'requires_approval': true},
          );
          return c.PermissionDecision.requireApproval(
            reason: decision.reason,
            reasonCode:
                decision.reasonCode ?? c.ShadowErrorCode.permApprovalRequired,
          );
        case PolicyEffect.deny:
          await _denyAudit(
            toolName,
            decision.reasonCode ?? c.ShadowErrorCode.permPolicyDenied,
            risk: effectiveRisk,
          );
          return c.PermissionDecision.deny(
            reason: decision.reason,
            reasonCode:
                decision.reasonCode ?? c.ShadowErrorCode.permPolicyDenied,
          );
      }
    } on PathSecurityException catch (e) {
      await _denyAudit(toolName, e.code, risk: riskLevel);
      return c.PermissionDecision.deny(reason: e.message, reasonCode: e.code);
    } catch (_) {
      // Fail closed: if authorization cannot be established, deny.
      await _denyAudit(
        toolName,
        c.ShadowErrorCode.permPolicyDenied,
        risk: riskLevel,
        extra: <String, Object?>{'detail': 'authorization_error'},
      );
      return const c.PermissionDecision.deny(
        reason: 'Authorization could not be established',
        reasonCode: c.ShadowErrorCode.permPolicyDenied,
      );
    }
  }

  /// Direct authorization for an external command outside the tool pipeline.
  ///
  /// The approval token, when used, must be requested with
  /// [shellApprovalArguments] for the same command.
  Future<c.PermissionDecision> authorizeShellCommand({
    required ShellCommand command,
    required String workspaceRoot,
    c.ApprovalToken? approval,
  }) async {
    final args = shellApprovalArguments(command);
    return authorizeToolCall(
      toolName: 'run_command',
      riskLevel: c.ToolRiskLevel.dangerous,
      arguments: args,
      workspaceRoot: workspaceRoot,
      approval: approval,
    );
  }

  /// Canonical argument map used for shell approval binding.
  Map<String, Object?> shellApprovalArguments(ShellCommand command) =>
      <String, Object?>{
        'executable': command.executable,
        'args': command.arguments,
        if (command.workingDirectory != null)
          'workingDirectory': command.workingDirectory,
      };

  @override
  Future<c.PermissionDecision> authorizeEgress(c.EgressRequest request) async {
    final has = await _egressConsent.hasConsent(
      providerId: request.providerId,
      resourceKind: request.resourceKind,
      resourceRefs: request.resourceRefs,
      purpose: request.purpose,
    );
    if (!has) {
      await _audit.logSensitive(
        action: 'ai_egress',
        outcome: 'denied',
        details: <String, Object?>{
          'provider': request.providerId,
          'kind': request.resourceKind,
          'count': request.resourceRefs.length,
          'reason_code': c.ShadowErrorCode.permApprovalRequired,
        },
      );
      return const c.PermissionDecision.requireApproval(
        reason: 'Explicit AI data egress consent required',
        reasonCode: c.ShadowErrorCode.permApprovalRequired,
      );
    }
    await _audit.logSensitive(
      action: 'ai_egress',
      outcome: 'allowed',
      details: <String, Object?>{
        'provider': request.providerId,
        'kind': request.resourceKind,
        'count': request.resourceRefs.length,
      },
    );
    return const c.PermissionDecision.allow();
  }

  @override
  Future<void> validatePath({
    required String path,
    required String workspaceRoot,
    required bool write,
  }) async {
    try {
      await _workspaceGuard.ensurePathAllowed(
        path: path,
        workspaceRoot: workspaceRoot,
      );
    } on PathSecurityException catch (e) {
      await _audit.logSensitive(
        action: 'validate_path',
        outcome: 'denied',
        details: <String, Object?>{'reason_code': e.code, 'write': write},
      );
      throw PathSecurityException(code: e.code, message: e.message);
    }
  }

  Future<bool> _isInsideWorkspaceRoot({
    required String workspaceRoot,
    required Map<String, Object?> arguments,
  }) async {
    final paths = _workspaceGuard.collectPathValues(arguments);
    if (paths.isEmpty) return true;
    const validator = PathValidator();
    for (final path in paths) {
      try {
        await validator.canonicalizeWithinWorkspace(
          targetPath: path,
          workspaceRoot: workspaceRoot,
        );
      } on PathSecurityException {
        return false;
      }
    }
    return true;
  }

  Future<void> _denyAudit(
    String toolName,
    String code, {
    required c.ToolRiskLevel risk,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    return _audit.logSensitive(
      action: 'authorize_tool',
      outcome: 'denied',
      details: <String, Object?>{
        'tool': toolName,
        'risk': risk.name,
        'reason_code': code,
        ...extra,
      },
    );
  }

  void _purgeExpired(DateTime now) {
    _pending.removeWhere((_, p) => p.request.isExpiredAt(now));
    _issuedTokens.removeWhere((_, t) => !now.isBefore(t.expiresAt.toUtc()));
  }

  String _basename(String executable) {
    final normalized = executable.replaceAll(r'\', '/');
    final segments = normalized.split('/');
    return segments.isEmpty ? executable : segments.last;
  }

  /// Cancellation must prevent subsequent tool execution: call before executing
  /// a tool and after any await inside the executor.
  void assertNotCancelled(c.CancellationToken cancel) {
    if (cancel.isCancelled) {
      throw c.CancelledException(reason: cancel.reason);
    }
  }

  /// Revokes every pending request and unused token. There is no permanent
  /// approval mode.
  void clearPendingApprovals() {
    _pending.clear();
    _issuedTokens.clear();
  }

  /// Revokes approval state and egress consent.
  Future<void> revokeAllApprovals() async {
    clearPendingApprovals();
    _usedTokenIds.clear();
    await _egressConsent.revokeAll();
  }

  AiEgressConsentManager get egressConsent => _egressConsent;
}

class _PendingApproval {
  _PendingApproval(this.request);

  final ApprovalRequest request;
  c.ApprovalToken? grantedToken;
}
