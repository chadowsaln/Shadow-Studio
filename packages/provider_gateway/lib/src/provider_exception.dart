import 'package:shadow_contracts/shadow_contracts.dart';

/// Normalized provider/gateway error. Never contains secrets.
class ProviderGatewayException implements Exception {
  const ProviderGatewayException({
    required this.code,
    required this.message,
    required this.retryable,
    this.statusCode,
    this.providerId,
    this.details = const <String, Object?>{},
  });

  final String code; // ShadowErrorCode.provider*
  final String message;
  final bool retryable;
  final int? statusCode;
  final String? providerId;
  final Map<String, Object?> details;

  bool get isAuth => code == ShadowErrorCode.providerAuth || statusCode == 401 || statusCode == 403;
  bool get isRateLimitOrServer => statusCode == 429 || (statusCode != null && statusCode! >= 500);

  @override
  String toString() => 'ProviderGatewayException($code, provider=$providerId, status=$statusCode, retryable=$retryable)';
}

class ProviderTimeoutException extends ProviderGatewayException {
  const ProviderTimeoutException({String? providerId, Duration? timeout})
      : super(
          code: ShadowErrorCode.providerRateLimit,
          message: 'Provider request timed out',
          retryable: true,
          providerId: providerId,
          details: timeout == null ? const {} : {'timeout_ms': timeout.inMilliseconds},
        );
}

class ProviderCancelledException extends ProviderGatewayException {
  const ProviderCancelledException({String? providerId, String? reason})
      : super(
          code: ShadowErrorCode.agentCancelled,
          message: 'Provider request cancelled',
          retryable: false,
          providerId: providerId,
          details: reason == null ? const {} : {'reason': reason},
        );
}

class BudgetExceededException extends ProviderGatewayException {
  const BudgetExceededException({required String message, Map<String, Object?> details = const {}})
      : super(
          code: ShadowErrorCode.providerBudgetExceeded,
          message: message,
          retryable: false,
          details: details,
        );
}

class EgressConsentRequiredException extends ProviderGatewayException {
  const EgressConsentRequiredException({required this.resourceRefs, this.purpose})
      : super(
          code: ShadowErrorCode.permApprovalRequired,
          message: 'Explicit user consent required before sending media/file content to cloud AI provider',
          retryable: false,
          details: const {'kind': 'egress_consent'},
        );
  final List<String> resourceRefs;
  final String? purpose;
}
