import 'dart:async';

import 'package:shadow_contracts/shadow_contracts.dart';

import '../agent_controller.dart';
import '../agent_events.dart';
import 'agent_message.dart';
import 'agent_role.dart';

/// Wraps one [AgentController] as a role-scoped worker.
///
/// A specialized agent never invents its own tools: it runs the shared runtime
/// loop, and the [ToolCallExecutor] it is given (optionally wrapped in a
/// [RoleToolFilter]) decides which tools the role may touch.
class SpecializedAgent {
  SpecializedAgent({
    required this.role,
    required AgentController Function() controllerFactory,
  }) : _controllerFactory = controllerFactory;

  final AgentRole role;
  final AgentController Function() _controllerFactory;
  AgentController? _controller;

  AgentController get controller => _controller ??= _controllerFactory();

  /// Executes [request] as a sub-task for this role and resolves with the
  /// terminal managed state. The controller emits its events for the UI; this
  /// method only waits for the terminal transition.
  Future<ManagedTask> run({
    required String request,
    required String workspaceRoot,
    required int projectRevision,
    AgentMessage? inbound,
  }) async {
    final effectiveRequest = inbound == null
        ? request
        : '$request\n\n[inbound ${inbound.from.id} -> ${role.id}] '
              '${inbound.type.wireName}: ${inbound.content}';

    final completer = Completer<ManagedTask>();
    late final StreamSubscription<Object> subscription;
    subscription = controller.events.listen((event) {
      if (event.taskId != _pendingTaskId) return;
      if (event is TaskCompleted) {
        if (!completer.isCompleted) completer.complete(_snapshot());
      } else if (event is TaskFailed) {
        if (!completer.isCompleted) completer.complete(_snapshot());
      } else if (event is TaskCancelled) {
        if (!completer.isCompleted) completer.complete(_snapshot());
      }
    });

    final managed = controller.createTask(
      request: effectiveRequest,
      workspaceRoot: workspaceRoot,
      projectRevision: projectRevision,
    );
    _pendingTaskId = managed.id;

    try {
      return await completer.future;
    } finally {
      await subscription.cancel();
    }
  }

  String? _pendingTaskId;

  ManagedTask _snapshot() {
    final task = controller.task(_pendingTaskId ?? '');
    if (task == null) {
      throw StateError('Specialized agent task disappeared before completion');
    }
    return task;
  }

  Future<void> dispose() => controller.dispose();
}

/// Hides every tool not explicitly allowed for a role.
///
/// Denied tools resolve to `null`, so the execution loop reports
/// `TOOL_NOT_FOUND` instead of ever dispatching them; the permission layer
/// still runs for the tools that do resolve.
class RoleToolFilter implements ToolCallExecutor {
  RoleToolFilter({required this.delegate, required this.allowedTools});

  final ToolCallExecutor delegate;
  final Set<String> allowedTools;

  @override
  AgentTool? resolve(String name) {
    if (!allowedTools.contains(name)) return null;
    return delegate.resolve(name);
  }

  @override
  Future<ToolResult> execute({
    required AIToolCall call,
    required ToolContext context,
    required AgentTool tool,
  }) {
    if (!allowedTools.contains(call.name)) {
      return Future<ToolResult>.value(
        ToolResult(
          success: false,
          errorCode: ShadowErrorCode.toolNotFound,
          errorMessage: 'Tool "${call.name}" is not allowed for this role',
        ),
      );
    }
    return delegate.execute(call: call, context: context, tool: tool);
  }
}
