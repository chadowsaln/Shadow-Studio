import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:test/test.dart';

class _Tool implements AgentTool {
  _Tool({
    this.name = 'noop',
    this.description = 'does nothing',
    this.timeout = const Duration(seconds: 1),
    Map<String, Object?>? inputSchema,
    Map<String, Object?>? outputSchema,
  }) : inputSchema =
           inputSchema ??
           <String, Object?>{
             'type': 'object',
             'properties': <String, Object?>{},
             'additionalProperties': false,
           },
       outputSchema =
           outputSchema ??
           <String, Object?>{
             'type': 'object',
             'properties': <String, Object?>{},
             'additionalProperties': false,
           };

  @override
  final String name;
  @override
  final String description;
  @override
  ToolRiskLevel get riskLevel => ToolRiskLevel.safe;
  @override
  bool get idempotent => true;
  @override
  final Duration timeout;
  @override
  final Map<String, Object?> inputSchema;
  @override
  final Map<String, Object?> outputSchema;

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> arguments,
  ) async => const ToolResult.ok();
}

Map<String, Object?> _schema({
  Map<String, Object?> properties = const <String, Object?>{},
  List<Object?> required = const <Object?>[],
  bool closed = true,
}) {
  return <String, Object?>{
    'type': 'object',
    'properties': properties,
    'required': required,
    'additionalProperties': closed ? false : true,
  };
}

void main() {
  group('ToolSchemaValidator', () {
    const validator = ToolSchemaValidator();

    test('accepts a closed schema with valid arguments', () {
      final result = validator.validate(
        schema: _schema(
          properties: <String, Object?>{
            'name': <String, Object?>{'type': 'string'},
            'count': <String, Object?>{
              'type': 'integer',
              'minimum': 1,
              'maximum': 5,
            },
          },
          required: const <Object?>['name'],
        ),
        arguments: <String, Object?>{'name': 'x', 'count': 3},
      );
      expect(result.isValid, isTrue);
    });

    test('rejects additional properties when closed', () {
      final result = validator.validate(
        schema: _schema(),
        arguments: <String, Object?>{'extra': true},
      );
      expect(result.isValid, isFalse);
      expect(result.errors.join(';'), contains('additional property'));
    });

    test('rejects missing required fields and wrong types', () {
      final result = validator.validate(
        schema: _schema(
          properties: <String, Object?>{
            'name': <String, Object?>{'type': 'string'},
          },
          required: const <Object?>['name'],
        ),
        arguments: <String, Object?>{'name': 1},
      );
      expect(result.isValid, isFalse);
      expect(result.errors.join(';'), contains('expected string'));
    });

    test('enforces integer bounds and array item types', () {
      final result = validator.validate(
        schema: _schema(
          properties: <String, Object?>{
            'n': <String, Object?>{
              'type': 'integer',
              'minimum': 2,
              'maximum': 4,
            },
            'xs': <String, Object?>{
              'type': 'array',
              'items': <String, Object?>{'type': 'integer'},
            },
          },
        ),
        arguments: <String, Object?>{
          'n': 9,
          'xs': <Object?>[1, 'bad'],
        },
      );
      expect(result.isValid, isFalse);
      expect(result.errors.join(';'), contains('above maximum'));
      expect(result.errors.join(';'), contains('expected integer'));
    });
  });

  group('ToolContractValidator', () {
    const validator = ToolContractValidator();

    test('accepts a well-formed tool definition', () {
      expect(validator.validateDefinition(_Tool()), isEmpty);
    });

    test('rejects invalid names, empty descriptions and bad timeouts', () {
      final tool = _Tool(
        name: 'Bad-Name',
        description: '   ',
        timeout: Duration.zero,
      );
      final errors = validator.validateDefinition(tool);
      expect(errors.join(';'), contains('name'));
      expect(errors.join(';'), contains('description'));
      expect(errors.join(';'), contains('timeout'));
    });

    test('rejects non-closed input/output schemas', () {
      final tool = _Tool(
        inputSchema: _schema(closed: false),
        outputSchema: <String, Object?>{'type': 'object'},
      );
      final errors = validator.validateDefinition(tool);
      expect(errors.join(';'), contains('inputSchema.additionalProperties'));
      expect(errors.join(';'), contains('outputSchema.additionalProperties'));
    });

    test('validates successful results against the output schema', () {
      final tool = _Tool(
        outputSchema: _schema(
          properties: <String, Object?>{
            'revision': <String, Object?>{'type': 'integer'},
          },
        ),
      );
      expect(
        validator.validateResult(
          tool,
          ToolResult.ok(data: const {'revision': 1}),
        ),
        isEmpty,
      );

      final bad = validator.validateResult(
        tool,
        ToolResult.ok(data: const {'revision': 'one', 'extra': true}),
      );
      expect(bad.join(';'), contains('expected integer'));
      expect(bad.join(';'), contains('additional property'));
    });

    test('failed results require a code and message', () {
      final tool = _Tool();
      expect(
        validator.validateResult(
          tool,
          const ToolResult.failure(code: 'X', message: 'bad'),
        ),
        isEmpty,
      );
      final missing = validator.validateResult(
        tool,
        const ToolResult(success: false),
      );
      expect(missing.join(';'), contains('error_code'));
      expect(missing.join(';'), contains('error_message'));
    });
  });

  group('ToolResult status', () {
    test('maps error codes to execution statuses', () {
      expect(const ToolResult.ok().status, ToolExecutionStatus.succeeded);
      expect(
        const ToolResult.failure(
          code: ShadowErrorCode.toolTimeout,
          message: 't',
        ).status,
        ToolExecutionStatus.timedOut,
      );
      expect(
        const ToolResult.failure(
          code: ShadowErrorCode.agentCancelled,
          message: 'c',
        ).status,
        ToolExecutionStatus.cancelled,
      );
      expect(
        const ToolResult.failure(
          code: ShadowErrorCode.permApprovalRequired,
          message: 'a',
        ).status,
        ToolExecutionStatus.denied,
      );
      expect(
        const ToolResult.failure(
          code: ShadowErrorCode.toolFailed,
          message: 'f',
        ).status,
        ToolExecutionStatus.failed,
      );
    });

    test('JSON round-trips including status and duration', () {
      final result = ToolResult(
        success: true,
        data: const <String, Object?>{'revision': 3},
        duration: const Duration(milliseconds: 12),
      );
      final restored = ToolResult.fromJson(result.toJson());
      expect(restored.success, isTrue);
      expect(restored.data['revision'], 3);
      expect(restored.duration?.inMilliseconds, 12);
      expect(restored.status, ToolExecutionStatus.succeeded);
    });

    test('fromError carries the structured code and correlation id', () {
      const error = ShadowError(
        code: ShadowErrorCode.toolFailed,
        category: ShadowErrorCategory.tool,
        retryable: false,
        correlationId: 'corr-1',
        message: 'boom',
      );
      final result = ToolResult.fromError(error);
      expect(result.success, isFalse);
      expect(result.errorCode, ShadowErrorCode.toolFailed);
      expect(result.errorMessage, 'boom');
      expect(result.artifacts['correlation_id'], 'corr-1');
    });
  });

  group('ToolExecutionMetadata', () {
    test('JSON round-trips and reports terminal states', () {
      final meta = ToolExecutionMetadata(
        toolName: 'save',
        taskId: 't1',
        correlationId: 'c1',
        attempt: 2,
        status: ToolExecutionStatus.succeeded,
        startedAt: DateTime.utc(2026, 1, 1),
        finishedAt: DateTime.utc(2026, 1, 1, 0, 0, 1),
        duration: const Duration(seconds: 1),
        resultBytes: 42,
      );
      final restored = ToolExecutionMetadata.fromJson(meta.toJson());
      expect(restored.toolName, 'save');
      expect(restored.attempt, 2);
      expect(restored.status, ToolExecutionStatus.succeeded);
      expect(restored.isTerminal, isTrue);
      expect(restored.resultBytes, 42);
      expect(restored.duration?.inSeconds, 1);
    });

    test('non-terminal statuses are not terminal', () {
      final meta = ToolExecutionMetadata(
        toolName: 'x',
        taskId: 't',
        correlationId: 'c',
        attempt: 1,
        status: ToolExecutionStatus.running,
        startedAt: DateTime.utc(2026),
      );
      expect(meta.isTerminal, isFalse);
    });
  });

  group('Cancellation and timeouts', () {
    test('cancelAfter cancels with a reason', () async {
      final token = CancellationToken();
      token.cancelAfter(const Duration(milliseconds: 5), 'deadline');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(token.isCancelled, isTrue);
      expect(token.reason, 'deadline');
    });

    test('runWithTimeout returns a fast body', () async {
      final token = CancellationToken();
      final value = await runWithTimeout<int>(
        timeout: const Duration(seconds: 1),
        cancel: token,
        body: () async => 7,
      );
      expect(value, 7);
    });

    test('runWithTimeout throws ShadowTimeoutException', () async {
      final token = CancellationToken();
      await expectLater(
        runWithTimeout<void>(
          timeout: const Duration(milliseconds: 5),
          cancel: token,
          operation: 'slow_tool',
          body: () => Future<void>.delayed(const Duration(seconds: 1)),
        ),
        throwsA(isA<ShadowTimeoutException>()),
      );
    });

    test(
      'runWithTimeout throws CancelledException when pre-cancelled',
      () async {
        final token = CancellationToken()..cancel('stop');
        await expectLater(
          runWithTimeout<void>(
            timeout: const Duration(seconds: 1),
            cancel: token,
            body: () async {},
          ),
          throwsA(isA<CancelledException>()),
        );
      },
    );
  });

  group('ShadowError', () {
    test('serializes a stable structured error', () {
      const error = ShadowError(
        code: ShadowErrorCode.editRevisionMismatch,
        category: ShadowErrorCategory.edit,
        retryable: false,
        correlationId: 'c',
        details: <String, Object?>{'expected': 1, 'actual': 2},
        message: 'stale revision',
      );
      final json = error.toJson();
      expect(json['code'], ShadowErrorCode.editRevisionMismatch);
      expect(json['category'], 'edit');
      expect(json['retryable'], false);
      expect(json['correlation_id'], 'c');
      expect((json['details'] as Map)['expected'], 1);
    });
  });
}
