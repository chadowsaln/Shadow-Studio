import 'dart:io';

import 'package:shadow_contracts/shadow_contracts.dart';

import 'workspace_paths.dart';

import 'editing_tool_helpers.dart';

const _closedObject = false;

Map<String, Object?> _objectSchema({
  required Map<String, Object?> properties,
  List<String> required = const <String>[],
}) => <String, Object?>{
  'type': 'object',
  'properties': properties,
  'required': required,
  'additionalProperties': _closedObject,
};

class GetSystemInfoTool implements AgentTool {
  GetSystemInfoTool(this._env);
  final EnvironmentInfoService _env;

  @override
  String get name => 'get_system_info';
  @override
  String get description =>
      'Returns local system information from the environment profile.';
  @override
  ToolRiskLevel get riskLevel => ToolRiskLevel.safe;
  @override
  bool get idempotent => true;
  @override
  Duration get timeout => const Duration(seconds: 5);
  @override
  Map<String, Object?> get inputSchema =>
      _objectSchema(properties: const {}, required: const []);
  @override
  Map<String, Object?> get outputSchema => _objectSchema(
    properties: const {
      'info': <String, Object?>{'type': 'object'},
    },
    required: const ['info'],
  );

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> arguments,
  ) async {
    context.cancel.throwIfCancelled();
    final info = await _env.getSystemInfo();
    return ToolResult(success: true, data: <String, Object?>{'info': info});
  }
}

class InspectCapabilitiesTool implements AgentTool {
  InspectCapabilitiesTool(this._env);
  final EnvironmentInfoService _env;

  @override
  String get name => 'inspect_capabilities';
  @override
  String get description =>
      'Returns environment capabilities (codecs/engine/GPU availability as known to tool layer).';
  @override
  ToolRiskLevel get riskLevel => ToolRiskLevel.safe;
  @override
  bool get idempotent => true;
  @override
  Duration get timeout => const Duration(seconds: 5);
  @override
  Map<String, Object?> get inputSchema =>
      _objectSchema(properties: const {}, required: const []);
  @override
  Map<String, Object?> get outputSchema => _objectSchema(
    properties: const {
      'capabilities': <String, Object?>{'type': 'object'},
    },
    required: const ['capabilities'],
  );

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> arguments,
  ) async {
    context.cancel.throwIfCancelled();
    final caps = await _env.inspectCapabilities();
    return ToolResult(
      success: true,
      data: <String, Object?>{'capabilities': caps},
    );
  }
}

class ListFilesTool implements AgentTool {
  const ListFilesTool();

  @override
  String get name => 'list_files';
  @override
  String get description =>
      'Lists files and directories inside workspace (non-recursive by default).';
  @override
  ToolRiskLevel get riskLevel => ToolRiskLevel.safe;
  @override
  bool get idempotent => true;
  @override
  Duration get timeout => const Duration(seconds: 10);
  @override
  Map<String, Object?> get inputSchema => _objectSchema(
    properties: const <String, Object?>{
      'path': <String, Object?>{'type': 'string'},
      'recursive': <String, Object?>{'type': 'boolean'},
    },
  );
  @override
  Map<String, Object?> get outputSchema => _objectSchema(
    properties: const {
      'entries': <String, Object?>{'type': 'array'},
    },
  );

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> arguments,
  ) async {
    context.cancel.throwIfCancelled();
    final rawPath = arguments['path'] as String?;
    final dir = rawPath == null || rawPath.isEmpty
        ? Directory(context.workspaceRoot)
        : Directory(resolveWorkspacePath(rawPath, context.workspaceRoot));
    final recursive = arguments['recursive'] as bool? ?? false;
    if (!await dir.exists()) {
      return const ToolResult(
        success: false,
        errorCode: 'TOOL_INVALID_ARGS',
        errorMessage: 'Directory not found',
      );
    }
    final entries = <Map<String, Object?>>[];
    await for (final ent in dir.list(
      recursive: recursive,
      followLinks: false,
    )) {
      context.cancel.throwIfCancelled();
      final stat = await ent.stat();
      entries.add(<String, Object?>{
        'path': ent.path,
        'name': ent.uri.pathSegments.isNotEmpty
            ? ent.uri.pathSegments.last
            : ent.path,
        'type': ent is Directory ? 'directory' : 'file',
        'sizeBytes': ent is File ? stat.size : null,
      });
      if (entries.length >= 500) break; // safety bound
    }
    entries.sort((a, b) => ('${a['name']}').compareTo('${b['name']}'));
    return ToolResult(
      success: true,
      data: <String, Object?>{'entries': entries},
    );
  }
}

class ScanMediaTool implements AgentTool {
  ScanMediaTool(this._media);
  final MediaMetadataService _media;

  @override
  String get name => 'scan_media';
  @override
  String get description =>
      'Scans for media files in a workspace directory (extensions + lightweight file info).';
  @override
  ToolRiskLevel get riskLevel => ToolRiskLevel.safe;
  @override
  bool get idempotent => true;
  @override
  Duration get timeout => const Duration(seconds: 30);
  @override
  Map<String, Object?> get inputSchema => _objectSchema(
    properties: const <String, Object?>{
      'directory': <String, Object?>{'type': 'string'},
    },
  );
  @override
  Map<String, Object?> get outputSchema => _objectSchema(
    properties: const {
      'media': <String, Object?>{'type': 'array'},
    },
  );

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> arguments,
  ) async {
    context.cancel.throwIfCancelled();
    final dir = arguments['directory'] as String?;
    final items = await _media.scanMedia(
      workspaceRoot: context.workspaceRoot,
      directory: dir,
    );
    return ToolResult(
      success: true,
      data: <String, Object?>{'media': items, 'count': items.length},
    );
  }
}

class GetMetadataTool implements AgentTool {
  GetMetadataTool(this._media);
  final MediaMetadataService _media;

  @override
  String get name => 'get_metadata';
  @override
  String get description =>
      'Returns cached/probed metadata for a media file if available; does not invoke native engines.';
  @override
  ToolRiskLevel get riskLevel => ToolRiskLevel.safe;
  @override
  bool get idempotent => true;
  @override
  Duration get timeout => const Duration(seconds: 10);
  @override
  Map<String, Object?> get inputSchema => _objectSchema(
    properties: const <String, Object?>{
      'path': <String, Object?>{'type': 'string'},
    },
    required: const ['path'],
  );
  @override
  Map<String, Object?> get outputSchema => _objectSchema(
    properties: const {
      'metadata': <String, Object?>{'type': 'object'},
    },
  );

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> arguments,
  ) async {
    context.cancel.throwIfCancelled();
    final path = arguments['path'] as String;
    final meta = await _media.getCachedMetadata(path);
    if (meta == null) {
      return ToolResult(
        success: false,
        errorCode: ShadowErrorCode.mediaAssetMissing,
        errorMessage: 'Metadata not available',
      );
    }
    if (meta['found'] == false) {
      return ToolResult(
        success: false,
        errorCode: ShadowErrorCode.mediaAssetMissing,
        errorMessage: 'Media file not found',
        data: meta,
      );
    }
    return ToolResult(success: true, data: <String, Object?>{'metadata': meta});
  }
}

class CreateProjectTool implements AgentTool {
  CreateProjectTool(this._projects);
  final ProjectLifecycleService _projects;

  @override
  String get name => 'create_project';
  @override
  String get description => 'Creates a new project inside the workspace.';
  @override
  ToolRiskLevel get riskLevel => ToolRiskLevel.restricted;
  @override
  bool get idempotent => true;
  @override
  Duration get timeout => const Duration(seconds: 15);
  @override
  Map<String, Object?> get inputSchema => _objectSchema(
    properties: const <String, Object?>{
      'name': <String, Object?>{'type': 'string'},
    },
    required: const ['name'],
  );
  @override
  Map<String, Object?> get outputSchema => _objectSchema(
    properties: const {
      'projectPath': <String, Object?>{'type': 'string'},
      'projectId': <String, Object?>{'type': 'string'},
      'revision': <String, Object?>{'type': 'integer'},
    },
  );

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> arguments,
  ) async {
    context.cancel.throwIfCancelled();
    final name = (arguments['name'] as String).trim();
    if (name.isEmpty) {
      return const ToolResult(
        success: false,
        errorCode: ShadowErrorCode.toolInvalidArgs,
        errorMessage: 'name must not be empty',
      );
    }
    final res = await _projects.createProject(
      workspaceRoot: context.workspaceRoot,
      name: name,
    );
    return ToolResult(
      success: true,
      data: <String, Object?>{
        'projectPath': res.projectPath,
        'projectId': res.projectId,
        'revision': res.revision,
      },
    );
  }
}

class OpenProjectTool implements AgentTool {
  OpenProjectTool(this._projects);
  final ProjectLifecycleService _projects;

  @override
  String get name => 'open_project';
  @override
  String get description => 'Opens an existing project within the workspace.';
  @override
  ToolRiskLevel get riskLevel => ToolRiskLevel.restricted;
  @override
  bool get idempotent => true;
  @override
  Duration get timeout => const Duration(seconds: 15);
  @override
  Map<String, Object?> get inputSchema => _objectSchema(
    properties: const <String, Object?>{
      'path': <String, Object?>{'type': 'string'},
    },
    required: const ['path'],
  );
  @override
  Map<String, Object?> get outputSchema => _objectSchema(
    properties: const {
      'projectId': <String, Object?>{'type': 'string'},
      'revision': <String, Object?>{'type': 'integer'},
    },
  );

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> arguments,
  ) async {
    context.cancel.throwIfCancelled();
    final path = arguments['path'] as String;
    final doc = await _projects.openProject(
      workspaceRoot: context.workspaceRoot,
      projectPath: path,
    );
    return ToolResult(
      success: true,
      data: <String, Object?>{'projectId': doc.id, 'revision': doc.revision},
    );
  }
}

class SaveProjectTool implements AgentTool {
  SaveProjectTool(this._projects);
  final ProjectLifecycleService _projects;

  @override
  String get name => 'save_project';
  @override
  String get description => 'Saves the current project document.';
  @override
  ToolRiskLevel get riskLevel => ToolRiskLevel.safe;
  @override
  bool get idempotent => true;
  @override
  Duration get timeout => const Duration(seconds: 15);
  @override
  Map<String, Object?> get inputSchema => _objectSchema(properties: const {});
  @override
  Map<String, Object?> get outputSchema => _objectSchema(
    properties: const {
      'saved': <String, Object?>{'type': 'boolean'},
      'revision': <String, Object?>{'type': 'integer'},
    },
  );

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> arguments,
  ) async {
    context.cancel.throwIfCancelled();
    // revision consistency: refuse if context revision stale vs service
    final current = _projects.editing.revision;
    if (current != context.revision) {
      return ToolResult(
        success: false,
        errorCode: ShadowErrorCode.editRevisionMismatch,
        errorMessage: 'Revision mismatch',
        data: {'current': current, 'expected': context.revision},
      );
    }
    await _projects.editing.save();
    return ToolResult(
      success: true,
      data: <String, Object?>{
        'saved': true,
        'revision': _projects.editing.revision,
      },
    );
  }
}

class AddClipTool implements AgentTool {
  AddClipTool(this._editing);
  final EditingService _editing;

  @override
  String get name => 'add_clip';
  @override
  String get description =>
      'Adds a clip to the timeline via an editing transaction.';
  @override
  ToolRiskLevel get riskLevel => ToolRiskLevel.safe;
  @override
  bool get idempotent => true;
  @override
  Duration get timeout => const Duration(seconds: 10);
  @override
  Map<String, Object?> get inputSchema => _objectSchema(
    properties: const <String, Object?>{
      'trackId': <String, Object?>{'type': 'string'},
      'assetPath': <String, Object?>{'type': 'string'},
      'startTick': <String, Object?>{'type': 'integer', 'minimum': 0},
      'durationTicks': <String, Object?>{'type': 'integer', 'minimum': 1},
      'clipId': <String, Object?>{'type': 'string'},
    },
    required: const ['trackId', 'assetPath', 'startTick', 'durationTicks'],
  );
  @override
  Map<String, Object?> get outputSchema => _objectSchema(
    properties: const {
      'revision': <String, Object?>{'type': 'integer'},
      'applied': <String, Object?>{'type': 'integer'},
    },
  );

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> arguments,
  ) async {
    context.cancel.throwIfCancelled();
    final op = EditOperation(
      type: 'add_clip',
      target: arguments['trackId'] as String,
      payload: <String, Object?>{
        'assetPath': arguments['assetPath'],
        'startTick': arguments['startTick'],
        'durationTicks': arguments['durationTicks'],
        if (arguments['clipId'] != null) 'clipId': arguments['clipId'],
      },
    );
    final outcome = await _editing.apply(
      EditTransaction(operations: [op], label: 'add_clip'),
      expectedRevision: context.revision,
    );
    return ToolResult(
      success: true,
      data: <String, Object?>{
        'revision': outcome.revision,
        'applied': outcome.applied.length,
      },
    );
  }
}

class TrimClipTool implements AgentTool {
  TrimClipTool(this._editing);
  final EditingService _editing;

  @override
  String get name => 'trim_clip';
  @override
  String get description =>
      'Trims a clip non-destructively via an editing transaction.';
  @override
  ToolRiskLevel get riskLevel => ToolRiskLevel.safe;
  @override
  bool get idempotent => true;
  @override
  Duration get timeout => const Duration(seconds: 10);
  @override
  Map<String, Object?> get inputSchema => _objectSchema(
    properties: const <String, Object?>{
      'clipId': <String, Object?>{'type': 'string'},
      'inTick': <String, Object?>{'type': 'integer', 'minimum': 0},
      'outTick': <String, Object?>{'type': 'integer', 'minimum': 0},
    },
    required: const ['clipId'],
  );
  @override
  Map<String, Object?> get outputSchema => _objectSchema(
    properties: const {
      'revision': <String, Object?>{'type': 'integer'},
      'applied': <String, Object?>{'type': 'integer'},
    },
  );

  @override
  Future<ToolResult> execute(
    ToolContext context,
    Map<String, Object?> arguments,
  ) async {
    context.cancel.throwIfCancelled();
    final inTick = arguments['inTick'];
    final outTick = arguments['outTick'];
    if (inTick != null &&
        outTick != null &&
        (outTick as int) < (inTick as int)) {
      return const ToolResult(
        success: false,
        errorCode: ShadowErrorCode.editInvalidOperation,
        errorMessage: 'outTick must be >= inTick',
      );
    }
    final op = EditOperation(
      type: 'trim_clip',
      target: arguments['clipId'] as String,
      payload: <String, Object?>{'inTick': ?inTick, 'outTick': ?outTick},
    );
    final outcome = await _editing.apply(
      EditTransaction(operations: [op], label: 'trim_clip'),
      expectedRevision: context.revision,
    );
    return ToolResult(
      success: true,
      data: <String, Object?>{
        'revision': outcome.revision,
        'applied': outcome.applied.length,
      },
    );
  }
}

List<AgentTool> buildMvpTools({
  required ProjectLifecycleService projects,
  required MediaMetadataService media,
  required EnvironmentInfoService env,
}) {
  return <AgentTool>[
    GetSystemInfoTool(env),
    InspectCapabilitiesTool(env),
    const ListFilesTool(),
    ScanMediaTool(media),
    GetMetadataTool(media),
    CreateProjectTool(projects),
    OpenProjectTool(projects),
    SaveProjectTool(projects),
    AddClipTool(projects.editing),
    TrimClipTool(projects.editing),
  ];
}
