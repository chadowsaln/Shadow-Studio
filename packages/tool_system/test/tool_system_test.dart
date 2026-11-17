import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:shadow_tool_system/testing.dart';
import 'package:shadow_tool_system/tool_system.dart';
import 'package:test/test.dart';

class RecordingAuditSink implements AuditSink {
  final List<Map<String, Object?>> events = <Map<String, Object?>>[];
  @override
  Future<void> record(Map<String, Object?> event) async {
    events.add(event);
  }
}

class AllowAllPermissions implements PermissionService {
  @override
  Future<PermissionDecision> authorizeToolCall({
    required String toolName,
    required ToolRiskLevel riskLevel,
    required Map<String, Object?> arguments,
    required String workspaceRoot,
    ApprovalToken? approval,
  }) async {
    return const PermissionDecision.allow();
  }

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

class DenyPermissions implements PermissionService {
  @override
  Future<PermissionDecision> authorizeToolCall({
    required String toolName,
    required ToolRiskLevel riskLevel,
    required Map<String, Object?> arguments,
    required String workspaceRoot,
    ApprovalToken? approval,
  }) async {
    return const PermissionDecision.deny(
      reason: 'denied',
      reasonCode: ShadowErrorCode.permApprovalRequired,
    );
  }

  @override
  Future<PermissionDecision> authorizeEgress(EgressRequest request) async =>
      const PermissionDecision.deny();
  @override
  Future<void> validatePath({
    required String path,
    required String workspaceRoot,
    required bool write,
  }) async {}
}

class BigResultTool implements AgentTool {
  @override
  String get name => 'big_result';
  @override
  String get description => 'returns big payload';
  @override
  ToolRiskLevel get riskLevel => ToolRiskLevel.safe;
  @override
  bool get idempotent => true;
  @override
  Duration get timeout => const Duration(seconds: 5);
  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'properties': <String, Object?>{},
    'additionalProperties': false,
  };
  @override
  Map<String, Object?> get outputSchema => {
    'type': 'object',
    'properties': <String, Object?>{
      'blob': <String, Object?>{'type': 'string'},
    },
    'additionalProperties': false,
  };
  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> arguments,
  ) async {
    return ToolResult(success: true, data: {'blob': 'x' * (300 * 1024)});
  }
}

class SlowTool implements AgentTool {
  @override
  String get name => 'slow';
  @override
  String get description => 'slow';
  @override
  ToolRiskLevel get riskLevel => ToolRiskLevel.safe;
  @override
  bool get idempotent => true;
  @override
  Duration get timeout => const Duration(seconds: 5);
  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'properties': <String, Object?>{},
    'additionalProperties': false,
  };
  @override
  Map<String, Object?> get outputSchema => {
    'type': 'object',
    'properties': <String, Object?>{
      'blob': <String, Object?>{'type': 'string'},
    },
    'additionalProperties': false,
  };
  bool completed = false;
  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> arguments,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    completed = true;
    return const ToolResult(success: true);
  }
}

ToolContext ctx({
  required String workspace,
  required AuditSink audit,
  int rev = 0,
  CancellationToken? cancel,
}) => ToolContext(
  taskId: 't1',
  correlationId: 'c1',
  revision: rev,
  workspaceRoot: workspace,
  cancel: cancel ?? CancellationToken(),
  audit: audit,
);

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('shadow_tool_test_');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('Registry & schema', () {
    test(
      'registers MVP tools with required declarations and rejects duplicates',
      () {
        final projects = MockProjectLifecycleService();
        final registry = ToolRegistry();
        final tools = buildMvpTools(
          projects: projects,
          media: MockMediaMetadataService(),
          env: const LocalEnvironmentInfoService(),
        );
        for (final t in tools) {
          expect(t.name, isNotEmpty);
          expect(t.description, isNotEmpty);
          expect(t.inputSchema['type'], 'object');
          expect(t.inputSchema['additionalProperties'], false);
          expect(t.riskLevel, isA<ToolRiskLevel>());
          registry.register(t);
        }
        expect(
          registry.all.map((t) => t.name),
          containsAll([
            'get_system_info',
            'inspect_capabilities',
            'list_files',
            'scan_media',
            'get_metadata',
            'create_project',
            'open_project',
            'save_project',
            'add_clip',
            'trim_clip',
          ]),
        );
        expect(
          () => registry.register(tools.first),
          throwsA(
            isA<StateError>().having(
              (e) => e.toString(),
              's',
              contains(ShadowErrorCode.toolDuplicateName),
            ),
          ),
        );
      },
    );

    test(
      'rejects additional JSON properties and unknown/invalid args',
      () async {
        final registry = ToolRegistry()..register(const ListFilesTool());
        final exec = ToolExecutor(
          registry: registry,
          permissions: AllowAllPermissions(),
        );
        final audit = RecordingAuditSink();
        final out = await exec.executeCall(
          toolName: 'list_files',
          arguments: {'path': tmp.path, 'extra': true},
          context: ctx(workspace: tmp.path, audit: audit),
        );
        expect(out.result.success, isFalse);
        expect(out.result.errorCode, ShadowErrorCode.toolInvalidArgs);
      },
    );
  });

  group('Execution pipeline', () {
    test('rejects unknown tool and records audit', () async {
      final registry = ToolRegistry();
      final exec = ToolExecutor(
        registry: registry,
        permissions: AllowAllPermissions(),
      );
      final audit = RecordingAuditSink();
      final out = await exec.executeCall(
        toolName: 'nope',
        arguments: {},
        context: ctx(workspace: tmp.path, audit: audit),
      );
      expect(out.result.errorCode, ShadowErrorCode.toolNotFound);
      expect(audit.events.single['tool'], 'nope');
      expect(audit.events.single['success'], false);
    });

    test('checks permissions and records audit', () async {
      final registry = ToolRegistry()..register(const ListFilesTool());
      final exec = ToolExecutor(
        registry: registry,
        permissions: DenyPermissions(),
      );
      final audit = RecordingAuditSink();
      final out = await exec.executeCall(
        toolName: 'list_files',
        arguments: {},
        context: ctx(workspace: tmp.path, audit: audit),
      );
      expect(out.result.success, isFalse);
      expect(out.result.errorCode, ShadowErrorCode.permApprovalRequired);
      expect(
        audit.events.last['error_code'],
        ShadowErrorCode.permApprovalRequired,
      );
    });

    test('validates workspace paths and rejects escape', () async {
      final registry = ToolRegistry()..register(const ListFilesTool());
      final exec = ToolExecutor(
        registry: registry,
        permissions: AllowAllPermissions(),
      );
      final audit = RecordingAuditSink();
      // create a path clearly outside by using ../ traversal
      final out = await exec.executeCall(
        toolName: 'list_files',
        arguments: {'path': '${tmp.path}/../..'},
        context: ctx(workspace: tmp.path, audit: audit),
      );
      expect(out.result.success, isFalse);
      expect(out.result.errorCode, ShadowErrorCode.permPathEscape);
    });

    test(
      'accepts workspace-relative paths and still rejects traversal',
      () async {
        final registry = ToolRegistry()..register(const ListFilesTool());
        final exec = ToolExecutor(
          registry: registry,
          permissions: AllowAllPermissions(),
        );
        final audit = RecordingAuditSink();
        final inside = Directory('${tmp.path}/nested')..createSync();
        File('${inside.path}/a.txt').createSync();

        final ok = await exec.executeCall(
          toolName: 'list_files',
          arguments: {'path': 'nested'},
          context: ctx(workspace: tmp.path, audit: audit),
        );
        expect(ok.result.success, isTrue);

        final escape = await exec.executeCall(
          toolName: 'list_files',
          arguments: {'path': '../../..'},
          context: ctx(workspace: tmp.path, audit: audit),
        );
        expect(escape.result.success, isFalse);
        expect(escape.result.errorCode, ShadowErrorCode.permPathEscape);
      },
    );

    test('limits tool result size to 256 KiB and marks truncated', () async {
      final registry = ToolRegistry()..register(BigResultTool());
      final exec = ToolExecutor(
        registry: registry,
        permissions: AllowAllPermissions(),
      );
      final audit = RecordingAuditSink();
      final out = await exec.executeCall(
        toolName: 'big_result',
        arguments: {},
        context: ctx(workspace: tmp.path, audit: audit),
      );
      expect(out.result.truncated, isTrue);
      expect(
        utf8.encode(jsonEncode(out.result.toJson())).length,
        lessThanOrEqualTo(256 * 1024),
      );
      expect(audit.events.single['truncated'], isTrue);
    });

    test('supports cancellation', () async {
      final registry = ToolRegistry()..register(SlowTool());
      final exec = ToolExecutor(
        registry: registry,
        permissions: AllowAllPermissions(),
      );
      final audit = RecordingAuditSink();
      final cancel = CancellationToken();
      final future = exec.executeCall(
        toolName: 'slow',
        arguments: {},
        context: ctx(workspace: tmp.path, audit: audit, cancel: cancel),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      cancel.cancel('stop');
      final out = await future;
      expect(out.result.success, isFalse);
      expect(out.result.errorCode, ShadowErrorCode.agentCancelled);
    });
  });

  group('Editing tools & revision consistency', () {
    test(
      'add_clip and trim_clip go through EditingService and enforce revision',
      () async {
        final projects = MockProjectLifecycleService();
        final registry = ToolRegistry();
        for (final t in [
          AddClipTool(projects.editing),
          TrimClipTool(projects.editing),
        ]) {
          registry.register(t);
        }
        final exec = ToolExecutor(
          registry: registry,
          permissions: AllowAllPermissions(),
        );
        final audit = RecordingAuditSink();

        final add = await exec.executeCall(
          toolName: 'add_clip',
          arguments: {
            'trackId': 'v1',
            'assetPath': '${tmp.path}/a.mp4',
            'startTick': 0,
            'durationTicks': 1000,
          },
          context: ctx(workspace: tmp.path, audit: audit, rev: 0),
        );
        expect(add.result.success, isTrue);
        expect(add.result.data['revision'], 1);
        expect(
          (projects.editing as MockEditingService)
              .applied
              .single
              .operations
              .single
              .type,
          'add_clip',
        );

        final stale = await exec.executeCall(
          toolName: 'trim_clip',
          arguments: {'clipId': 'c1', 'inTick': 0, 'outTick': 10},
          context: ctx(workspace: tmp.path, audit: audit, rev: 0),
        );
        expect(
          stale.result.success,
          isFalse,
        ); // editing service enforces expectedRevision
        // returned as tool failure wrapping mismatch
      },
    );

    test(
      'save_project detects revision mismatch and project tools use lifecycle service',
      () async {
        final projects = MockProjectLifecycleService();
        final registry = ToolRegistry();
        for (final t in buildMvpTools(
          projects: projects,
          media: MockMediaMetadataService(),
          env: const LocalEnvironmentInfoService(),
        )) {
          registry.register(t);
        }
        final exec = ToolExecutor(
          registry: registry,
          permissions: AllowAllPermissions(),
        );
        final audit = RecordingAuditSink();

        final created = await exec.executeCall(
          toolName: 'create_project',
          arguments: {'name': 'demo'},
          context: ctx(workspace: tmp.path, audit: audit, rev: 0),
        );
        expect(created.result.success, isTrue);
        expect(created.result.data['projectPath'], contains('demo.ssproj'));

        final saved = await exec.executeCall(
          toolName: 'save_project',
          arguments: {},
          context: ctx(workspace: tmp.path, audit: audit, rev: 0),
        );
        expect(saved.result.success, isTrue);

        final mismatch = await exec.executeCall(
          toolName: 'save_project',
          arguments: {},
          context: ctx(workspace: tmp.path, audit: audit, rev: 99),
        );
        expect(mismatch.result.success, isFalse);
        expect(mismatch.result.errorCode, ShadowErrorCode.editRevisionMismatch);
      },
    );
  });
}
