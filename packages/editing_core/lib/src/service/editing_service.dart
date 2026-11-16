import '../model/project_document.dart';
import '../model/range_ticks.dart';
import '../model/render_graph.dart';
import '../transaction/edit_outcome.dart';
import '../transaction/edit_transaction.dart';

/// Normative Editing Core port per Spec §9.3.
///
/// Responsible for:
/// - In-memory immutable ProjectDocument state.
/// - Atomic EditTransaction execution.
/// - Revision tracking and optimistic concurrency enforcement.
/// - Undo / redo stack management.
/// - Invariant validation (EDIT_INVALID_OPERATION).
abstract interface class EditingService {
  /// Current monotonic document revision number.
  int get revision;

  /// Current immutable document snapshot.
  ProjectDocument get currentDocument;

  /// Whether there are transactions available to undo.
  bool get canUndo;

  /// Whether there are transactions available to redo.
  bool get canRedo;

  /// Opens and loads a project from [path] (Deferred to Phase 2).
  Future<ProjectDocument> openProject(String path);

  /// Atomically applies an [EditTransaction] if [expectedRevision] matches [revision].
  ///
  /// Returns [EditSuccess] with the new document and bumped revision on success.
  /// Returns [EditFailure] with EDIT_REVISION_MISMATCH or EDIT_INVALID_OPERATION on failure.
  Future<EditOutcome> apply(
    EditTransaction transaction, {
    required int expectedRevision,
  });

  /// Undoes the last transaction if [expectedRevision] matches [revision].
  Future<EditOutcome> undo({required int expectedRevision});

  /// Redoes the last undone transaction if [expectedRevision] matches [revision].
  Future<EditOutcome> redo({required int expectedRevision});

  /// Flushes document state atomically to storage (Deferred to Phase 2).
  Future<void> save();

  /// Resolves the canonical RenderGraph for preview/rendering (Deferred to Phase 3).
  RenderGraph resolveGraph({
    required int revision,
    required RangeTicks range,
  });
}
