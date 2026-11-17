/// Resolves a tool argument that names a file against the task workspace.
///
/// Tool arguments are workspace-relative by contract; absolute paths (POSIX or
/// Windows) are passed through untouched. Containment is enforced separately by
/// the executor's workspace path validator.
String resolveWorkspacePath(String raw, String workspaceRoot) {
  if (raw.startsWith('/') || raw.startsWith('\\\\')) return raw;
  if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(raw)) return raw;
  return '${workspaceRoot.replaceAll(RegExp(r'[/\\]+$'), '')}/$raw';
}
