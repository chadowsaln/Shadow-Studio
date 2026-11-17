import 'dart:convert';

import 'package:shadow_contracts/shadow_contracts.dart';

/// Validates tool arguments against a closed JSON-schema subset.
/// Rejects unknown tools via registry; this rejects invalid args & additional properties.
class ToolSchemaValidator {
  const ToolSchemaValidator();

  ToolValidationResult validate({
    required Map<String, Object?> schema,
    required Map<String, Object?> arguments,
  }) {
    final errors = <String>[];
    _validateObject(schema, arguments, r'$', errors);
    if (errors.isEmpty) {
      return const ToolValidationResult.ok();
    }
    return ToolValidationResult.invalid(errors);
  }

  void _validateObject(
    Map<String, Object?> schema,
    Object? value,
    String path,
    List<String> errors,
  ) {
    final type = schema['type'];
    if (type == 'object') {
      if (value is! Map) {
        errors.add('$path: expected object');
        return;
      }
      final map = Map<String, Object?>.from(value);
      final props = (schema['properties'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
      final requiredList = (schema['required'] as List?)?.cast<Object?>() ?? const <Object?>[];
      final additional = schema['additionalProperties'];

      for (final req in requiredList) {
        final key = req?.toString();
        if (key != null && !map.containsKey(key)) {
          errors.add('$path.$key: required');
        }
      }
      for (final entry in map.entries) {
        if (!props.containsKey(entry.key)) {
          if (additional == false) {
            errors.add('$path.${entry.key}: additional property not allowed');
          }
          continue;
        }
        final propSchema = props[entry.key];
        if (propSchema is Map) {
          _validateObject(propSchema.cast<String, Object?>(), entry.value, '$path.${entry.key}', errors);
        }
      }
      return;
    }
    if (type == 'string') {
      if (value is! String) errors.add('$path: expected string');
      return;
    }
    if (type == 'integer') {
      if (value is! int) errors.add('$path: expected integer');
      final min = schema['minimum'];
      final max = schema['maximum'];
      if (value is int && min is num && value < min.toInt()) errors.add('$path: below minimum');
      if (value is int && max is num && value > max.toInt()) errors.add('$path: above maximum');
      return;
    }
    if (type == 'number') {
      if (value is! num) errors.add('$path: expected number');
      return;
    }
    if (type == 'boolean') {
      if (value is! bool) errors.add('$path: expected boolean');
      return;
    }
    if (type == 'array') {
      if (value is! List) {
        errors.add('$path: expected array');
        return;
      }
      final items = schema['items'];
      if (items is Map) {
        for (var i = 0; i < value.length; i++) {
          _validateObject(items.cast<String, Object?>(), value[i], '$path[$i]', errors);
        }
      }
      return;
    }
    // If type omitted, accept (defensive) but still enforce closed object when declared.
  }
}

class ToolValidationResult {
  const ToolValidationResult._(this.isValid, this.errors);
  const ToolValidationResult.ok() : this._(true, const <String>[]);
  const ToolValidationResult.invalid(List<String> errors) : this._(false, errors);

  final bool isValid;
  final List<String> errors;

  Map<String, Object?> toJson() => {'valid': isValid, 'errors': errors};
}
