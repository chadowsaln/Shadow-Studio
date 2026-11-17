import 'dart:async';
import 'dart:convert';

import 'package:shadow_contracts/shadow_contracts.dart';

import 'audit_event.dart';
import 'schema_validator.dart';
import 'tool_registry.dart';
import 'workspace_path_validator.dart';

const int kMaxToolResultBytes = 256 * 1024;

class ToolExecutor {
  ToolExecutor({
    required ToolRegistry registry,
    required PermissionService permissions,
    ToolSchemaValidator? schemaValidator,
    WorkspacePathValidator? pathValidator,
  })  : _registry = registry,
        _permissions = permissions,
        _schemaValidator = schemaValidator ?? const ToolSchemaValidator(),
        _pathValidator = pathValidator ?? const WorkspacePathValidator();

  final ToolRegistry _registry;
  final PermissionService _permissions;
  final ToolSchemaValidator _schemaValidator;
  final WorkspacePathValidator _pathValidator;

  Future<ToolExecutionOutcome> executeCall({
    required String toolName,
    required Map<String, Object?> arguments,
    required ToolContext context,
  }) async {
    final started = DateTime.now().toUtc();
    final argsHash = hashArguments(arguments);

    ToolResult fail(String code, String message, {int? rev}) {
      return ToolResult(success: false, errorCode: code, errorMessage: message);
    }

    // 1-2. resolve
    final tool = _registry.resolve(toolName);
    if (tool == null) {
      final result = fail(ShadowErrorCode.toolNotFound, 'Unknown tool: $toolName');
      final record = ToolExecutionRecord(
        toolName: toolName,
        taskId: context.taskId,
        correlationId: context.correlationId,
        revisionBefore: context.revision,
        revisionAfter: context.revision,
        argumentsHash: argsHash,
        success: false,
        startedAt: started,
        endedAt: DateTime.now().toUtc(),
        errorCode: result.errorCode,
      );
      await context.audit.record(record.toAuditEvent());
      return ToolExecutionOutcome(result: result, record: record);
    }

    try {
      if (context.cancel.isCancelled) {
        throw CancelledException(reason: context.cancel.reason);
      }

      // 3. validate args (closed schema, reject additional properties)
      final validation = _schemaValidator.validate(schema: tool.inputSchema, arguments: arguments);
      if (!validation.isValid) {
        final result = fail(ShadowErrorCode.toolInvalidArgs, 'Invalid arguments: ${validation.errors.join('; ')}');
        return await _finalize(tool, context, started, argsHash, result, context.revision);
      }

      // 4. permissions
      final decision = await _permissions.authorizeToolCall(
        toolName: tool.name,
        riskLevel: tool.riskLevel,
        arguments: arguments,
        workspaceRoot: context.workspaceRoot,
        approval: context.approval,
      );
      if (!decision.allowed) {
        final code = decision.requiresApproval
            ? (decision.reasonCode ?? ShadowErrorCode.permApprovalRequired)
            : (decision.reasonCode ?? ShadowErrorCode.permPathEscape);
        final result = fail(code, decision.reason ?? 'Permission denied');
        return await _finalize(tool, context, started, argsHash, result, context.revision);
      }

      // 5. validate workspace paths in args
      await _validatePathArguments(arguments, context);

      // 6. execute with cancellation
      context.cancel.throwIfCancelled();
      final execFuture = tool.execute(context, arguments);
      final resultRaw = await _withCancellation(execFuture, context.cancel);

      // 7. validate/limit result
      final limited = _limitResult(resultRaw);

      // 8. audit (9. return)
      final revAfter = _extractRevision(limited);
      return await _finalize(tool, context, started, argsHash, limited, revAfter ?? context.revision);
    } on CancelledException catch (e) {
      final result = fail(ShadowErrorCode.agentCancelled, e.reason ?? 'Cancelled');
      return await _finalize(tool, context, started, argsHash, result, context.revision);
    } on ToolPathException catch (e) {
      final result = fail(e.code, e.message);
      return await _finalize(tool, context, started, argsHash, result, context.revision);
    } catch (e) {
      final result = fail(ShadowErrorCode.toolFailed, 'Tool execution failed');
      return await _finalize(tool, context, started, argsHash, result, context.revision);
    }
  }

  Future<ToolExecutionOutcome> _finalize(
    AgentTool tool,
    ToolContext context,
    DateTime started,
    String argsHash,
    ToolResult result,
    int revisionAfter,
  ) async {
    final record = ToolExecutionRecord(
      toolName: tool.name,
      taskId: context.taskId,
      correlationId: context.correlationId,
      revisionBefore: context.revision,
      revisionAfter: revisionAfter,
      argumentsHash: argsHash,
      success: result.success,
      startedAt: started,
      endedAt: DateTime.now().toUtc(),
      errorCode: result.errorCode,
      truncated: result.truncated,
    );
    await context.audit.record(record.toAuditEvent());
    return ToolExecutionOutcome(result: result, record: record);
  }

  Future<void> _validatePathArguments(Map<String, Object?> args, ToolContext context) async {
    const pathKeys = {'path', 'file_path', 'filePath', 'project_path', 'projectPath', 'media_path', 'mediaPath', 'directory', 'dir'};
    for (final entry in args.entries) {
      if (!pathKeys.contains(entry.key)) continue;
      final v = entry.value;
      if (v is String && v.isNotEmpty) {
        await _pathValidator.validateWithinWorkspace(
          candidatePath: v,
          workspaceRoot: context.workspaceRoot,
          mustExist: false,
          resolveSymlinks: true,
        );
      }
    }
  }

  Future<ToolResult> _withCancellation(Future<ToolResult> future, CancellationToken cancel) async {
    if (cancel.isCancelled) throw CancelledException(reason: cancel.reason);
    final completer = Completer<ToolResult>();
    StreamSubscription<void>? sub;
    sub = cancel.onCancel.listen((_) {
      if (!completer.isCompleted) {
        completer.completeError(CancelledException(reason: cancel.reason));
      }
    });
    future.then((v) {
      if (!completer.isCompleted) completer.complete(v);
    }, onError: (Object e, StackTrace st) {
      if (!completer.isCompleted) completer.completeError(e, st);
    });
    try {
      return await completer.future;
    } finally {
      await sub.cancel();
    }
  }

  ToolResult _limitResult(ToolResult result) {
    final bytes = utf8.encode(jsonEncode(result.toJson()));
    if (bytes.length <= kMaxToolResultBytes) return result;
    // truncate data payload deterministically
    final minimal = <String, Object?>{
      'truncated': true,
      'original_bytes': bytes.length,
      'limit_bytes': kMaxToolResultBytes,
    };
    return ToolResult(
      success: result.success,
      data: minimal,
      errorCode: result.errorCode,
      errorMessage: result.errorMessage,
      truncated: true,
      artifacts: const <String, Object?>{},
    );
  }

  int? _extractRevision(ToolResult result) {
    final v = result.data['revision'];
    if (v is int) return v;
    return null;
  }
}

class ToolExecutionOutcome {
  const ToolExecutionOutcome({required this.result, required this.record});
  final ToolResult result;
  final ToolExecutionRecord record;
}
