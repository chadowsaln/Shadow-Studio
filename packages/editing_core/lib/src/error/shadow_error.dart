import 'package:meta/meta.dart';

/// Unified error representation across all Shadow Studio boundaries (Spec §13 & §14.2/§14.3).
///
/// Standard format: ShadowError { code, category, retryable, correlationId, details }
@immutable
class ShadowError implements Exception {
  /// Machine-readable error code (e.g. EDIT_REVISION_MISMATCH, EDIT_INVALID_OPERATION).
  final String code;

  /// Error category (agent | provider | tool | perm | edit | media | store).
  final String category;

  /// Whether the caller may retry the operation with adjusted parameters.
  final bool retryable;

  /// Optional correlation identifier for distributed tracing / observability.
  final String? correlationId;

  /// Flat metadata details (no sensitive secrets).
  final Map<String, Object?> details;

  /// Human-readable diagnostic message.
  final String? message;

  const ShadowError({
    required this.code,
    required this.category,
    required this.retryable,
    this.correlationId,
    this.details = const {},
    this.message,
  });

  /// Factory for EDIT_REVISION_MISMATCH (retryable: true per Spec §14.3).
  factory ShadowError.revisionMismatch({
    required int expected,
    required int actual,
    String? correlationId,
  }) {
    return ShadowError(
      code: 'EDIT_REVISION_MISMATCH',
      category: 'edit',
      retryable: true,
      correlationId: correlationId,
      details: {
        'expected_revision': expected,
        'actual_revision': actual,
      },
      message: 'Revision mismatch: expected $expected but current is $actual',
    );
  }

  /// Factory for EDIT_INVALID_OPERATION (retryable: false per Spec §14.3).
  factory ShadowError.invalidOperation(
    String message, {
    Map<String, Object?> details = const {},
    String? correlationId,
  }) {
    return ShadowError(
      code: 'EDIT_INVALID_OPERATION',
      category: 'edit',
      retryable: false,
      correlationId: correlationId,
      details: details,
      message: message,
    );
  }

  /// Factory for MEDIA_ASSET_MISSING (retryable: false per Spec §14.3).
  factory ShadowError.assetMissing(
    String assetId, {
    String? correlationId,
  }) {
    return ShadowError(
      code: 'MEDIA_ASSET_MISSING',
      category: 'media',
      retryable: false,
      correlationId: correlationId,
      details: {'asset_id': assetId},
      message: 'Referenced asset $assetId not found in project document',
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer('ShadowError(')
      ..write('code: $code')
      ..write(', category: $category')
      ..write(', retryable: $retryable');
    if (message != null) buffer.write(', message: $message');
    if (correlationId != null) buffer.write(', correlationId: $correlationId');
    if (details.isNotEmpty) buffer.write(', details: $details');
    buffer.write(')');
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShadowError &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          category == other.category &&
          retryable == other.retryable &&
          correlationId == other.correlationId &&
          message == other.message;

  @override
  int get hashCode => Object.hash(code, category, retryable, correlationId, message);
}
