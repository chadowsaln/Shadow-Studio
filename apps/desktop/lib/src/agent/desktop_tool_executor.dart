import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:shadow_tool_system/tool_system.dart';

/// Adapts the tool-system execution pipeline to the agent runtime port.
///
/// Every call still goes through schema validation, permission checks, path
/// confinement, cancellation, audit, and output validation in [ToolExecutor].
class DesktopToolExecutor implements ToolCallExecutor {
  DesktopToolExecutor({
    required ToolRegistry registry,
    required ToolExecutor executor,
  })  : _registry = registry,
        _executor = executor;

  final ToolRegistry _registry;
  final ToolExecutor _executor;

  @override
  AgentTool? resolve(String name) => _registry.resolve(name);

  @override
  Future<ToolResult> execute({
    required AIToolCall call,
    required ToolContext context,
    required AgentTool tool,
  }) async {
    final outcome = await _executor.executeCall(
      toolName: tool.name,
      arguments: call.arguments,
      context: context,
    );
    return outcome.result;
  }
}
