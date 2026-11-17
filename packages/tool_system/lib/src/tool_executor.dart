import 'dart:async';
import 'dart:convert';

import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:shadow_permissions/permissions.dart' as perm;

import 'audit_event.dart';
import 'tool_registry.dart';
import 'workspace_path_validator.dart';

const int kMaxToolResultBytes = 256 * 1024;

class ToolExecutor {
  ToolExecutor({
    required ToolRegistry registry,
    required PermissionService permissions,
    ToolSchemaValidator? schemaValidator,
  }) : _registry = registry,
       _permissions = permissions,
       _schemaValidator = schemaValidator ?? const ToolSchemaValidator(),
       _contractValidator = const ToolContractValidator();

  final ToolRegistry _registry;
  final PermissionService _permissions;
  final ToolSchemaValidator _schemaValidator;
  final ToolContractValidator _contractValidator;

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
      final result = fail(
        ShadowErrorCode.toolNotFound,
        'Unknown tool: $toolName',
      );
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
      final validation = _schemaValidator.validate(
        schema: tool.inputSchema,
        arguments: arguments,
      );
      if (!validation.isValid) {
        final result = fail(
          ShadowErrorCode.toolInvalidArgs,
          'Invalid arguments: ${validation.errors.join('; ')}',
        );
        return await _finalize(
          tool,
          context,
          started,
          argsHash,
          result,
          context.revision,
        );
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
        return await _finalize(
          tool,
          context,
          started,
          argsHash,
          result,
          context.revision,
        );
      }

      // 5. validate workspace paths in args and hand the tool canonical paths
      final resolvedArguments = await _validatePathArguments(
        arguments,
        context,
      );

      // 6. execute with cancellation + per-tool timeout
      context.cancel.throwIfCancelled();
      final execFuture = tool.execute(context, resolvedArguments);
      final ToolResult resultRaw;
      try {
        resultRaw = await runWithTimeout<ToolResult>(
          timeout: tool.timeout,
          cancel: context.cancel,
          operation: tool.name,
          body: () => _withCancellation(execFuture, context.cancel),
        );
      } on ShadowTimeoutException catch (e) {
        final timeoutResult = ToolResult.failure(
          code: ShadowErrorCode.toolTimeout,
          message: e.toString(),
          data: <String, Object?>{
            'timeout_ms': tool.timeout.inMilliseconds,
            'tool': tool.name,
          },
        );
        return await _finalize(
          tool,
          context,
          started,
          argsHash,
          timeoutResult,
          context.revision,
        );
      }

      // 7. limit size, then validate against the declared output schema
      final limited = _limitResult(resultRaw);
      // A truncated result is already a terminal, lossy outcome; validating its
      // minimal payload against the full output schema would only mask the
      // truncation with a misleading schema error.
      final validated = limited.truncated
          ? limited
          : _validateOutput(tool, limited);

      // 8. audit (9. return)
      final revAfter = _extractRevision(validated);
      return await _finalize(
        tool,
        context,
        started,
        argsHash,
        validated,
        revAfter ?? context.revision,
      );
    } on CancelledException catch (e) {
      final result = fail(
        ShadowErrorCode.agentCancelled,
        e.reason ?? 'Cancelled',
      );
      return await _finalize(
        tool,
        context,
        started,
        argsHash,
        result,
        context.revision,
      );
    } on ToolPathException catch (e) {
      final result = fail(e.code, e.message);
      return await _finalize(
        tool,
        context,
        started,
        argsHash,
        result,
        context.revision,
      );
    } catch (e) {
      final result = fail(ShadowErrorCode.toolFailed, 'Tool execution failed');
      return await _finalize(
        tool,
        context,
        started,
        argsHash,
        result,
        context.revision,
      );
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

  /// Defense in depth: the permission service already validates paths, but the
  /// executor must not depend on a caller-supplied implementation doing so.
  /// Uses the canonical, deny-by-default argument guard from `permissions` and
  /// passes the returned map (canonical absolute paths) to the tool, so the path
  /// executed is exactly the path validated — never a CWD-relative reinterpretation.
  Future<Map<String, Object?>> _validatePathArguments(
    Map<String, Object?> args,
    ToolContext context,
  ) async {
    try {
      return await perm.WorkspaceGuard().resolveArgumentPaths(
        arguments: args,
        workspaceRoot: context.workspaceRoot,
      );
    } on perm.PathSecurityException catch (e) {
      throw ToolPathException(e.message, code: e.code);
    }
  }

  Future<ToolResult> _withCancellation(
    Future<ToolResult> future,
    CancellationToken cancel,
  ) async {
    if (cancel.isCancelled) throw CancelledException(reason: cancel.reason);
    final completer = Completer<ToolResult>();
    StreamSubscription<void>? sub;
    sub = cancel.onCancel.listen((_) {
      if (!completer.isCompleted) {
        completer.completeError(CancelledException(reason: cancel.reason));
      }
    });
    future.then(
      (v) {
        if (!completer.isCompleted) completer.complete(v);
      },
      onError: (Object e, StackTrace st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      },
    );
    try {
      return await completer.future;
    } finally {
      await sub.cancel();
    }
  }

  ToolResult _validateOutput(AgentTool tool, ToolResult result) {
    final outputErrors = _contractValidator.validateResult(tool, result);
    if (outputErrors.isEmpty) return result;
    return ToolResult.failure(
      code: ShadowErrorCode.toolOutputInvalid,
      message:
          'Tool output does not match outputSchema: ${outputErrors.join('; ')}',
      data: <String, Object?>{'errors': outputErrors},
      artifacts: result.artifacts,
      duration: result.duration,
    );
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
