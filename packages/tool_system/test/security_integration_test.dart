import 'dart:io';

import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:shadow_permissions/permissions.dart' as perm;
import 'package:shadow_tool_system/tool_system.dart';
import 'package:test/test.dart';

class _ExecutableTool implements AgentTool {
  _ExecutableTool({
    required this.name,
    required this.riskLevel,
    required this.inputSchema,
    required this.outputSchema,
  });

  @override
  final String name;
  @override
  String get description => 'test tool';
  @override
  final ToolRiskLevel riskLevel;
  @override
  bool get idempotent => false;
  @override
  Duration get timeout => const Duration(seconds: 5);
  @override
  final Map<String, Object?> inputSchema;
  @override
  final Map<String, Object?> outputSchema;

  int executions = 0;
  Map<String, Object?>? lastArguments;

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> arguments,
  ) async {
    executions++;
    lastArguments = arguments;
    return const ToolResult.ok(data: <String, Object?>{'done': true});
  }
}

const _pathSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'path': <String, Object?>{'type': 'string'},
  },
  'required': <String>['path'],
  'additionalProperties': false,
};

const _okSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'done': <String, Object?>{'type': 'boolean'},
  },
  'additionalProperties': false,
};

class RecordingAuditSink implements AuditSink {
  final List<Map<String, Object?>> events = <Map<String, Object?>>[];

  @override
  Future<void> record(Map<String, Object?> event) async {
    events.add(event);
  }
}

void main() {
  late Directory root;
  late perm.PermissionManager permissions;
  late perm.InMemoryAuditLogger securityAudit;
  late RecordingAuditSink toolAudit;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('perm_tool_int_');
    securityAudit = perm.InMemoryAuditLogger();
    permissions = perm.PermissionManager(auditLogger: securityAudit);
    toolAudit = RecordingAuditSink();
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  ToolContext context({ApprovalToken? approval}) => ToolContext(
    taskId: 'task-1',
    correlationId: 'corr-1',
    revision: 0,
    workspaceRoot: root.path,
    cancel: CancellationToken(),
    audit: toolAudit,
    approval: approval,
  );

  test('destructive tool does not execute without an approval token', () async {
    final tool = _ExecutableTool(
      name: 'delete_file',
      riskLevel: ToolRiskLevel.safe, // attempts to downscope
      inputSchema: _pathSchema,
      outputSchema: _okSchema,
    );
    final executor = ToolExecutor(
      registry: ToolRegistry()..register(tool),
      permissions: permissions,
    );

    final outcome = await executor.executeCall(
      toolName: 'delete_file',
      arguments: {'path': '${root.path}/clip.mp4'},
      context: context(),
    );

    expect(outcome.result.success, isFalse);
    expect(outcome.result.errorCode, ShadowErrorCode.permApprovalRequired);
    expect(tool.executions, 0);
    expect(outcome.record.success, isFalse);
  });

  test('approved destructive call executes exactly once', () async {
    final tool = _ExecutableTool(
      name: 'delete_file',
      riskLevel: ToolRiskLevel.dangerous,
      inputSchema: _pathSchema,
      outputSchema: _okSchema,
    );
    final executor = ToolExecutor(
      registry: ToolRegistry()..register(tool),
      permissions: permissions,
    );
    final args = <String, Object?>{'path': '${root.path}/clip.mp4'};
    final request = permissions.requestApproval(
      toolName: 'delete_file',
      riskLevel: ToolRiskLevel.dangerous,
      arguments: args,
      workspaceRoot: root.path,
    );
    final token = permissions.approve(request.requestId)!;

    final first = await executor.executeCall(
      toolName: 'delete_file',
      arguments: args,
      context: context(approval: token),
    );
    expect(first.result.success, isTrue);
    expect(tool.executions, 1);

    final replay = await executor.executeCall(
      toolName: 'delete_file',
      arguments: args,
      context: context(approval: token),
    );
    expect(replay.result.success, isFalse);
    expect(tool.executions, 1);
  });

  test('shell tools never execute without approval', () async {
    final shell = _ExecutableTool(
      name: 'run_command',
      riskLevel: ToolRiskLevel.safe,
      inputSchema: _pathSchema,
      outputSchema: _okSchema,
    );
    final executor = ToolExecutor(
      registry: ToolRegistry()..register(shell),
      permissions: permissions,
    );
    // Deliberately shaped like a path argument so the call would otherwise look
    // harmless; shell detection still forces HIGH risk.
    final outcome = await executor.executeCall(
      toolName: 'run_command',
      arguments: {'path': '${root.path}/ffmpeg'},
      context: context(),
    );
    expect(outcome.result.success, isFalse);
    expect(
      outcome.result.errorCode,
      anyOf(
        ShadowErrorCode.permApprovalRequired,
        ShadowErrorCode.permShellBlocked,
      ),
    );
    expect(shell.executions, 0);
  });

  test(
    'executor rejects path escapes even with an allow-all permission service',
    () async {
      final tool = _ExecutableTool(
        name: 'list_files',
        riskLevel: ToolRiskLevel.safe,
        inputSchema: _pathSchema,
        outputSchema: _okSchema,
      );
      final executor = ToolExecutor(
        registry: ToolRegistry()..register(tool),
        permissions: _AllowAllPermissions(),
      );
      final outside = await Directory.systemTemp.createTemp('perm_tool_out_');
      addTearDown(() async {
        if (outside.existsSync()) await outside.delete(recursive: true);
      });

      final outcome = await executor.executeCall(
        toolName: 'list_files',
        arguments: {'path': outside.path},
        context: context(),
      );
      expect(outcome.result.success, isFalse);
      expect(outcome.result.errorCode, ShadowErrorCode.permPathEscape);
      expect(tool.executions, 0);
    },
  );

  test('relative paths are canonicalized before the tool sees them', () async {
    await Directory('${root.path}/sub').create();
    final tool = _ExecutableTool(
      name: 'list_files',
      riskLevel: ToolRiskLevel.safe,
      inputSchema: _pathSchema,
      outputSchema: _okSchema,
    );
    final executor = ToolExecutor(
      registry: ToolRegistry()..register(tool),
      permissions: _AllowAllPermissions(),
    );
    final input = <String, Object?>{'path': 'sub'};

    final outcome = await executor.executeCall(
      toolName: 'list_files',
      arguments: input,
      context: context(),
    );

    expect(outcome.result.success, isTrue);
    final expected = await Directory('${root.path}/sub').resolveSymbolicLinks();
    expect(tool.lastArguments?['path'], expected);
    // The caller's map is not mutated; approval binding stays on the original.
    expect(input['path'], 'sub');
  });

  test(
    'ambiguous target identifiers are not rewritten, path values are',
    () async {
      const schema = <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'target': <String, Object?>{'type': 'string'},
        },
        'required': <String>['target'],
        'additionalProperties': false,
      };
      final tool = _ExecutableTool(
        name: 'timeline_edit',
        riskLevel: ToolRiskLevel.restricted,
        inputSchema: schema,
        outputSchema: _okSchema,
      );
      final executor = ToolExecutor(
        registry: ToolRegistry()..register(tool),
        permissions: perm.PermissionManager(),
      );

      final ok = await executor.executeCall(
        toolName: 'timeline_edit',
        arguments: {'target': 'main'},
        context: context(),
      );
      expect(ok.result.success, isTrue);
      expect(tool.lastArguments?['target'], 'main');

      final escape = await executor.executeCall(
        toolName: 'timeline_edit',
        arguments: {'target': '/etc/passwd'},
        context: context(),
      );
      expect(escape.result.success, isFalse);
      expect(escape.result.errorCode, ShadowErrorCode.permPathEscape);
    },
  );

  test('executor rejects path smuggling under assetPath', () async {
    final tool = _ExecutableTool(
      name: 'list_files',
      riskLevel: ToolRiskLevel.safe,
      inputSchema: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'assetPath': <String, Object?>{'type': 'string'},
        },
        'required': <String>['assetPath'],
        'additionalProperties': false,
      },
      outputSchema: _okSchema,
    );
    final executor = ToolExecutor(
      registry: ToolRegistry()..register(tool),
      permissions: _AllowAllPermissions(),
    );
    final outcome = await executor.executeCall(
      toolName: 'list_files',
      arguments: {'assetPath': '/etc/passwd'},
      context: context(),
    );
    expect(outcome.result.success, isFalse);
    expect(outcome.result.errorCode, ShadowErrorCode.permPathEscape);
    expect(tool.executions, 0);
  });

  test('cancellation after approval still prevents execution', () async {
    final tool = _ExecutableTool(
      name: 'delete_file',
      riskLevel: ToolRiskLevel.dangerous,
      inputSchema: _pathSchema,
      outputSchema: _okSchema,
    );
    final executor = ToolExecutor(
      registry: ToolRegistry()..register(tool),
      permissions: permissions,
    );
    final args = <String, Object?>{'path': '${root.path}/clip.mp4'};
    final request = permissions.requestApproval(
      toolName: 'delete_file',
      riskLevel: ToolRiskLevel.dangerous,
      arguments: args,
      workspaceRoot: root.path,
    );
    final token = permissions.approve(request.requestId)!;
    final cancel = CancellationToken()..cancel('user');
    final outcome = await executor.executeCall(
      toolName: 'delete_file',
      arguments: args,
      context: ToolContext(
        taskId: 'task-1',
        correlationId: 'corr-1',
        revision: 0,
        workspaceRoot: root.path,
        cancel: cancel,
        audit: toolAudit,
        approval: token,
      ),
    );
    expect(outcome.result.success, isFalse);
    expect(outcome.result.errorCode, ShadowErrorCode.agentCancelled);
    expect(tool.executions, 0);
  });
}

class _AllowAllPermissions implements PermissionService {
  @override
  Future<PermissionDecision> authorizeToolCall({
    required String toolName,
    required ToolRiskLevel riskLevel,
    required Map<String, Object?> arguments,
    required String workspaceRoot,
    ApprovalToken? approval,
  }) async => const PermissionDecision.allow();

  @override
  Future<PermissionDecision> authorizeEgress(EgressRequest request) async =>
      const PermissionDecision.allow();

  @override
  Future<void> validatePath({
    required String path,
    required String workspaceRoot,
    required bool write,
  }) async {}
}
