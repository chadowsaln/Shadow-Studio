import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:shadow_permissions/permissions.dart' as perm;

/// Thin adapter over the single canonical path validator.
///
/// Kept for the tool-system API surface; the implementation lives in
/// `shadow_permissions` so the tool pipeline and the permission engine cannot
/// drift into two different escape checks.
class WorkspacePathValidator {
  const WorkspacePathValidator();

  Future<void> validateWithinWorkspace({
    required String candidatePath,
    required String workspaceRoot,
    required bool mustExist,
    bool resolveSymlinks = true,
  }) async {
    try {
      await const perm.PathValidator().assertWithinWorkspace(
        targetPath: candidatePath,
        workspaceRoot: workspaceRoot,
        mustExist: mustExist,
      );
    } on perm.PathSecurityException catch (e) {
      throw ToolPathException(e.message, code: e.code);
    }
  }
}

class ToolPathException implements Exception {
  ToolPathException(this.message, {this.code = ShadowErrorCode.permPathEscape});

  final String message;
  final String code;

  @override
  String toString() => message;
}
