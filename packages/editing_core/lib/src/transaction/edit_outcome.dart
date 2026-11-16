import 'package:meta/meta.dart';

import '../error/shadow_error.dart';
import '../model/project_document.dart';

/// Outcome of applying, undoing, or redoing an [EditTransaction] on [EditingService].
///
/// Sealed hierarchy supporting functional pattern matching:
/// - [EditSuccess]: transaction applied, contains new document and incremented revision.
/// - [EditFailure]: transaction rejected or failed invariants, contains [ShadowError].
@immutable
sealed class EditOutcome {
  const EditOutcome();

  bool get isSuccess;
  bool get isFailure => !isSuccess;

  ProjectDocument? get document;
  int? get revision;
  ShadowError? get error;

  factory EditOutcome.success({
    required ProjectDocument document,
    required int revision,
  }) = EditSuccess;

  factory EditOutcome.failure(ShadowError error) = EditFailure;
}

final class EditSuccess extends EditOutcome {
  @override
  final ProjectDocument document;

  @override
  final int revision;

  const EditSuccess({
    required this.document,
    required this.revision,
  });

  @override
  bool get isSuccess => true;

  @override
  ShadowError? get error => null;

  @override
  String toString() => 'EditSuccess(revision: $revision, document: $document)';
}

final class EditFailure extends EditOutcome {
  @override
  final ShadowError error;

  const EditFailure(this.error);

  @override
  bool get isSuccess => false;

  @override
  ProjectDocument? get document => null;

  @override
  int? get revision => null;

  @override
  String toString() => 'EditFailure($error)';
}
