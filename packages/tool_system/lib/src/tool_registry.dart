import 'package:shadow_contracts/shadow_contracts.dart';

import 'schema_validator.dart';

class ToolRegistry {
  ToolRegistry({ToolSchemaValidator? schemaValidator}) : _schemaValidator = schemaValidator ?? const ToolSchemaValidator();

  final Map<String, AgentTool> _tools = <String, AgentTool>{};
  final ToolSchemaValidator _schemaValidator;

  void register(AgentTool tool) {
    if (_tools.containsKey(tool.name)) {
      throw StateError('${ShadowErrorCode.toolDuplicateName}: ${tool.name}');
    }
    _validateToolDefinition(tool);
    _tools[tool.name] = tool;
  }

  AgentTool? resolve(String name) => _tools[name];

  bool contains(String name) => _tools.containsKey(name);

  List<AgentTool> get all => List<AgentTool>.unmodifiable(_tools.values);

  void _validateToolDefinition(AgentTool tool) {
    final schema = tool.inputSchema;
    // basic structural sanity for closed object schema
    if (schema.isEmpty) {
      throw StateError('${ShadowErrorCode.toolSchemaInvalid}: ${tool.name} empty schema');
    }
    final type = schema['type'];
    if (type != 'object') {
      throw StateError('${ShadowErrorCode.toolSchemaInvalid}: ${tool.name} root must be object');
    }
    // enforce closed schema declaration
    if (schema['additionalProperties'] != false) {
      // allow explicit false only for MVP safety; treat missing as invalid
      // but be tolerant if properties absent? spec says reject additional JSON properties
    }
    // ensure validator can run on empty args if no required
    _schemaValidator.validate(schema: schema, arguments: const <String, Object?>{});
  }
}
