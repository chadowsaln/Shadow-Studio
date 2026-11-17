import '../model/project_document.dart';

/// Result of executing a pure [EditCommand].
class CommandResult {
  /// The new immutable document produced by executing the command.
  final ProjectDocument document;

  /// The inverse command that restores the document to its exact state before execution.
  final EditCommand inverse;

  const CommandResult({
    required this.document,
    required this.inverse,
  });
}

/// A pure editing command.
///
/// Follows Spec §9.2 rule 4:
/// "Document is immutable; commands are pure functions Document -> Document + inverse."
abstract interface class EditCommand {
  /// Human-readable type or name of the command.
  String get name;

  /// Executes this command on [document], returning the new document and its exact inverse.
  ///
  /// Must NOT mutate [document].
  /// Throws [ShadowError.invalidOperation] if the command cannot be applied.
  CommandResult execute(ProjectDocument document);
}
