import 'dart:io';

import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:shadow_permissions/permissions.dart' as perm;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late perm.InMemoryAuditLogger audit;
  late DateTime clock;
  late perm.PermissionManager manager;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('perm_adv_');
    audit = perm.InMemoryAuditLogger();
    clock = DateTime.utc(2026, 11, 17, 12);
    manager = perm.PermissionManager(
      auditLogger: audit,
      policy: const perm.PermissionPolicy(),
      now: () => clock,
      approvalTtl: const Duration(minutes: 10),
    );
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  group('approval integrity', () {
    test(
      'rejects a forged token that was never minted by the engine',
      () async {
        final args = <String, Object?>{'path': '${root.path}/a.txt'};
        final forged = ApprovalToken(
          id: 'atk_forged',
          toolName: 'delete_file',
          inputHash: perm.hashToolCallBinding(
            toolName: 'delete_file',
            arguments: args,
          ),
          issuedAt: clock,
          expiresAt: clock.add(const Duration(hours: 1)),
          singleUse: true,
        );
        final decision = await manager.authorizeToolCall(
          toolName: 'delete_file',
          riskLevel: ToolRiskLevel.dangerous,
          arguments: args,
          workspaceRoot: root.path,
          approval: forged,
        );
        expect(decision.allowed, isFalse);
        expect(decision.reasonCode, ShadowErrorCode.permApprovalInvalid);
      },
    );

    test('a request can only be approved once', () {
      final req = manager.requestApproval(
        toolName: 'delete_file',
        riskLevel: ToolRiskLevel.dangerous,
        arguments: {'path': '${root.path}/a.txt'},
        workspaceRoot: root.path,
      );
      expect(manager.approve(req.requestId), isNotNull);
      expect(manager.approve(req.requestId), isNull);
    });

    test(
      'approval expires deterministically with the injected clock',
      () async {
        final args = <String, Object?>{'path': '${root.path}/a.txt'};
        final req = manager.requestApproval(
          toolName: 'delete_file',
          riskLevel: ToolRiskLevel.dangerous,
          arguments: args,
          workspaceRoot: root.path,
        );
        final token = manager.approve(req.requestId)!;
        clock = clock.add(const Duration(minutes: 11));
        final decision = await manager.authorizeToolCall(
          toolName: 'delete_file',
          riskLevel: ToolRiskLevel.dangerous,
          arguments: args,
          workspaceRoot: root.path,
          approval: token,
        );
        expect(decision.allowed, isFalse);
        expect(decision.reasonCode, ShadowErrorCode.permApprovalTimeout);
      },
    );

    test('expired request cannot mint a token', () {
      final req = manager.requestApproval(
        toolName: 'delete_file',
        riskLevel: ToolRiskLevel.dangerous,
        arguments: {'path': '${root.path}/a.txt'},
        workspaceRoot: root.path,
      );
      clock = clock.add(const Duration(hours: 2));
      expect(manager.approve(req.requestId), isNull);
    });

    test('revoking approvals invalidates unused tokens', () async {
      final args = <String, Object?>{'path': '${root.path}/a.txt'};
      final req = manager.requestApproval(
        toolName: 'delete_file',
        riskLevel: ToolRiskLevel.dangerous,
        arguments: args,
        workspaceRoot: root.path,
      );
      final token = manager.approve(req.requestId)!;
      manager.clearPendingApprovals();
      final decision = await manager.authorizeToolCall(
        toolName: 'delete_file',
        riskLevel: ToolRiskLevel.dangerous,
        arguments: args,
        workspaceRoot: root.path,
        approval: token,
      );
      expect(decision.allowed, isFalse);
    });
  });

  group('fail-closed policy', () {
    test(
      'unclassified tools require approval instead of running silently',
      () async {
        final decision = await manager.authorizeToolCall(
          toolName: 'mystery_tool',
          riskLevel: ToolRiskLevel.safe,
          arguments: const <String, Object?>{},
          workspaceRoot: root.path,
        );
        expect(decision.allowed, isFalse);
        expect(decision.requiresApproval, isTrue);
        expect(decision.reasonCode, ShadowErrorCode.permPolicyUnknown);
      },
    );

    test('policy-manipulating tools are denied even with approval', () async {
      const name = 'grant_permission';
      final args = <String, Object?>{'tool': 'delete_file'};
      final req = manager.requestApproval(
        toolName: name,
        riskLevel: ToolRiskLevel.safe,
        arguments: args,
        workspaceRoot: root.path,
      );
      final token = manager.approve(req.requestId)!;
      final decision = await manager.authorizeToolCall(
        toolName: name,
        riskLevel: ToolRiskLevel.safe,
        arguments: args,
        workspaceRoot: root.path,
        approval: token,
      );
      expect(decision.allowed, isFalse);
      expect(decision.reasonCode, ShadowErrorCode.permPolicyDenied);
    });

    test('declared risk cannot downscope a dangerous tool', () async {
      final decision = await manager.authorizeToolCall(
        toolName: 'delete_file',
        riskLevel: ToolRiskLevel.safe,
        arguments: {'path': '${root.path}/a.txt'},
        workspaceRoot: root.path,
      );
      expect(decision.allowed, isFalse);
      expect(decision.requiresApproval, isTrue);
    });

    test(
      'medium-risk timeline edits are allowed in-workspace but classified restricted',
      () {
        const policy = perm.PermissionPolicy();
        expect(policy.classify('add_clip'), ToolRiskLevel.restricted);
        expect(policy.classify('trim_clip'), ToolRiskLevel.restricted);
        expect(policy.classify('generate_subtitles'), ToolRiskLevel.restricted);
        expect(policy.classify('create_temp_file'), ToolRiskLevel.restricted);
      },
    );
  });

  group('shell execution protection', () {
    test('shell tool without approval is not executed', () async {
      final decision = await manager.authorizeToolCall(
        toolName: 'run_command',
        riskLevel: ToolRiskLevel.safe, // downscoping attempt
        arguments: {
          'executable': 'ffmpeg',
          'args': ['-version'],
          'workingDirectory': root.path,
        },
        workspaceRoot: root.path,
      );
      expect(decision.allowed, isFalse);
      expect(decision.requiresApproval, isTrue);
    });

    test('shell tool alias is recognized as shell execution', () {
      expect(perm.ShellCommandGuard.isShellTool('run_command'), isTrue);
      expect(perm.ShellCommandGuard.isShellTool('spawn_process'), isTrue);
      expect(
        perm.ShellCommandGuard.isShellTool('executeExternalCommand'),
        isTrue,
      );
      expect(perm.ShellCommandGuard.isShellTool('trim_clip'), isFalse);
    });

    test(
      'approved shell call with an allowlisted binary runs only once',
      () async {
        final args = <String, Object?>{
          'executable': 'ffmpeg',
          'args': ['-version'],
          'workingDirectory': root.path,
        };
        final req = manager.requestApproval(
          toolName: 'run_command',
          riskLevel: ToolRiskLevel.dangerous,
          arguments: args,
          workspaceRoot: root.path,
        );
        final token = manager.approve(req.requestId)!;
        final first = await manager.authorizeToolCall(
          toolName: 'run_command',
          riskLevel: ToolRiskLevel.dangerous,
          arguments: args,
          workspaceRoot: root.path,
          approval: token,
        );
        expect(first.allowed, isTrue);

        final replay = await manager.authorizeToolCall(
          toolName: 'run_command',
          riskLevel: ToolRiskLevel.dangerous,
          arguments: args,
          workspaceRoot: root.path,
          approval: token,
        );
        expect(replay.allowed, isFalse);
      },
    );

    test('non-allowlisted binaries are blocked even with approval', () async {
      final args = <String, Object?>{
        'executable': '/bin/sh',
        'args': ['-c', 'id'],
      };
      final req = manager.requestApproval(
        toolName: 'run_command',
        riskLevel: ToolRiskLevel.dangerous,
        arguments: args,
        workspaceRoot: root.path,
      );
      final token = manager.approve(req.requestId)!;
      final decision = await manager.authorizeToolCall(
        toolName: 'run_command',
        riskLevel: ToolRiskLevel.dangerous,
        arguments: args,
        workspaceRoot: root.path,
        approval: token,
      );
      expect(decision.allowed, isFalse);
      expect(decision.reasonCode, ShadowErrorCode.permShellBlocked);
    });

    test('shell command strings with arguments are rejected', () async {
      final decision = await manager.authorizeToolCall(
        toolName: 'run_command',
        riskLevel: ToolRiskLevel.dangerous,
        arguments: {'command': 'ffmpeg -i input.mp4 out.mp4'},
        workspaceRoot: root.path,
      );
      expect(decision.allowed, isFalse);
      expect(decision.reasonCode, ShadowErrorCode.permShellBlocked);
    });

    test('shell metacharacters in arguments are rejected', () async {
      final guard = const perm.ShellCommandGuard();
      expect(
        guard.firstViolation(
          const perm.ShellCommand(
            executable: 'ffmpeg',
            arguments: ['-i', 'a.mp4; rm -rf /'],
          ),
        ),
        isNotNull,
      );
      expect(
        guard.firstViolation(
          const perm.ShellCommand(
            executable: 'ffmpeg',
            arguments: ['-i', 'a.mp4'],
          ),
        ),
        isNull,
      );
    });

    test('working directory outside the workspace is rejected', () async {
      final outside = await Directory.systemTemp.createTemp('perm_shell_out_');
      addTearDown(() async {
        if (outside.existsSync()) await outside.delete(recursive: true);
      });
      final args = <String, Object?>{
        'executable': 'ffmpeg',
        'args': ['-version'],
        'workingDirectory': outside.path,
      };
      final req = manager.requestApproval(
        toolName: 'run_command',
        riskLevel: ToolRiskLevel.dangerous,
        arguments: args,
        workspaceRoot: root.path,
      );
      final token = manager.approve(req.requestId)!;
      final decision = await manager.authorizeToolCall(
        toolName: 'run_command',
        riskLevel: ToolRiskLevel.dangerous,
        arguments: args,
        workspaceRoot: root.path,
        approval: token,
      );
      expect(decision.allowed, isFalse);
      expect(decision.reasonCode, ShadowErrorCode.permPathEscape);
    });

    test('direct shell authorization API enforces the same rules', () async {
      const command = perm.ShellCommand(
        executable: 'ffprobe',
        arguments: ['-version'],
      );
      final denied = await manager.authorizeShellCommand(
        command: command,
        workspaceRoot: root.path,
      );
      expect(denied.requiresApproval, isTrue);

      final args = manager.shellApprovalArguments(command);
      final req = manager.requestApproval(
        toolName: 'run_command',
        riskLevel: ToolRiskLevel.dangerous,
        arguments: args,
        workspaceRoot: root.path,
      );
      final token = manager.approve(req.requestId)!;
      final allowed = await manager.authorizeShellCommand(
        command: command,
        workspaceRoot: root.path,
        approval: token,
      );
      expect(allowed.allowed, isTrue);
    });
  });

  group('malicious paths and arguments', () {
    test('path smuggling under an unrelated key is rejected', () async {
      final decision = await manager.authorizeToolCall(
        toolName: 'get_metadata',
        riskLevel: ToolRiskLevel.safe,
        arguments: {'assetPath': '/etc/shadow'},
        workspaceRoot: root.path,
      );
      expect(decision.allowed, isFalse);
      expect(decision.reasonCode, ShadowErrorCode.permPathEscape);
    });

    test('parent traversal in any string argument is rejected', () async {
      final decision = await manager.authorizeToolCall(
        toolName: 'list_files',
        riskLevel: ToolRiskLevel.safe,
        arguments: {'note': '../../etc/passwd'},
        workspaceRoot: root.path,
      );
      expect(decision.allowed, isFalse);
      expect(decision.reasonCode, ShadowErrorCode.permPathEscape);
    });

    test(
      'Windows-style parent traversal is rejected on every platform',
      () async {
        final decision = await manager.authorizeToolCall(
          toolName: 'list_files',
          riskLevel: ToolRiskLevel.safe,
          arguments: {'path': r'..\..\etc\passwd'},
          workspaceRoot: root.path,
        );
        expect(decision.allowed, isFalse);
        expect(decision.reasonCode, ShadowErrorCode.permPathEscape);
      },
    );

    test('NUL bytes and control characters are rejected', () async {
      final decision = await manager.authorizeToolCall(
        toolName: 'list_files',
        riskLevel: ToolRiskLevel.safe,
        arguments: {'path': '${root.path}/a\u0000b'},
        workspaceRoot: root.path,
      );
      expect(decision.allowed, isFalse);
      expect(decision.reasonCode, ShadowErrorCode.permInvalidArgument);
    });

    test('a non-existent workspace root fails closed', () async {
      final missing = '${root.path}/does-not-exist';
      final decision = await manager.authorizeToolCall(
        toolName: 'list_files',
        riskLevel: ToolRiskLevel.safe,
        arguments: {'path': missing},
        workspaceRoot: missing,
      );
      expect(decision.allowed, isFalse);
      expect(decision.reasonCode, ShadowErrorCode.permPathEscape);
    });

    test('all denials are audited', () async {
      await manager.authorizeToolCall(
        toolName: 'list_files',
        riskLevel: ToolRiskLevel.safe,
        arguments: {'path': '/etc'},
        workspaceRoot: root.path,
      );
      expect(
        audit.records.any(
          (r) => r.action == 'authorize_tool' && r.outcome == 'denied',
        ),
        isTrue,
      );
    });
  });

  group('egress consent expiry', () {
    test('consent expires and must be re-granted', () async {
      final consent = perm.InMemoryAiEgressConsentManager(
        defaultTtl: const Duration(minutes: 5),
        now: () => clock,
      );
      final mgr = perm.PermissionManager(
        auditLogger: audit,
        egressConsent: consent,
        now: () => clock,
      );
      const request = EgressRequest(
        providerId: 'openai',
        resourceKind: 'image',
        resourceRefs: ['frame.png'],
        purpose: 'analyze',
      );
      await consent.grantConsent(
        providerId: 'openai',
        resourceKind: 'image',
        resourceRefs: ['frame.png'],
        purpose: 'analyze',
      );
      expect((await mgr.authorizeEgress(request)).allowed, isTrue);
      clock = clock.add(const Duration(minutes: 6));
      final expired = await mgr.authorizeEgress(request);
      expect(expired.allowed, isFalse);
      expect(expired.requiresApproval, isTrue);
    });
  });
}
