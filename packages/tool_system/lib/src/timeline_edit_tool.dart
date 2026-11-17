import 'package:shadow_contracts/shadow_contracts.dart';

Map<String, Object?> _closedObject({
  Map<String, Object?> properties = const <String, Object?>{},
  List<String> required = const <String>[],
}) {
  return <String, Object?>{
    'type': 'object',
    'properties': properties,
    'required': required,
    'additionalProperties': false,
  };
}

/// Applies validated, atomic timeline edits through the Editing Core.
///
/// The tool never touches media files and never bypasses editor invariants:
/// every call becomes one EditTransaction (one revision, one undo step) and
/// optimistic concurrency is enforced against [ToolContext.revision].
class TimelineEditTool implements AgentTool {
  TimelineEditTool(this._editing);

  final EditingService _editing;

  @override
  String get name => 'timeline_edit';

  @override
  String get description =>
      'Applies an atomic timeline edit (add/trim/split/move/remove clip, add track) with revision checks.';

  @override
  ToolRiskLevel get riskLevel => ToolRiskLevel.restricted;

  @override
  bool get idempotent => false;

  @override
  Duration get timeout => const Duration(seconds: 15);

  @override
  Map<String, Object?> get inputSchema => _closedObject(
    properties: const <String, Object?>{
      'operations': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'type': <String, Object?>{'type': 'string'},
            'target': <String, Object?>{'type': 'string'},
            'payload': <String, Object?>{'type': 'object'},
          },
          'required': <String>['type', 'target'],
          'additionalProperties': false,
        },
      },
      'label': <String, Object?>{'type': 'string'},
    },
    required: const <String>['operations'],
  );

  @override
  Map<String, Object?> get outputSchema => _closedObject(
    properties: const <String, Object?>{
      'revision': <String, Object?>{'type': 'integer'},
      'applied': <String, Object?>{'type': 'integer'},
      'operations': <String, Object?>{'type': 'array'},
    },
    required: const <String>['revision', 'applied'],
  );

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> arguments,
  ) async {
    context.cancel.throwIfCancelled();
    final raw = arguments['operations'];
    if (raw is! List || raw.isEmpty) {
      return const ToolResult.failure(
        code: ShadowErrorCode.toolInvalidArgs,
        message: 'operations must be a non-empty array',
      );
    }

    final operations = <EditOperation>[];
    for (final item in raw) {
      if (item is! Map) {
        return const ToolResult.failure(
          code: ShadowErrorCode.toolInvalidArgs,
          message: 'each operation must be an object',
        );
      }
      final type = item['type'];
      final target = item['target'];
      if (type is! String || target is! String) {
        return const ToolResult.failure(
          code: ShadowErrorCode.toolInvalidArgs,
          message: 'each operation requires string type and target',
        );
      }
      final payload = item['payload'];
      operations.add(
        EditOperation(
          type: type,
          target: target,
          payload: payload is Map
              ? payload.cast<String, Object?>()
              : const <String, Object?>{},
        ),
      );
    }

    final transaction = EditTransaction(
      operations: operations,
      label: arguments['label'] as String?,
      metadata: <String, Object?>{'origin': 'agent'},
    );

    try {
      final outcome = await _editing.apply(
        transaction,
        expectedRevision: context.revision,
      );
      return ToolResult.ok(
        data: <String, Object?>{
          'revision': outcome.revision,
          'applied': outcome.applied.length,
          'operations': outcome.applied
              .map((operation) => operation.type)
              .toList(growable: false),
        },
      );
    } on ShadowError catch (error) {
      return ToolResult.failure(
        code: error.code,
        message: error.message ?? 'Timeline edit failed',
        data: <String, Object?>{
          'details': error.details,
          'expected_revision': context.revision,
        },
      );
    }
  }
}