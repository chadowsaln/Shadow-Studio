import '../commands/edit_command.dart';
import '../error/shadow_error.dart';
import '../invariants/document_invariants.dart';
import '../model/project_document.dart';
import '../model/range_ticks.dart';
import '../model/render_graph.dart';
import '../transaction/edit_outcome.dart';
import '../transaction/edit_transaction.dart';
import 'editing_service.dart';

class _UndoEntry {
  final String transactionId;
  final String? description;
  final List<EditCommand> inverseCommands;
  final List<EditCommand> forwardCommands;

  const _UndoEntry({
    required this.transactionId,
    this.description,
    required this.inverseCommands,
    required this.forwardCommands,
  });
}

/// Standard in-memory implementation of [EditingService].
///
/// Guarantees:
/// - Atomic all-or-nothing transaction execution.
/// - Invariant enforcement with EDIT_INVALID_OPERATION before state commit.
/// - Optimistic concurrency via expectedRevision with EDIT_REVISION_MISMATCH.
/// - Append-only revision incrementing.
/// - Full undo/redo symmetry.
class DefaultEditingService implements EditingService {
  int _revision;
  ProjectDocument _currentDocument;

  final List<_UndoEntry> _undoStack = [];
  final List<_UndoEntry> _redoStack = [];

  DefaultEditingService({
    required ProjectDocument initialDocument,
    int initialRevision = 0,
  })  : _currentDocument = initialDocument,
        _revision = initialRevision {
    // Ensure initial document passes invariant checks
    DocumentInvariants.validate(_currentDocument);
  }

  @override
  int get revision => _revision;

  @override
  ProjectDocument get currentDocument => _currentDocument;

  @override
  bool get canUndo => _undoStack.isNotEmpty;

  @override
  bool get canRedo => _redoStack.isNotEmpty;

  int get undoStackDepth => _undoStack.length;

  int get redoStackDepth => _redoStack.length;

  @override
  Future<EditOutcome> apply(
    EditTransaction transaction, {
    required int expectedRevision,
  }) async {
    // 1. Check revision match (Spec §9.2 rule 3 & §14.3)
    if (expectedRevision != _revision) {
      return EditOutcome.failure(
        ShadowError.revisionMismatch(
          expected: expectedRevision,
          actual: _revision,
        ),
      );
    }

    // 2. Execute commands sequentially on draft document
    var draftDoc = _currentDocument;
    final executedInverses = <EditCommand>[];

    for (final command in transaction.commands) {
      try {
        final result = command.execute(draftDoc);
        draftDoc = result.document;
        executedInverses.add(result.inverse);
      } on ShadowError catch (e) {
        return EditOutcome.failure(e);
      } catch (e) {
        return EditOutcome.failure(
          ShadowError.invalidOperation(
            'Command ${command.name} failed: $e',
          ),
        );
      }
    }

    // 3. Enforce document invariants
    try {
      DocumentInvariants.validate(draftDoc);
    } on ShadowError catch (e) {
      return EditOutcome.failure(e);
    } catch (e) {
      return EditOutcome.failure(
        ShadowError.invalidOperation('Invariant check failed: $e'),
      );
    }

    // 4. Commit state transition atomically
    _currentDocument = draftDoc;
    _revision++;

    _undoStack.add(
      _UndoEntry(
        transactionId: transaction.id,
        description: transaction.description,
        inverseCommands: executedInverses.reversed.toList(),
        forwardCommands: transaction.commands.toList(),
      ),
    );

    // New edit clears redo stack (Spec §3.5.3)
    _redoStack.clear();

    return EditOutcome.success(
      document: _currentDocument,
      revision: _revision,
    );
  }

  @override
  Future<EditOutcome> undo({required int expectedRevision}) async {
    if (expectedRevision != _revision) {
      return EditOutcome.failure(
        ShadowError.revisionMismatch(
          expected: expectedRevision,
          actual: _revision,
        ),
      );
    }

    if (_undoStack.isEmpty) {
      return EditOutcome.failure(
        ShadowError.invalidOperation('Cannot undo: history is empty'),
      );
    }

    final entry = _undoStack.removeLast();
    var draftDoc = _currentDocument;
    final redoInverses = <EditCommand>[];

    for (final cmd in entry.inverseCommands) {
      try {
        final result = cmd.execute(draftDoc);
        draftDoc = result.document;
        redoInverses.add(result.inverse);
      } on ShadowError catch (e) {
        _undoStack.add(entry);
        return EditOutcome.failure(e);
      } catch (e) {
        _undoStack.add(entry);
        return EditOutcome.failure(
          ShadowError.invalidOperation('Undo failed executing ${cmd.name}: $e'),
        );
      }
    }

    try {
      DocumentInvariants.validate(draftDoc);
    } on ShadowError catch (e) {
      _undoStack.add(entry);
      return EditOutcome.failure(e);
    } catch (e) {
      _undoStack.add(entry);
      return EditOutcome.failure(
        ShadowError.invalidOperation('Undo invariant check failed: $e'),
      );
    }

    _currentDocument = draftDoc;
    _revision++;

    _redoStack.add(
      _UndoEntry(
        transactionId: entry.transactionId,
        description: entry.description,
        inverseCommands: redoInverses.reversed.toList(),
        forwardCommands: entry.inverseCommands.toList(),
      ),
    );

    return EditOutcome.success(
      document: _currentDocument,
      revision: _revision,
    );
  }

  @override
  Future<EditOutcome> redo({required int expectedRevision}) async {
    if (expectedRevision != _revision) {
      return EditOutcome.failure(
        ShadowError.revisionMismatch(
          expected: expectedRevision,
          actual: _revision,
        ),
      );
    }

    if (_redoStack.isEmpty) {
      return EditOutcome.failure(
        ShadowError.invalidOperation('Cannot redo: history is empty'),
      );
    }

    final entry = _redoStack.removeLast();
    var draftDoc = _currentDocument;
    final undoInverses = <EditCommand>[];

    for (final cmd in entry.inverseCommands) {
      try {
        final result = cmd.execute(draftDoc);
        draftDoc = result.document;
        undoInverses.add(result.inverse);
      } on ShadowError catch (e) {
        _redoStack.add(entry);
        return EditOutcome.failure(e);
      } catch (e) {
        _redoStack.add(entry);
        return EditOutcome.failure(
          ShadowError.invalidOperation('Redo failed executing ${cmd.name}: $e'),
        );
      }
    }

    try {
      DocumentInvariants.validate(draftDoc);
    } on ShadowError catch (e) {
      _redoStack.add(entry);
      return EditOutcome.failure(e);
    } catch (e) {
      _redoStack.add(entry);
      return EditOutcome.failure(
        ShadowError.invalidOperation('Redo invariant check failed: $e'),
      );
    }

    _currentDocument = draftDoc;
    _revision++;

    _undoStack.add(
      _UndoEntry(
        transactionId: entry.transactionId,
        description: entry.description,
        inverseCommands: undoInverses.reversed.toList(),
        forwardCommands: entry.inverseCommands.toList(),
      ),
    );

    return EditOutcome.success(
      document: _currentDocument,
      revision: _revision,
    );
  }

  @override
  Future<ProjectDocument> openProject(String path) {
    throw UnimplementedError('openProject is deferred to Phase 2 (local_storage)');
  }

  @override
  Future<void> save() {
    throw UnimplementedError('save is deferred to Phase 2 (local_storage)');
  }

  @override
  RenderGraph resolveGraph({
    required int revision,
    required RangeTicks range,
  }) {
    throw UnimplementedError('resolveGraph is deferred to Phase 3 (RenderGraph derivation)');
  }
}
