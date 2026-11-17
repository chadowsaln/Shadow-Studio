import 'package:meta/meta.dart';
import 'package:shadow_contracts/shadow_contracts.dart' as contracts;

/// Engine-managed approval token (single-use, bound to exact tool call + args hash).
@immutable
class ApprovalToken {
  const ApprovalToken({
    required this.id,
    required this.toolName,
    required this.inputHash,
    required this.issuedAt,
    required this.expiresAt,
    this.singleUse = true,
  });

  final String id;
  final String toolName;
  final String inputHash;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final bool singleUse;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt.toUtc());

  contracts.ApprovalToken toContractToken() => contracts.ApprovalToken(
        id: id,
        toolName: toolName,
        inputHash: inputHash,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
        singleUse: singleUse,
      );

  static ApprovalToken fromContract(contracts.ApprovalToken token) => ApprovalToken(
        id: token.id,
        toolName: token.toolName,
        inputHash: token.inputHash,
        issuedAt: token.issuedAt,
        expiresAt: token.expiresAt,
        singleUse: token.singleUse,
      );
}

enum TokenRejectionReason {
  missing,
  invalidBinding,
  modifiedArguments,
  expired,
  timeout,
  replayed,
  alreadyUsed,
}

class TokenValidationResult {
  const TokenValidationResult.ok() : ok = true, reason = null, code = null;
  const TokenValidationResult.reject(this.reason, this.code) : ok = false;

  final bool ok;
  final TokenRejectionReason? reason;
  final String? code;
}
