import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// Worker script executed in a separate process to test abrupt mid-save termination.
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Missing target path argument');
    exit(1);
  }

  final targetPath = args[0];
  final partPath = '$targetPath.part';

  // Open .part file and create uncommitted/in-progress SQLite database
  final db = sqlite3.open(partPath);
  db.execute('''
    CREATE TABLE project_state (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      revision INTEGER NOT NULL,
      schema_version INTEGER NOT NULL,
      document_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
  ''');
  db.execute('''
    INSERT INTO project_state VALUES (
      'mid-save-killed', 'Killed Project', 99, 2, '{"incomplete":true}',
      '2026-11-17T00:00:00Z', '2026-11-17T00:00:00Z'
    );
  ''');
  db.close();

  // Signal parent that .part is on disk, then wait to be killed
  stdout.writeln('PART_WRITTEN');
  stdout.flush();

  // Hang until SIGKILL arrives
  while (true) {
    sleep(const Duration(milliseconds: 100));
  }
}
