import 'package:meta/meta.dart';

/// Unified storage error representation for local_storage (Spec §13 & §14.3).
@immutable
class StorageError implements Exception {
  final String code;
  final String category;
  final bool retryable;
  final String? correlationId;
  final Map<String, Object?> details;
  final String? message;

  const StorageError({
    required this.code,
    required this.category,
    required this.retryable,
    this.correlationId,
    this.details = const {},
    this.message,
  });

  /// Factory for STORE_CORRUPT (Spec §14.3, retryable: false).
  factory StorageError.corrupt(
    String message, {
    String? path,
    Map<String, Object?> details = const {},
    String? correlationId,
  }) {
    return StorageError(
      code: 'STORE_CORRUPT',
      category: 'store',
      retryable: false,
      correlationId: correlationId,
      details: {
        if (path != null) 'path': path,
        ...details,
      },
      message: message,
    );
  }

  /// Factory for STORE_DISK_FULL (Spec §14.3, retryable: false).
  factory StorageError.diskFull(
    String message, {
    String? path,
    Map<String, Object?> details = const {},
    String? correlationId,
  }) {
    return StorageError(
      code: 'STORE_DISK_FULL',
      category: 'store',
      retryable: false,
      correlationId: correlationId,
      details: {
        if (path != null) 'path': path,
        ...details,
      },
      message: message,
    );
  }

  /// Factory for unsupported newer schema versions.
  factory StorageError.schemaTooNew({
    required int fileVersion,
    required int maxSupportedVersion,
    String? path,
    String? correlationId,
  }) {
    return StorageError(
      code: 'STORE_CORRUPT',
      category: 'store',
      retryable: false,
      correlationId: correlationId,
      details: {
        if (path != null) 'path': path,
        'file_version': fileVersion,
        'max_supported_version': maxSupportedVersion,
      },
      message:
          'Project file schema version $fileVersion is newer than max supported version $maxSupportedVersion',
    );
  }

  @override
  String toString() =>
      'StorageError(code: $code, category: $category, retryable: $retryable, message: $message, details: $details)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StorageError &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          category == other.category &&
          retryable == other.retryable &&
          message == other.message;

  @override
  int get hashCode => Object.hash(code, category, retryable, message);
}
