import 'package:meta/meta.dart';

/// Unified error representation for media operations (Spec §13 & §14.3).
///
/// Standard format: MediaException { code, category, retryable, correlationId, details, message }
@immutable
class MediaException implements Exception {
  /// Machine-readable error code (e.g. MEDIA_ASSET_MISSING, MEDIA_UNSUPPORTED, etc.).
  final String code;

  /// Error category (always 'media' per Spec §14.3).
  final String category;

  /// Whether the caller may retry the operation.
  final bool retryable;

  /// Optional correlation identifier for distributed tracing / observability.
  final String? correlationId;

  /// Flat metadata details (no sensitive secrets).
  final Map<String, Object?> details;

  /// Human-readable diagnostic message.
  final String message;

  const MediaException({
    required this.code,
    this.category = 'media',
    required this.retryable,
    this.correlationId,
    this.details = const {},
    required this.message,
  });

  /// Factory for MEDIA_ASSET_MISSING (retryable: false per Spec §14.3).
  factory MediaException.assetMissing(
    String path, {
    String? correlationId,
    String? customMessage,
  }) {
    return MediaException(
      code: 'MEDIA_ASSET_MISSING',
      category: 'media',
      retryable: false,
      correlationId: correlationId,
      details: {'path': path},
      message: customMessage ?? 'Media asset not found at path: $path',
    );
  }

  /// Factory for MEDIA_UNSUPPORTED (retryable: false per Spec §14.3).
  factory MediaException.unsupported(
    String reason, {
    String? path,
    String? codec,
    String? container,
    String? correlationId,
  }) {
    return MediaException(
      code: 'MEDIA_UNSUPPORTED',
      category: 'media',
      retryable: false,
      correlationId: correlationId,
      details: {
        if (path != null) 'path': path,
        if (codec != null) 'codec': codec,
        if (container != null) 'container': container,
        'reason': reason,
      },
      message: 'Unsupported media format: $reason',
    );
  }

  /// Factory for MEDIA_CORRUPT (retryable: false per Spec §14.3).
  factory MediaException.corrupt(
    String reason, {
    String? path,
    String? correlationId,
  }) {
    return MediaException(
      code: 'MEDIA_CORRUPT',
      category: 'media',
      retryable: false,
      correlationId: correlationId,
      details: {
        if (path != null) 'path': path,
        'reason': reason,
      },
      message: 'Corrupted media file: $reason',
    );
  }

  /// Factory for MEDIA_ENGINE_CRASH (retryable: true per Spec §14.3).
  factory MediaException.engineCrash(
    String detailsMessage, {
    int? exitCode,
    String? correlationId,
  }) {
    return MediaException(
      code: 'MEDIA_ENGINE_CRASH',
      category: 'media',
      retryable: true,
      correlationId: correlationId,
      details: {
        if (exitCode != null) 'exit_code': exitCode,
        'details': detailsMessage,
      },
      message: 'Media engine worker crashed unexpectedly: $detailsMessage',
    );
  }

  /// Factory for MEDIA_WORKER_UNAVAILABLE (retryable: true per Spec §14.3).
  factory MediaException.workerUnavailable(
    String reason, {
    String? correlationId,
  }) {
    return MediaException(
      code: 'MEDIA_WORKER_UNAVAILABLE',
      category: 'media',
      retryable: true,
      correlationId: correlationId,
      details: {'reason': reason},
      message: 'Media worker is unavailable: $reason',
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer('MediaException(')
      ..write('code: $code')
      ..write(', category: $category')
      ..write(', retryable: $retryable')
      ..write(', message: $message');
    if (correlationId != null) buffer.write(', correlationId: $correlationId');
    if (details.isNotEmpty) buffer.write(', details: $details');
    buffer.write(')');
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaException &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          category == other.category &&
          retryable == other.retryable &&
          correlationId == other.correlationId &&
          message == other.message;

  @override
  int get hashCode => Object.hash(code, category, retryable, correlationId, message);
}
