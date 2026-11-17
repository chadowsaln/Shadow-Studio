import 'package:meta/meta.dart';
import 'package:shadow_contracts/shadow_contracts.dart';

/// A fully resolved external command. There is deliberately no single
/// `command` string: execution must use an executable plus an argument list,
/// never a shell.
@immutable
class ShellCommand {
  const ShellCommand({
    required this.executable,
    this.arguments = const <String>[],
    this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;

  @override
  String toString() =>
      'ShellCommand(executable: $executable, '
      'arguments: ${arguments.length}, cwd: ${workingDirectory ?? "-"})';
}

@immutable
class ShellViolation {
  const ShellViolation(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'ShellViolation($code): $message';
}

/// Validates external command invocations before anything is spawned.
///
/// Controls:
/// * deny-by-default executable allowlist (basename match);
/// * no shell command strings (`command: "ffmpeg -i ..."` is rejected);
/// * no shell metacharacters in executable or arguments (defense in depth even
///   though the engine never invokes a shell);
/// * no NUL/newline/control characters;
/// * bounded argument count/length;
/// * working directory must be inside the workspace (checked by the manager,
///   which owns the workspace root).
class ShellCommandGuard {
  const ShellCommandGuard({
    this.allowedExecutables = defaultAllowedExecutables,
    this.maxArguments = 64,
    this.maxArgumentLength = 4096,
  });

  /// Media-app processes only. Extend explicitly for new engines.
  static const Set<String> defaultAllowedExecutables = <String>{
    'ffmpeg',
    'ffprobe',
    'mediainfo',
  };

  final Set<String> allowedExecutables;
  final int maxArguments;
  final int maxArgumentLength;

  static final RegExp _shellMetacharacters = RegExp(r'[;&|$`><\r\n]');
  static final RegExp _controlChars = RegExp(r'[\u0000-\u001F\u007F]');
  static final RegExp _windowsAbsolute = RegExp(r'^[A-Za-z]:[\\/]');

  /// Tool names that spawn external processes. Matches aliases such as
  /// `run_shell`, `execute_command`, `spawn_process`, `cmd`.
  static final RegExp _shellToolPattern = RegExp(
    r'(^|_)(shell|sh|exec|execute|executable|command|cmd|process|spawn|subprocess|terminal)($|_)',
    caseSensitive: false,
  );

  static bool isShellTool(String toolName) {
    final snake = toolName
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]}_${m[2]}',
        )
        .toLowerCase();
    return _shellToolPattern.hasMatch(snake);
  }

  /// Builds a [ShellCommand] from untrusted tool arguments, or a violation when
  /// the shape is unsafe. Accepts:
  /// * `{"executable": "ffmpeg", "args": ["-i", "in.mp4"]}`
  /// * `{"command": "ffmpeg", "args": [...]}`  (single token only)
  static ShellCommandOrViolation fromToolArguments(
    Map<String, Object?> arguments,
  ) {
    final executableValue = arguments['executable'] ?? arguments['command'];
    if (executableValue is! String || executableValue.trim().isEmpty) {
      return const ShellCommandOrViolation.violation(
        ShellViolation(
          ShadowErrorCode.permShellBlocked,
          'Shell tool call must declare an executable',
        ),
      );
    }

    // A `command` string containing whitespace implies shell parsing.
    if (arguments['executable'] == null &&
        RegExp(r'\s').hasMatch(executableValue.trim())) {
      return const ShellCommandOrViolation.violation(
        ShellViolation(
          ShadowErrorCode.permShellBlocked,
          'Shell command strings are not allowed; pass executable + args',
        ),
      );
    }

    final rawArgs = arguments['args'] ?? arguments['arguments'];
    final args = <String>[];
    if (rawArgs != null) {
      if (rawArgs is! List) {
        return const ShellCommandOrViolation.violation(
          ShellViolation(
            ShadowErrorCode.permShellBlocked,
            'Shell arguments must be a list of strings',
          ),
        );
      }
      for (final raw in rawArgs) {
        if (raw is! String) {
          return const ShellCommandOrViolation.violation(
            ShellViolation(
              ShadowErrorCode.permShellBlocked,
              'Shell arguments must be strings',
            ),
          );
        }
        args.add(raw);
      }
    }

    final cwd = arguments['workingDirectory'] ?? arguments['cwd'];
    if (cwd != null && cwd is! String) {
      return const ShellCommandOrViolation.violation(
        ShellViolation(
          ShadowErrorCode.permShellBlocked,
          'workingDirectory must be a string',
        ),
      );
    }

    return ShellCommandOrViolation.command(
      ShellCommand(
        executable: executableValue,
        arguments: args,
        workingDirectory: cwd as String?,
      ),
    );
  }

  List<ShellViolation> validate(ShellCommand command) {
    final violations = <ShellViolation>[];
    final executable = command.executable;

    if (executable.trim().isEmpty) {
      violations.add(
        const ShellViolation(
          ShadowErrorCode.permShellBlocked,
          'Executable is empty',
        ),
      );
    }
    if (_controlChars.hasMatch(executable)) {
      violations.add(
        const ShellViolation(
          ShadowErrorCode.permShellBlocked,
          'Executable contains control characters',
        ),
      );
    }
    if (_shellMetacharacters.hasMatch(executable)) {
      violations.add(
        const ShellViolation(
          ShadowErrorCode.permShellBlocked,
          'Executable contains shell metacharacters',
        ),
      );
    }
    if (executable != executable.trim()) {
      violations.add(
        const ShellViolation(
          ShadowErrorCode.permShellBlocked,
          'Executable must not have surrounding whitespace',
        ),
      );
    }

    final normalized = executable.replaceAll(r'\', '/');
    final segments = normalized.split('/');
    if (segments.contains('..')) {
      violations.add(
        const ShellViolation(
          ShadowErrorCode.permShellBlocked,
          'Executable path traversal is not allowed',
        ),
      );
    }
    final base = segments.isEmpty ? executable : segments.last;
    if (!allowedExecutables.contains(base)) {
      violations.add(
        ShellViolation(
          ShadowErrorCode.permShellBlocked,
          'Executable "$base" is not allowlisted',
        ),
      );
    }

    if (command.arguments.length > maxArguments) {
      violations.add(
        ShellViolation(
          ShadowErrorCode.permShellBlocked,
          'Too many arguments (max $maxArguments)',
        ),
      );
    }
    for (final arg in command.arguments) {
      if (arg.length > maxArgumentLength) {
        violations.add(
          const ShellViolation(
            ShadowErrorCode.permShellBlocked,
            'Argument exceeds maximum length',
          ),
        );
        break;
      }
      if (_controlChars.hasMatch(arg)) {
        violations.add(
          const ShellViolation(
            ShadowErrorCode.permShellBlocked,
            'Argument contains control characters',
          ),
        );
        break;
      }
      if (_shellMetacharacters.hasMatch(arg)) {
        violations.add(
          const ShellViolation(
            ShadowErrorCode.permShellBlocked,
            'Argument contains shell metacharacters',
          ),
        );
        break;
      }
    }

    final cwd = command.workingDirectory;
    if (cwd != null && (cwd.trim().isEmpty || _controlChars.hasMatch(cwd))) {
      violations.add(
        const ShellViolation(
          ShadowErrorCode.permShellBlocked,
          'Invalid working directory',
        ),
      );
    }
    if (cwd != null &&
        (_windowsAbsolute.hasMatch(cwd) || cwd.startsWith('/'))) {
      // Absolute working directories are allowed only after workspace
      // containment is verified by PermissionManager; nothing to add here.
    }

    return violations;
  }

  /// Returns null when safe, otherwise a violation describing the first breach.
  ShellViolation? firstViolation(ShellCommand command) {
    final violations = validate(command);
    return violations.isEmpty ? null : violations.first;
  }
}

/// Result of parsing untrusted shell tool arguments.
class ShellCommandOrViolation {
  const ShellCommandOrViolation.command(this.command) : violation = null;

  const ShellCommandOrViolation.violation(this.violation) : command = null;

  final ShellCommand? command;
  final ShellViolation? violation;

  bool get isCommand => command != null;
}
