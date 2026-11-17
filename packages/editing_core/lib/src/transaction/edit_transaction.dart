import 'package:meta/meta.dart';

import '../commands/edit_command.dart';
import '../uuid/uuid_v7.dart';

/// Atomic batch of editing commands representing a single undo/redo step and revision bump.
///
/// Follows Spec §9.2 rule 2 & §3.5.2:
/// "Every change is an atomic EditTransaction = one revision = one undo step."
@immutable
class EditTransaction {
  final String id;
  final String? description;
  final List<EditCommand> commands;
  final String origin; // 'ui', 'ai', 'import', 'system'

  EditTransaction({
    String? id,
    this.description,
    required Iterable<EditCommand> commands,
    this.origin = 'ui',
  })  : id = id ?? UuidV7.generate(),
        commands = List.unmodifiable(commands.toList());

  /// Convenience constructor for a transaction with a single command.
  factory EditTransaction.single(
    EditCommand command, {
    String? description,
    String origin = 'ui',
  }) {
    return EditTransaction(
      description: description ?? command.name,
      commands: [command],
      origin: origin,
    );
  }

  @override
  String toString() =>
      'EditTransaction(id: $id, desc: "$description", commands: ${commands.length}, origin: $origin)';
}
