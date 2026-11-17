/// Durable, crash-safe project SQLite persistence and index for Shadow Studio.
///
/// Implements:
/// - V2-D9: Atomic save (`.part` -> `fsync` -> `rename`).
/// - V2-D11: `.ssproj` as source of truth, app index DB as rebuildable cache.
/// - Spec §14.3 error model: `STORE_CORRUPT`, `STORE_DISK_FULL`.
/// - Forward-only versioned schema migrations.
library local_storage;

export 'src/database/schema_migrations.dart';
export 'src/database/sqlite_project_file.dart';
export 'src/error/storage_error.dart';
export 'src/model/project_file_data.dart';
export 'src/model/project_index_entry.dart';
export 'src/model/storage_models.dart';
export 'src/model/stored_edit_op.dart';
export 'src/repository/storage_repositories.dart';
export 'src/service/atomic_saver.dart';
export 'src/service/project_file_storage.dart';
export 'src/service/project_index_database.dart';

export 'src/local_database.dart';
export 'src/session_memory_repository.dart';
export 'src/task_memory_repository.dart';
export 'src/checkpoint_store.dart';
