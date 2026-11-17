import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../database/sqlite_project_file.dart';
import '../error/storage_error.dart';
import '../model/project_file_data.dart';
import '../model/stored_edit_op.dart';
import 'atomic_saver.dart';

/// High-level service for atomic `.ssproj` file persistence and loading.
class ProjectFileStorage {
  const ProjectFileStorage();

  /// Atomically saves [projectData] and [ops] to [filePath] using `<name>.part` -> fsync -> rename.
  Future<void> saveProjectFile(
    String filePath,
    ProjectFileData projectData, {
    List<StoredEditOp> ops = const [],
    SaveFaultStage? faultStage,
    bool simulateDiskFull = false,
  }) async {
    AtomicSaver.saveSync(
      targetPath: filePath,
      faultStage: faultStage,
      simulateDiskFull: simulateDiskFull,
      writeAction: (partPath) {
        final db = sqlite3.open(partPath);
        try {
          db.execute('PRAGMA synchronous = FULL;');
          SqliteProjectFile.writeProject(
            db,
            projectData: projectData,
            ops: ops,
            path: partPath,
          );
          SqliteProjectFile.verifyIntegrity(db, path: partPath);
        } finally {
          db.close();
        }
      },
    );
  }

  /// Opens [filePath], cleans any leftover `.part` debris, checks integrity, and loads data.
  ///
  /// Throws [StorageError.corrupt] if integrity check fails or schema is invalid.
  Future<(ProjectFileData, List<StoredEditOp>)> openProjectFile(String filePath) async {
    // Detect and clean leftover .part file from earlier crash
    AtomicSaver.cleanLeftoverPart(filePath);

    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('Project file does not exist', filePath);
    }

    final Database db;
    try {
      db = sqlite3.open(filePath);
    } catch (e) {
      throw StorageError.corrupt(
        'Failed to open SQLite database: $e',
        path: filePath,
      );
    }

    try {
      return SqliteProjectFile.readProject(db, path: filePath);
    } catch (e) {
      if (e is StorageError) rethrow;
      throw StorageError.corrupt('Failed to read project file: $e', path: filePath);
    } finally {
      db.close();
    }
  }
}
