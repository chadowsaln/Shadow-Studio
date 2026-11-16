import '../common/cancellation.dart';
import '../permissions/permissions.dart';

enum ToolRiskLevel { safe, restricted, dangerous }

class ToolResult {
  const ToolResult({
    required this.success,
    this.data = const <String, Object?>{},
    this.errorCode,
    this.errorMessage,
    this.truncated = false,
    this.artifacts = const <String, Object?>{},
  });

  final bool success;
  final Map<String, Object?> data;
  final String? errorCode;
  final String? errorMessage;
  final bool truncated;
  final Map<String, Object?> artifacts;

  Map<String, Object?> toJson() => <String, Object?>{
        'success': success,
        'data': data,
        if (errorCode != null) 'error_code': errorCode,
        if (errorMessage != null) 'error_message': errorMessage,
        'truncated': truncated,
        'artifacts': artifacts,
      };
}

abstract interface class AuditSink {
  Future<void> record(Map<String, Object?> event);
}

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

abstract interface class AgentTool {
  String get name;
  String get description;
  ToolRiskLevel get riskLevel;
  bool get idempotent;
  Duration get timeout;
  Map<String, Object?> get inputSchema; // closed JSON-schema subset
  Map<String, Object?> get outputSchema;

  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> arguments,
  );
}
