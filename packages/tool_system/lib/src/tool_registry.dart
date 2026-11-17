import 'package:shadow_contracts/shadow_contracts.dart';

class ToolRegistry {
  ToolRegistry({ToolSchemaValidator? schemaValidator})
    : _schemaValidator = schemaValidator ?? const ToolSchemaValidator(),
      _contractValidator = const ToolContractValidator();

  final Map<String, AgentTool> _tools = <String, AgentTool>{};
  final ToolSchemaValidator _schemaValidator;
  final ToolContractValidator _contractValidator;

  void register(AgentTool tool) {
    if (_tools.containsKey(tool.name)) {
      throw StateError('${ShadowErrorCode.toolDuplicateName}: ${tool.name}');
    }
    final errors = _contractValidator.validateDefinition(tool);
    if (errors.isNotEmpty) {
      throw StateError(
        '${ShadowErrorCode.toolSchemaInvalid}: ${tool.name}: ${errors.join('; ')}',
      );
    }
    // Ensure the declared input schema can validate an empty argument map when
    // no required fields are declared. This catches malformed schemas early.
    _schemaValidator.validate(
      schema: tool.inputSchema,
      arguments: const <String, Object?>{},
    );
    _tools[tool.name] = tool;
  }

  AgentTool? resolve(String name) => _tools[name];

  bool contains(String name) => _tools.containsKey(name);

  List<AgentTool> get all => List<AgentTool>.unmodifiable(_tools.values);
}
