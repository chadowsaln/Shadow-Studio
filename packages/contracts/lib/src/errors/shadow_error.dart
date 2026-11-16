enum ShadowErrorCategory {
  agent,
  provider,
  tool,
  perm,
  edit,
  media,
  store,
}

/// Unified error contract crossing agent/provider/tool/permission/edit/media/store boundaries.
/// Details must be flat and must not contain secrets or file contents.
class ShadowError implements Exception {
  const ShadowError({
    required this.code,
    required this.category,
    required this.retryable,
    required this.correlationId,
    this.details = const <String, Object?>{},
    this.message,
    this.cause,
  });

  final String code;
  final ShadowErrorCategory category;
  final bool retryable;
  final String correlationId;
  final Map<String, Object?> details;
  final String? message;
  final Object? cause;

  Map<String, Object?> toJson() => <String, Object?>{
        'code': code,
        'category': category.name,
        'retryable': retryable,
        'correlation_id': correlationId,
        'details': details,
        if (message != null) 'message': message,
      };

  @override
  String toString() =>
      'ShadowError(code: $code, category: ${category.name}, retryable: $retryable, correlationId: $correlationId, message: $message)';
}
