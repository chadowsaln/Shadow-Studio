import 'dart:io';

import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:shadow_permissions/permissions.dart' as perm;
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late File logFile;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('perm_audit_');
    logFile = File('${dir.path}/audit.jsonl');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test(
    'hash chain verifies across sequential and concurrent appends',
    () async {
      final logger = perm.AppendOnlyAuditLogger(logFilePath: logFile.path);
      await Future.wait(<Future<void>>[
        for (var i = 0; i < 25; i++)
          logger.logSensitive(
            action: 'authorize_tool',
            outcome: 'allowed',
            details: {'tool': 'list_files', 'index': i},
          ),
      ]);
      final verification = await logger.verifyChain();
      expect(verification.valid, isTrue, reason: verification.reason);
      expect(verification.recordCount, 25);
    },
  );

  test('modifying a record is detected', () async {
    final logger = perm.AppendOnlyAuditLogger(logFilePath: logFile.path);
    for (var i = 0; i < 3; i++) {
      await logger.logSensitive(
        action: 'authorize_tool',
        outcome: 'denied',
        details: {'index': i},
      );
    }
    final lines = await logFile.readAsLines();
    lines[1] = lines[1].replaceFirst('"denied"', '"allowed"');
    await logFile.writeAsString('${lines.join('\n')}\n');

    final verification = await logger.verifyChain();
    expect(verification.valid, isFalse);
    expect(verification.brokenAtLine, 2);
  });

  test('truncating the chain is detected', () async {
    final logger = perm.AppendOnlyAuditLogger(logFilePath: logFile.path);
    await logger.logSensitive(action: 'a', outcome: 'allowed');
    await logger.logSensitive(action: 'b', outcome: 'allowed');
    final lines = await logFile.readAsLines();
    await logFile.writeAsString('${lines.last}\n'); // drop the first record
    final verification = await logger.verifyChain();
    expect(verification.valid, isFalse);
  });

  test('secrets are redacted before they reach disk', () async {
    final logger = perm.AppendOnlyAuditLogger(logFilePath: logFile.path);
    await logger.logSensitive(
      action: 'provider_config',
      outcome: 'recorded',
      details: {
        'provider': 'openai',
        'api_key': 'sk-abcdef0123456789',
        'nested': {
          'authorization': 'Bearer abc.def.ghi',
          'password': 'hunter2',
          'note': 'token sk-zzzzzzzzzzzzzz leaked',
        },
        'safe': 'ffmpeg',
      },
    );
    final contents = await logFile.readAsString();
    expect(contents, isNot(contains('sk-abcdef0123456789')));
    expect(contents, isNot(contains('hunter2')));
    expect(contents, isNot(contains('abc.def.ghi')));
    expect(contents, isNot(contains('sk-zzzzzzzzzzzzzz')));
    expect(contents, contains('[REDACTED]'));
    expect(contents, contains('ffmpeg'));
    expect((await logger.verifyChain()).valid, isTrue);
  });

  test('file permissions are restricted on POSIX', () async {
    final logger = perm.AppendOnlyAuditLogger(logFilePath: logFile.path);
    await logger.logSensitive(action: 'a', outcome: 'allowed');
    if (!Platform.isWindows) {
      final mode = logFile.statSync().mode & 0x1FF;
      expect(mode, 0x180); // 0600
    }
  });

  test('permission denials never log raw argument values', () async {
    final logger = perm.AppendOnlyAuditLogger(logFilePath: logFile.path);
    final manager = perm.PermissionManager(auditLogger: logger);
    await manager.authorizeToolCall(
      toolName: 'delete_file',
      riskLevel: ToolRiskLevel.dangerous,
      arguments: {'path': '/outside/secret-name.mp4'},
      workspaceRoot: Directory.systemTemp.path,
    );
    final contents = await logFile.readAsString();
    expect(contents, isNot(contains('secret-name.mp4')));
    expect(contents, contains('PERM_PATH_ESCAPE'));
  });
}
