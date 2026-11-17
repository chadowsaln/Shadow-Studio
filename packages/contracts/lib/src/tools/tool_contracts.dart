import '../common/cancellation.dart';
import '../errors/error_codes.dart';
import '../errors/shadow_error.dart';
import '../permissions/permissions.dart';
import 'schema_validator.dart';

/// Risk classification for a tool call (Spec V2-D8: three classes).
enum ToolRiskLevel { safe, restricted, dangerous }

/// Terminal or in-flight state of a tool execution.
enum ToolExecutionStatus {
  pending,
  running,
  succeeded,
  failed,
  cancelled,
  timedOut,
  denied,
}

ToolExecutionStatus _statusFromJson(Object? value) {
  if (value is String) {
    for (final s in ToolExecutionStatus.values) {
      if (s.name == value) return s;
    }
  }
  return ToolExecutionStatus.failed;
}

/// Structured outcome of a single tool invocation.
class ToolResult {
  const ToolResult({
    required this.success,
    this.data = const <String, Object?>{},
    this.errorCode,
    this.errorMessage,
    this.truncated = false,
    this.artifacts = const <String, Object?>{},
    this.duration,
  });

  const ToolResult.ok({
    this.data = const <String, Object?>{},
    this.artifacts = const <String, Object?>{},
    this.duration,
  }) : success = true,
       errorCode = null,
       errorMessage = null,
       truncated = false;

  const ToolResult.failure({
    required String code,
    required String message,
    this.data = const <String, Object?>{},
    this.artifacts = const <String, Object?>{},
    this.duration,
  }) : success = false,
       errorCode = code,
       errorMessage = message,
       truncated = false;

  /// Builds a failure result from a structured [ShadowError].
  factory ToolResult.fromError(
    ShadowError error, {
    Map<String, Object?> data = const <String, Object?>{},
    Duration? duration,
  }) {
    return ToolResult(
      success: false,
      data: data,
      errorCode: error.code,
      errorMessage: error.message ?? error.code,
      duration: duration,
      artifacts: <String, Object?>{'correlation_id': error.correlationId},
    );
  }

  final bool success;
  final Map<String, Object?> data;
  final String? errorCode;
  final String? errorMessage;
  final bool truncated;
  final Map<String, Object?> artifacts;
  final Duration? duration;

  ToolExecutionStatus get status {
    if (success) return ToolExecutionStatus.succeeded;
    if (errorCode == ShadowErrorCode.toolTimeout) {
      return ToolExecutionStatus.timedOut;
    }
    if (errorCode == ShadowErrorCode.agentCancelled) {
      return ToolExecutionStatus.cancelled;
    }
    if (errorCode == ShadowErrorCode.permApprovalRequired ||
        errorCode == ShadowErrorCode.permApprovalInvalid ||
        errorCode == ShadowErrorCode.permApprovalTimeout) {
      return ToolExecutionStatus.denied;
    }
    return ToolExecutionStatus.failed;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'success': success,
    'status': status.name,
    'data': data,
    if (errorCode != null) 'error_code': errorCode,
    if (errorMessage != null) 'error_message': errorMessage,
    'truncated': truncated,
    'artifacts': artifacts,
    if (duration != null) 'duration_ms': duration!.inMilliseconds,
  };

  static ToolResult fromJson(Map<String, Object?> json) {
    return ToolResult(
      success: json['success'] as bool? ?? false,
      data:
          (json['data'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{},
      errorCode: json['error_code'] as String?,
      errorMessage: json['error_message'] as String?,
      truncated: json['truncated'] as bool? ?? false,
      artifacts:
          (json['artifacts'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{},
      duration: json['duration_ms'] is int
          ? Duration(milliseconds: json['duration_ms'] as int)
          : null,
    );
  }
}

/// Execution metadata attached to audit records and checkpoints.
class ToolExecutionMetadata {
  const ToolExecutionMetadata({
    required this.toolName,
    required this.taskId,
    required this.correlationId,
    required this.attempt,
    required this.status,
    required this.startedAt,
    this.finishedAt,
    this.duration,
    this.truncated = false,
    this.resultBytes,
    this.errorCode,
    this.errorMessage,
    this.retryable = false,
  });

  final String toolName;
  final String taskId;
  final String correlationId;
  final int attempt;
  final ToolExecutionStatus status;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final Duration? duration;
  final bool truncated;
  final int? resultBytes;
  final String? errorCode;
  final String? errorMessage;
  final bool retryable;

  bool get isTerminal =>
      status == ToolExecutionStatus.succeeded ||
      status == ToolExecutionStatus.failed ||
      status == ToolExecutionStatus.cancelled ||
      status == ToolExecutionStatus.timedOut ||
      status == ToolExecutionStatus.denied;

  Map<String, Object?> toJson() => <String, Object?>{
    'tool': toolName,
    'task_id': taskId,
    'correlation_id': correlationId,
    'attempt': attempt,
    'status': status.name,
    'started_at': startedAt.toUtc().toIso8601String(),
    if (finishedAt != null)
      'finished_at': finishedAt!.toUtc().toIso8601String(),
    if (duration != null) 'duration_ms': duration!.inMilliseconds,
    'truncated': truncated,
    if (resultBytes != null) 'result_bytes': resultBytes,
    if (errorCode != null) 'error_code': errorCode,
    if (errorMessage != null) 'error_message': errorMessage,
    'retryable': retryable,
  };

  static ToolExecutionMetadata fromJson(Map<String, Object?> json) {
    return ToolExecutionMetadata(
      toolName: json['tool'] as String? ?? '',
      taskId: json['task_id'] as String? ?? '',
      correlationId: json['correlation_id'] as String? ?? '',
      attempt: json['attempt'] as int? ?? 1,
      status: _statusFromJson(json['status']),
      startedAt: DateTime.parse(json['started_at'] as String).toUtc(),
      finishedAt: json['finished_at'] == null
          ? null
          : DateTime.parse(json['finished_at'] as String).toUtc(),
      duration: json['duration_ms'] is int
          ? Duration(milliseconds: json['duration_ms'] as int)
          : null,
      truncated: json['truncated'] as bool? ?? false,
      resultBytes: json['result_bytes'] as int?,
      errorCode: json['error_code'] as String?,
      errorMessage: json['error_message'] as String?,
      retryable: json['retryable'] as bool? ?? false,
    );
  }
}

abstract interface class AuditSink {
  Future<void> record(Map<String, Object?> event);
}

/// Per-call execution context passed to every tool.
class ToolContext {
  const ToolContext({
    required this.taskId,
    required this.correlationId,
    required this.revision,
    required this.workspaceRoot,
    required this.cancel,
    required this.audit,
    this.approval,
  });

  final String taskId;
  final String correlationId;
  final int revision;
  final String workspaceRoot;
  final CancellationToken cancel;
  final AuditSink audit;
  final ApprovalToken? approval;
}

/// Executable tool contract.
///
/// [inputSchema] and [outputSchema] use the closed JSON-schema subset validated
/// by [ToolSchemaValidator]. Both schemas must declare `additionalProperties:
/// false` at the root.
abstract interface class AgentTool {
  String get name;
  String get description;
  ToolRiskLevel get riskLevel;
  bool get idempotent;
  Duration get timeout;
  Map<String, Object?> get inputSchema;
  Map<String, Object?> get outputSchema;

  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> arguments,
  );
}

/// Validates tool definitions and results against the executable contract.
class ToolContractValidator {
  const ToolContractValidator();

  static final RegExp _namePattern = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
  static const int _maxDescriptionLength = 500;
  static const Duration _maxTimeout = Duration(minutes: 10);

  /// Returns a list of contract violations. Empty means valid.
  List<String> validateDefinition(AgentTool tool) {
    final errors = <String>[];
    if (!_namePattern.hasMatch(tool.name)) {
      errors.add('name "${tool.name}" must match ${_namePattern.pattern}');
    }
    if (tool.description.trim().isEmpty) {
      errors.add('description must not be empty');
    } else if (tool.description.length > _maxDescriptionLength) {
      errors.add('description exceeds $_maxDescriptionLength characters');
    }
    if (tool.timeout <= Duration.zero || tool.timeout > _maxTimeout) {
      errors.add('timeout must be in (0, ${_maxTimeout.inMilliseconds}ms]');
    }
    _validateRootObjectSchema('inputSchema', tool.inputSchema, errors);
    _validateRootObjectSchema('outputSchema', tool.outputSchema, errors);
    return errors;
  }

  /// Validates [result] against the tool's [outputSchema].
  ///
  /// Failure results require an error code. Successful results are validated
  /// structurally; truncated results are accepted but flagged.
  List<String> validateResult(AgentTool tool, ToolResult result) {
    final errors = <String>[];
    if (!result.success) {
      if (result.errorCode == null || result.errorCode!.isEmpty) {
        errors.add('failed result requires error_code');
      }
      if (result.errorMessage == null || result.errorMessage!.isEmpty) {
        errors.add('failed result requires error_message');
      }
      return errors;
    }
    if (result.data.isEmpty && tool.outputSchema.isNotEmpty) {
      // An empty data map is allowed when the schema has no required fields.
      final required = (tool.outputSchema['required'] as List?) ?? const [];
      if (required.isNotEmpty) {
        errors.add('successful result requires data');
      }
    }
    final validation = const ToolSchemaValidator().validate(
      schema: tool.outputSchema,
      arguments: result.data,
    );
    if (!validation.isValid) {
      errors.addAll(validation.errors.map((e) => 'output: $e'));
    }
    return errors;
  }

  void _validateRootObjectSchema(
    String label,
    Map<String, Object?> schema,
    List<String> errors,
  ) {
    if (schema.isEmpty) {
      errors.add('$label must not be empty');
      return;
    }
    if (schema['type'] != 'object') {
      errors.add('$label.type must be "object"');
    }
    if (schema['additionalProperties'] != false) {
      errors.add('$label.additionalProperties must be false');
    }
    final props = schema['properties'];
    if (props is! Map) {
      errors.add('$label.properties must be an object');
    }
  }
}
