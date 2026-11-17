import 'package:shadow_permissions/permissions.dart' as perm;
import 'dart:async';
import 'dart:io';

import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:test/test.dart';

void main() {
  group(
    'perm.PathValidator / perm.WorkspaceGuard - traversal & symlink escapes',
    () {
      late Directory root;
      late Directory outside;

      setUp(() async {
        root = await Directory.systemTemp.createTemp('perm_root_');
        outside = await Directory.systemTemp.createTemp('perm_out_');
      });

      tearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
        if (outside.existsSync()) await outside.delete(recursive: true);
      });

      test('rejects path traversal escaping workspace', () async {
        final validator = const perm.PathValidator();
        final escaping =
            '${root.path}/../../${outside.uri.pathSegments[outside.uri.pathSegments.length - 2]}';
        await expectLater(
          () => validator.assertWithinWorkspace(
            targetPath: escaping,
            workspaceRoot: root.path,
          ),
          throwsA(
            isA<perm.PathSecurityException>().having(
              (e) => e.code,
              'code',
              ShadowErrorCode.permPathEscape,
            ),
          ),
        );
      });

      test('rejects absolute path outside workspace', () async {
        final validator = const perm.PathValidator();
        await expectLater(
          () => validator.assertWithinWorkspace(
            targetPath: outside.path,
            workspaceRoot: root.path,
          ),
          throwsA(
            isA<perm.PathSecurityException>().having(
              (e) => e.code,
              'code',
              ShadowErrorCode.permPathEscape,
            ),
          ),
        );
      });

      test('rejects symlink that escapes workspace', () async {
        final linkPath = '${root.path}/escape_link';
        final link = Link(linkPath);
        await link.create(outside.path);
        final validator = const perm.PathValidator();
        await expectLater(
          () => validator.assertWithinWorkspace(
            targetPath: linkPath,
            workspaceRoot: root.path,
          ),
          throwsA(
            isA<perm.PathSecurityException>().having(
              (e) => e.code,
              'code',
              ShadowErrorCode.permPathEscape,
            ),
          ),
        );
      });

      test(
        'rejects traversal through symlinked parent inside workspace',
        () async {
          final sub = Directory('${root.path}/sub')..createSync();
          final linkToOutside = Link('${sub.path}/jump');
          await linkToOutside.create(outside.path);
          final validator = const perm.PathValidator();
          await expectLater(
            () => validator.assertWithinWorkspace(
              targetPath: '${sub.path}/jump/secret.txt',
              workspaceRoot: root.path,
            ),
            throwsA(
              isA<perm.PathSecurityException>().having(
                (e) => e.code,
                'code',
                ShadowErrorCode.permPathEscape,
              ),
            ),
          );
        },
      );

      test('allows canonical path inside workspace', () async {
        final file = File('${root.path}/ok.txt')..createSync();
        final validator = const perm.PathValidator();
        final canonical = await validator.canonicalizeWithinWorkspace(
          targetPath: file.path,
          workspaceRoot: root.path,
        );
        expect(canonical, isNotEmpty);
      });

      test(
        'perm.WorkspaceGuard validates path-like arguments recursively',
        () async {
          final guard = perm.WorkspaceGuard();
          await expectLater(
            () => guard.validateArgumentsPaths(
              arguments: {
                'nested': {'path': outside.path},
              },
              workspaceRoot: root.path,
            ),
            throwsA(
              isA<perm.PathSecurityException>().having(
                (e) => e.code,
                'code',
                ShadowErrorCode.permPathEscape,
              ),
            ),
          );
        },
      );
    },
  );

  group('perm.PermissionPolicy - risk classes', () {
    test('classifies SAFE/RESTRICTED/DANGEROUS only', () {
      const policy = perm.PermissionPolicy();
      expect(policy.classify('get_metadata'), ToolRiskLevel.safe);
      expect(policy.classify('trim_clip'), ToolRiskLevel.restricted);
      expect(policy.classify('scan_media'), ToolRiskLevel.safe);
      expect(policy.classify('create_project'), ToolRiskLevel.restricted);
      expect(policy.classify('open_project'), ToolRiskLevel.restricted);
      expect(policy.classify('analyze_video'), ToolRiskLevel.safe);
      expect(policy.classify('delete_file'), ToolRiskLevel.dangerous);
      expect(policy.classify('overwrite_file'), ToolRiskLevel.dangerous);
      expect(policy.classify('export_project'), ToolRiskLevel.dangerous);
    });
  });

  group('perm.PermissionManager - approvals, binding, replay, expiry, consent', () {
    late Directory root;
    late perm.PermissionManager manager;
    late perm.InMemoryAuditLogger audit;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('perm_mgr_');
      audit = perm.InMemoryAuditLogger();
      manager = perm.PermissionManager(auditLogger: audit);
    });

    tearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });

    test('SAFE operation allowed without approval and audited', () async {
      final decision = await manager.authorizeToolCall(
        toolName: 'get_metadata',
        riskLevel: ToolRiskLevel.safe,
        arguments: {'path': '${root.path}/a.txt'},
        workspaceRoot: root.path,
      );
      expect(decision.allowed, isTrue);
      expect(
        audit.records.any(
          (r) => r.action == 'authorize_tool' && r.outcome == 'allowed',
        ),
        isTrue,
      );
    });

    test(
      'DANGEROUS operation requires explicit approval (no permanent mode)',
      () async {
        final d1 = await manager.authorizeToolCall(
          toolName: 'delete_file',
          riskLevel: ToolRiskLevel.dangerous,
          arguments: {'path': '${root.path}/a.txt'},
          workspaceRoot: root.path,
        );
        expect(d1.allowed, isFalse);
        expect(d1.requiresApproval, isTrue);
        expect(d1.reasonCode, ShadowErrorCode.permApprovalRequired);

        // request + approve + use once
        final req = manager.requestApproval(
          toolName: 'delete_file',
          riskLevel: ToolRiskLevel.dangerous,
          arguments: {'path': '${root.path}/a.txt'},
          workspaceRoot: root.path,
        );
        final token = manager.approve(req.requestId)!;
        final d2 = await manager.authorizeToolCall(
          toolName: 'delete_file',
          riskLevel: ToolRiskLevel.dangerous,
          arguments: {'path': '${root.path}/a.txt'},
          workspaceRoot: root.path,
          approval: token,
        );
        expect(d2.allowed, isTrue);

        // second attempt must require approval again (no permanent approval)
        final d3 = await manager.authorizeToolCall(
          toolName: 'delete_file',
          riskLevel: ToolRiskLevel.dangerous,
          arguments: {'path': '${root.path}/a.txt'},
          workspaceRoot: root.path,
        );
        expect(d3.requiresApproval, isTrue);
      },
    );

    test('rejects replayed approval token (single-use)', () async {
      final args = {'path': '${root.path}/x.txt'};
      final req = manager.requestApproval(
        toolName: 'overwrite_file',
        riskLevel: ToolRiskLevel.dangerous,
        arguments: args,
        workspaceRoot: root.path,
      );
      final token = manager.approve(req.requestId)!;
      final ok = await manager.authorizeToolCall(
        toolName: 'overwrite_file',
        riskLevel: ToolRiskLevel.dangerous,
        arguments: args,
        workspaceRoot: root.path,
        approval: token,
      );
      expect(ok.allowed, isTrue);
      final replay = await manager.authorizeToolCall(
        toolName: 'overwrite_file',
        riskLevel: ToolRiskLevel.dangerous,
        arguments: args,
        workspaceRoot: root.path,
        approval: token,
      );
      expect(replay.allowed, isFalse);
      expect(replay.reasonCode, ShadowErrorCode.permApprovalInvalid);
    });

    test('rejects token with modified arguments (hash-bound)', () async {
      final req = manager.requestApproval(
        toolName: 'export_project',
        riskLevel: ToolRiskLevel.dangerous,
        arguments: {'path': '${root.path}/a.zip'},
        workspaceRoot: root.path,
      );
      final token = manager.approve(req.requestId)!;
      final res = await manager.authorizeToolCall(
        toolName: 'export_project',
        riskLevel: ToolRiskLevel.dangerous,
        arguments: {'path': '${root.path}/b.zip'}, // modified
        workspaceRoot: root.path,
        approval: token,
      );
      expect(res.allowed, isFalse);
      expect(res.reasonCode, ShadowErrorCode.permApprovalInvalid);
    });

    test('rejects token bound to different tool call', () async {
      final args = {'path': '${root.path}/a.txt'};
      final req = manager.requestApproval(
        toolName: 'delete_file',
        riskLevel: ToolRiskLevel.dangerous,
        arguments: args,
        workspaceRoot: root.path,
      );
      final token = manager.approve(req.requestId)!;
      final res = await manager.authorizeToolCall(
        toolName: 'overwrite_file',
        riskLevel: ToolRiskLevel.dangerous,
        arguments: args,
        workspaceRoot: root.path,
        approval: token,
      );
      expect(res.allowed, isFalse);
      expect(res.reasonCode, ShadowErrorCode.permApprovalInvalid);
    });

    test('rejects expired approvals', () async {
      final fast = perm.PermissionManager(
        auditLogger: audit,
        approvalTtl: const Duration(milliseconds: 10),
      );
      final req = fast.requestApproval(
        toolName: 'delete_file',
        riskLevel: ToolRiskLevel.dangerous,
        arguments: {'path': '${root.path}/a.txt'},
        workspaceRoot: root.path,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        fast.approve(req.requestId),
        isNull,
        reason: 'expired request must not mint token',
      );
      final expiredToken = perm.ApprovalToken(
        id: 'atk_exp',
        toolName: 'delete_file',
        inputHash: req.argumentsHash,
        issuedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        singleUse: true,
      );
      final res = await fast.authorizeToolCall(
        toolName: 'delete_file',
        riskLevel: ToolRiskLevel.dangerous,
        arguments: {'path': '${root.path}/a.txt'},
        workspaceRoot: root.path,
        approval: expiredToken,
      );
      expect(res.allowed, isFalse);
      expect(res.reasonCode, ShadowErrorCode.permApprovalTimeout);
    });

    test('rejects unauthorized/escaping paths in tool args', () async {
      final res = await manager.authorizeToolCall(
        toolName: 'list_files',
        riskLevel: ToolRiskLevel.safe,
        arguments: {'path': '/etc'},
        workspaceRoot: root.path,
      );
      expect(res.allowed, isFalse);
      expect(res.reasonCode, ShadowErrorCode.permPathEscape);
    });

    test(
      'AI data egress requires separate explicit consent (file approval not enough)',
      () async {
        final egress = const EgressRequest(
          providerId: 'openai',
          resourceKind: 'image',
          resourceRefs: ['frame.png'],
          purpose: 'analyze',
        );
        final denied = await manager.authorizeEgress(egress);
        expect(denied.allowed, isFalse);
        expect(denied.requiresApproval, isTrue);
        expect(denied.reasonCode, ShadowErrorCode.permApprovalRequired);

        // file operation approval/allow does not grant egress consent
        await manager.authorizeToolCall(
          toolName: 'get_metadata',
          riskLevel: ToolRiskLevel.safe,
          arguments: {'path': '${root.path}/f.mp4'},
          workspaceRoot: root.path,
        );
        final stillDenied = await manager.authorizeEgress(egress);
        expect(stillDenied.allowed, isFalse);

        await (manager.egressConsent as perm.InMemoryAiEgressConsentManager)
            .grantConsent(
              providerId: 'openai',
              resourceKind: 'image',
              resourceRefs: ['frame.png'],
              purpose: 'analyze',
            );
        final allowed = await manager.authorizeEgress(egress);
        expect(allowed.allowed, isTrue);
      },
    );

    test('missing egress consent is denied (negative)', () async {
      final res = await manager.authorizeEgress(
        const EgressRequest(
          providerId: 'gemini',
          resourceKind: 'file',
          resourceRefs: ['a.mov'],
        ),
      );
      expect(res.allowed, isFalse);
      expect(res.reasonCode, ShadowErrorCode.permApprovalRequired);
    });

    test('records sensitive actions in append-only audit logger', () async {
      final logFile = File('${root.path}/audit.log');
      final fileAudit = perm.AppendOnlyAuditLogger(logFilePath: logFile.path);
      final mgr = perm.PermissionManager(auditLogger: fileAudit);
      await mgr.authorizeToolCall(
        toolName: 'get_metadata',
        riskLevel: ToolRiskLevel.safe,
        arguments: {'path': '${root.path}/x'},
        workspaceRoot: root.path,
      );
      await mgr.authorizeToolCall(
        toolName: 'delete_file',
        riskLevel: ToolRiskLevel.dangerous,
        arguments: {'path': '${root.path}/x'},
        workspaceRoot: root.path,
      );
      final lines = await logFile.readAsLines();
      expect(lines.length, greaterThanOrEqualTo(2));
      // append-only: write again increases count
      await mgr.authorizeToolCall(
        toolName: 'scan_media',
        riskLevel: ToolRiskLevel.safe,
        arguments: {'directory': root.path},
        workspaceRoot: root.path,
      );
      final lines2 = await logFile.readAsLines();
      expect(lines2.length, greaterThan(lines.length));
    });

    test('cancellation prevents subsequent tool execution (guard)', () {
      final cancel = CancellationToken()..cancel('user');
      expect(
        () => manager.assertNotCancelled(cancel),
        throwsA(isA<CancelledException>()),
      );
    });

    test(
      'never accepts permission changes from model responses (policy independent)',
      () async {
        // even if arguments try to smuggle approval/permission flags, dangerous still requires approval
        final res = await manager.authorizeToolCall(
          toolName: 'overwrite_file',
          riskLevel: ToolRiskLevel.dangerous,
          arguments: {
            'path': '${root.path}/f.txt',
            'grantPermission': true,
            'approved': true,
            'permission': 'allow',
          },
          workspaceRoot: root.path,
        );
        expect(res.allowed, isFalse);
        expect(res.requiresApproval, isTrue);
      },
    );
  });
}
