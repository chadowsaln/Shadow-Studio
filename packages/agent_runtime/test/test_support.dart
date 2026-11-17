import 'package:shadow_agent_runtime/agent_runtime.dart';
import 'package:shadow_contracts/shadow_contracts.dart';

class FakeTool implements AgentTool {
  FakeTool({
    required this.name,
    this.riskLevel = ToolRiskLevel.safe,
    this.idempotent = true,
    this.timeout = const Duration(seconds: 5),
    this.inputSchema = const <String, Object?>{'type': 'object', 'additionalProperties': false},
    this.outputSchema = const <String, Object?>{'type': 'object'},
    Future<ToolResult> Function(ToolContext ctx, Map<String, Object?> args)? handler,
  }) : _handler = handler;

  @override
  final String name;
  @override
  String get description => 'fake $name';
  @override
  final ToolRiskLevel riskLevel;
  @override
  final bool idempotent;
  @override
  final Duration timeout;
  @override
  final Map<String, Object?> inputSchema;
  @override
  final Map<String, Object?> outputSchema;
  final Future<ToolResult> Function(ToolContext ctx, Map<String, Object?> args)? _handler;

  int calls = 0;
  List<Map<String, Object?>> receivedArgs = <Map<String, Object?>>[];

  @override
  Future<ToolResult> execute(ToolContext context, Map<String, Object?> arguments) async {
    calls++;
    receivedArgs.add(arguments);
    final h = _handler;
    if (h != null) return h(context, arguments);
    return ToolResult(success: true, data: <String, Object?>{'ok': true, 'name': name, 'args': arguments});
  }
}

class FakeToolExecutor implements ToolCallExecutor {
  FakeToolExecutor([List<AgentTool> tools = const []]) {
    for (final t in tools) register(t);
  }
  final Map<String, AgentTool> _tools = <String, AgentTool>{};
  void register(AgentTool tool) => _tools[tool.name] = tool;

  @override
  AgentTool? resolve(String name) => _tools[name];

  @override
  Future<ToolResult> execute({
    required AIToolCall call,
    required ToolContext context,
    required AgentTool tool,
  }) {
    return tool.execute(context, call.arguments);
  }
}

class MemoryAuditSink implements AuditSink {
  final List<Map<String, Object?>> events = <Map<String, Object?>>[];
  @override
  Future<void> record(Map<String, Object?> event) async {
    events.add(event);
  }
}

class GrantAllApprovalGate implements ApprovalGate {
  GrantAllApprovalGate({this.tokenPrefix = 'tok'});
  final String tokenPrefix;
  int count = 0;
  @override
  Future<ApprovalToken?> requestApproval({
    required String taskId,
    required String callId,
    required AgentTool tool,
    required Map<String, Object?> arguments,
  }) async {
    count++;
    return ApprovalToken(
      id: '${tokenPrefix}_$count',
      toolName: tool.name,
      inputHash: callId,
      issuedAt: DateTime.now().toUtc(),
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      singleUse: true,
    );
  }
}

class DenyApprovalGate implements ApprovalGate {
  @override
  Future<ApprovalToken?> requestApproval({
    required String taskId,
    required String callId,
    required AgentTool tool,
    required Map<String, Object?> arguments,
  }) async => null;
}
