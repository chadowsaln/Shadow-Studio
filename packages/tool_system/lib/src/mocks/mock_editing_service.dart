import 'dart:io';

import 'package:shadow_contracts/shadow_contracts.dart';

import '../editing_tool_helpers.dart';

class MockProjectDocument implements ProjectDocument {
  MockProjectDocument(this.id, this._revision);
  @override
  final String id;
  int _revision;
  @override
  int get revision => _revision;
  void bump(int to) => _revision = to;
}

/// In-memory mock [EditingService] for isolated testing. No native/media engine.
class MockEditingService implements EditingService {
  MockEditingService({this.projectId = 'proj_1', int initialRevision = 0})
      : _revision = initialRevision,
        _document = MockProjectDocument('proj_1', initialRevision);

  int _revision;
  final MockProjectDocument _document;
  final String projectId;
  String? savedPath;
  final List<EditTransaction> applied = <EditTransaction>[];
  final List<EditTransaction> undone = <EditTransaction>[];

  @override
  int get revision => _revision;

  @override
  Future<ProjectDocument> openProject(String path) async {
    savedPath = path;
    return _document;
  }

  @override
  Future<EditOutcome> apply(EditTransaction transaction, {required int expectedRevision}) async {
    if (expectedRevision != _revision) {
      throw StateError('${ShadowErrorCode.editRevisionMismatch}: expected $expectedRevision got $_revision');
    }
    _revision += 1;
    _document.bump(_revision);
    applied.add(transaction);
    undone.clear();
    return EditOutcome(revision: _revision, applied: transaction.operations);
  }

  @override
  Future<EditOutcome> undo({required int expectedRevision}) async {
    if (expectedRevision != _revision) {
      throw StateError('${ShadowErrorCode.editRevisionMismatch}: expected $expectedRevision got $_revision');
    }
    if (applied.isEmpty) {
      throw StateError('${ShadowErrorCode.editInvalidOperation}: nothing to undo');
    }
    final tx = applied.removeLast();
    undone.add(tx);
    _revision += 1;
    _document.bump(_revision);
    return EditOutcome(revision: _revision, applied: const <EditOperation>[]);
  }

  @override
  Future<EditOutcome> redo({required int expectedRevision}) async {
    if (expectedRevision != _revision) {
      throw StateError('${ShadowErrorCode.editRevisionMismatch}: expected $expectedRevision got $_revision');
    }
    if (undone.isEmpty) {
      throw StateError('${ShadowErrorCode.editInvalidOperation}: nothing to redo');
    }
    final tx = undone.removeLast();
    applied.add(tx);
    _revision += 1;
    _document.bump(_revision);
    return EditOutcome(revision: _revision, applied: tx.operations);
  }

  @override
  Future<void> save() async {
    savedPath ??= 'unsaved.ssproj';
  }

  @override
  Future<Map<String, Object?>> resolveGraph({required int revision, required RangeTicks range}) async {
    return <String, Object?>{'revision': revision, 'range': range.toJson(), 'tracks': <Object?>[]};
  }
}

class MockProjectLifecycleService implements ProjectLifecycleService {
  MockProjectLifecycleService({MockEditingService? editing})
      : _editing = editing ?? MockEditingService();

  final MockEditingService _editing;
  final Map<String, String> created = <String, String>{}; // name -> path

  @override
  EditingService get editing => _editing;

  @override
  Future<({String projectPath, String projectId, int revision})> createProject({required String workspaceRoot, required String name}) async {
    final dir = Directory(workspaceRoot);
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = '${dir.path}${Platform.pathSeparator}$name.ssproj';
    created[name] = path;
    await _editing.openProject(path);
    return (projectPath: path, projectId: _editing.projectId, revision: _editing.revision);
  }

  @override
  Future<ProjectDocument> openProject({required String workspaceRoot, required String projectPath}) async {
    return _editing.openProject(projectPath);
  }
}

class MockMediaMetadataService implements MediaMetadataService {
  final Map<String, Map<String, Object?>> cache = <String, Map<String, Object?>>{};
  List<Map<String, Object?>> scanned = const <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>> getCachedMetadata(String path) async {
    if (cache.containsKey(path)) return cache[path]!;
    final f = File(path);
    if (await f.exists()) {
      final stat = await f.stat();
      return <String, Object?>{'path': path, 'found': true, 'sizeBytes': stat.size, 'cached': false};
    }
    return <String, Object?>{'path': path, 'found': false};
  }

  @override
  Future<List<Map<String, Object?>>> scanMedia({required String workspaceRoot, String? directory}) async {
    if (scanned.isNotEmpty) return scanned;
    return const FileSystemMediaMetadataService().scanMedia(workspaceRoot: workspaceRoot, directory: directory);
  }
}
