import 'dart:convert';

import 'package:local_storage/local_storage.dart';

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
/// - Durable project file persistence on top of [ProjectFileStorage].
class DefaultEditingService implements EditingService {
  int _revision;
  ProjectDocument _currentDocument;
  String? _projectFilePath;
  final ProjectFileStorage _storage;

  final List<_UndoEntry> _undoStack = [];
  final List<_UndoEntry> _redoStack = [];
  final List<StoredEditOp> _committedOps = [];

  DefaultEditingService({
    required ProjectDocument initialDocument,
    int initialRevision = 0,
    String? projectFilePath,
    ProjectFileStorage storage = const ProjectFileStorage(),
  })  : _currentDocument = initialDocument,
        _revision = initialRevision,
        _projectFilePath = projectFilePath,
        _storage = storage {
    // Ensure initial document passes invariant checks
    DocumentInvariants.validate(_currentDocument);
  }

  /// Opens an existing project file at [path] and returns an initialized [DefaultEditingService].
  static Future<DefaultEditingService> open(
    String path, {
    ProjectFileStorage storage = const ProjectFileStorage(),
  }) async {
    final (projectData, ops) = await storage.openProjectFile(path);
    final docMap = jsonDecode(projectData.documentJson) as Map<String, dynamic>;
    final doc = ProjectDocument.fromJson(docMap);
    DocumentInvariants.validate(doc);

    final service = DefaultEditingService(
      initialDocument: doc,
      initialRevision: projectData.revision,
      projectFilePath: path,
      storage: storage,
    );
    service._committedOps.addAll(ops);
    return service;
  }

  @override
  int get revision => _revision;

  @override
  ProjectDocument get currentDocument => _currentDocument;

  @override
  String? get projectFilePath => _projectFilePath;

  /// Internal access to ops log for testing and verification.
  List<StoredEditOp> get committedOps => List.unmodifiable(_committedOps);

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

    final now = DateTime.now().toUtc().toIso8601String();
    for (var i = 0; i < transaction.commands.length; i++) {
      final cmd = transaction.commands[i];
      final inv = executedInverses[i];
      _committedOps.add(
        StoredEditOp(
          projectId: _currentDocument.id,
          revision: _revision,
          batchId: transaction.id,
          opType: cmd.name,
          payloadJson: jsonEncode({'command': cmd.toString()}),
          inverseJson: jsonEncode({'inverse': inv.toString()}),
          origin: transaction.origin,
          createdAt: now,
        ),
      );
    }

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
  Future<ProjectDocument> openProject(String path) async {
    try {
      final (projectData, ops) = await _storage.openProjectFile(path);
      final docMap = jsonDecode(projectData.documentJson) as Map<String, dynamic>;
      final doc = ProjectDocument.fromJson(docMap);
      DocumentInvariants.validate(doc);

      _currentDocument = doc;
      _revision = projectData.revision;
      _projectFilePath = path;
      _undoStack.clear();
      _redoStack.clear();
      _committedOps.clear();
      _committedOps.addAll(ops);

      return _currentDocument;
    } on StorageError catch (e) {
      throw ShadowError(
        code: e.code,
        category: e.category,
        retryable: e.retryable,
        message: e.message,
        details: e.details,
      );
    }
  }

  @override
  Future<void> save() async {
    final path = _projectFilePath;
    if (path == null) {
      throw ShadowError.invalidOperation(
        'Cannot save: no project file path specified',
      );
    }
    await saveTo(path);
  }

  /// Saves the project to [targetPath] atomically and updates [projectFilePath].
  Future<void> saveTo(String targetPath) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final projectData = ProjectFileData(
        projectId: _currentDocument.id,
        name: _currentDocument.name,
        schemaVersion: SchemaMigrations.currentVersion,
        revision: _revision,
        documentJson: jsonEncode(_currentDocument.toJson()),
        createdAt: now,
        updatedAt: now,
      );

      await _storage.saveProjectFile(targetPath, projectData, ops: _committedOps);
      _projectFilePath = targetPath;
    } on StorageError catch (e) {
      throw ShadowError(
        code: e.code,
        category: e.category,
        retryable: e.retryable,
        message: e.message,
        details: e.details,
      );
    }
  }

  @override
  RenderGraph resolveGraph({
    required int revision,
    required RangeTicks range,
  }) {
    throw UnimplementedError('resolveGraph is deferred to Phase 3 (RenderGraph derivation)');
  }
}
