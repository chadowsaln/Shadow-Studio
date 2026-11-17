import 'package:shadow_contracts/shadow_contracts.dart' as contracts;

/// Single approval-token type, owned by the contracts package.
///
/// The permissions package deliberately does not define its own token: a
/// duplicate type would let a security field be added on one side and silently
/// dropped on the other. Engine-minted tokens are always registered with the
/// issuing [PermissionManager]; possession of a token alone is never enough.
typedef ApprovalToken = contracts.ApprovalToken;

/// Why an approval token was rejected.
enum TokenRejectionReason {
  missing,
  invalidBinding,
  modifiedArguments,
  expired,
  timeout,
  replayed,
  alreadyUsed,
  notIssuedByEngine,
}

/// Result of validating an approval token against a concrete tool call.
class TokenValidationResult {
  const TokenValidationResult.ok() : ok = true, reason = null, code = null;

  const TokenValidationResult.reject(this.reason, this.code) : ok = false;

  final bool ok;
  final TokenRejectionReason? reason;
  final String? code;
}
