import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shadow_agent_runtime/agent_runtime.dart';
import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:shadow_permissions/permissions.dart' as perm;
import 'package:shadow_provider_gateway/provider_gateway.dart';
import 'package:shadow_tool_system/tool_system.dart';

import '../controller/editor_controller.dart';
import 'agent_settings.dart';
import 'desktop_tool_executor.dart';

/// Lifecycle of the desktop AI session.
enum AgentSessionStatus {
  unconfigured,
  idle,
  running,
  succeeded,
  failed,
  cancelled
}

enum AgentActivityKind { info, tool, approval, success, error }

class AgentActivityEntry {
  const AgentActivityEntry({
    required this.at,
    required this.message,
    this.kind = AgentActivityKind.info,
  });

  final DateTime at;
  final String message;
  final AgentActivityKind kind;
}

/// A tool call awaiting explicit user approval.
class PendingAgentApproval {
  const PendingAgentApproval({
    required this.requestId,
    required this.callId,
    required this.toolName,
    required this.riskLevel,
    required this.arguments,
    required this.expiresAt,
    this.reason,
  });

  final String requestId;
  final String callId;
  final String toolName;
  final ToolRiskLevel riskLevel;
  final Map<String, Object?> arguments;
  final DateTime expiresAt;
  final String? reason;
}

class _PendingApprovalState {
  _PendingApprovalState(this.view, this.request, this.completer);

  final PendingAgentApproval view;
  final perm.ApprovalRequest request;
  final Completer<ApprovalToken?> completer;
}

/// Owns the desktop-side AI runtime and exposes only UI-safe state.
///
/// Credentials never leave the provider gateway; this controller receives only
/// provider/model settings and asks the encrypted store whether a key exists.
class AgentSessionController extends ChangeNotifier {
  AgentSessionController({
    required this.editor,
    AgentSettingsStore? settingsStore,
    AgentBrain? brainOverride,
    ToolRegistry? toolRegistryOverride,
    perm.PermissionManager? permissionManager,
    String? workspaceRootOverride,
    this.providerTimeout = const Duration(seconds: 30),
  })  : settingsStore = settingsStore ?? AgentSettingsStore(),
        _brainOverride = brainOverride,
        _toolRegistryOverride = toolRegistryOverride,
        _permissions = permissionManager ?? perm.PermissionManager(),
        _workspaceRootOverride = workspaceRootOverride {
    unawaited(initialize());
  }

  final EditorController editor;
  final AgentSettingsStore settingsStore;
  final AgentBrain? _brainOverride;
  final ToolRegistry? _toolRegistryOverride;
  final perm.PermissionManager _permissions;
  final String? _workspaceRootOverride;

  /// Upper bound for a single provider request, from connection to last chunk.
  ///
  /// Tests use a short value to exercise the timeout path without waiting for
  /// a production-sized deadline.
  final Duration providerTimeout;

  AgentSettings? _settings;
  AgentSessionStatus _status = AgentSessionStatus.unconfigured;
  Future<void>? _initialization;
  bool _loading = true;
  bool _hasApiKey = false;
  String? _configurationError;
  String? _notice;
  String? _taskId;
  String? _summary;
  String? _errorCode;
  String? _errorMessage;
  bool _egressConsentGranted = false;
  int _completedSteps = 0;
  int _totalSteps = 0;
  int _toolCallsUsed = 0;
  int? _estimatedTokens;
  int? _tokenBudget;

  List<PlanStep> _plan = const <PlanStep>[];
  final List<AgentActivityEntry> _activity = <AgentActivityEntry>[];
  PendingAgentApproval? _pendingApproval;
  _PendingApprovalState? _pendingState;

  AgentController? _agent;
  StreamSubscription<AgentRuntimeEvent>? _events;
  Completer<void>? _taskDone;
  bool _disposed = false;

  static const int _maxActivityEntries = 100;

  AgentSettings? get settings => _settings;
  AgentSessionStatus get status => _status;
  bool get isLoading => _loading;
  bool get isConfigured => _hasApiKey || _brainOverride != null;
  bool get hasApiKey => _hasApiKey;
  String? get configurationError => _configurationError;
  String? get notice => _notice;
  String? get taskId => _taskId;
  String? get summary => _summary;
  String? get errorCode => _errorCode;
  String? get errorMessage => _errorMessage;
  bool get egressConsentGranted => _egressConsentGranted;
  int get completedSteps => _completedSteps;
  int get totalSteps => _totalSteps;
  int get toolCallsUsed => _toolCallsUsed;
  int? get estimatedTokens => _estimatedTokens;
  int? get tokenBudget => _tokenBudget;
  List<PlanStep> get plan => List<PlanStep>.unmodifiable(_plan);
  List<AgentActivityEntry> get activity =>
      List<AgentActivityEntry>.unmodifiable(_activity);
  PendingAgentApproval? get pendingApproval => _pendingApproval;

  String get providerLabel =>
      _settings?.provider.label ?? AgentSettings.defaults().provider.label;

  bool get isRunning => _status == AgentSessionStatus.running;

  bool get canRun =>
      !_loading && !isRunning && isConfigured && _egressConsentGranted;

  String get workspaceRoot {
    final override = _workspaceRootOverride;
    if (override != null && override.trim().isNotEmpty) return override;
    final projectPath = editor.currentProjectPath;
    if (projectPath == null || projectPath.trim().isEmpty) {
      return Directory.current.absolute.path;
    }
    return File(projectPath).absolute.parent.path;
  }

  /// Loads provider/model settings and checks for an available credential.
  Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      final loaded = await settingsStore.load();
      _settings = loaded;
      _hasApiKey = _brainOverride != null
          ? true
          : await settingsStore.hasApiKey(loaded.providerId);
      _notice = settingsStore.lastWarning;
      _configurationError = null;
    } catch (error) {
      _settings = AgentSettings.defaults();
      _hasApiKey = _brainOverride != null;
      _configurationError = 'Could not load AI settings: $error';
    } finally {
      _loading = false;
      _status = isConfigured
          ? AgentSessionStatus.idle
          : AgentSessionStatus.unconfigured;
      _notify();
    }
  }

  Future<void> saveSettings(AgentSettings settings, {String? apiKey}) async {
    await settingsStore.save(settings, apiKey: apiKey);
    _settings = settings;
    _configurationError = null;
    _notice = null;
    _hasApiKey = _brainOverride != null
        ? true
        : await settingsStore.hasApiKey(settings.providerId);
    if (!isRunning) {
      _status = isConfigured
          ? AgentSessionStatus.idle
          : AgentSessionStatus.unconfigured;
    }
    _notify();
  }

  void setEgressConsent(bool granted) {
    if (_egressConsentGranted == granted) return;
    _egressConsentGranted = granted;
    _notify();
  }

  /// Starts one agent task. Call [waitForTask] to await its terminal state.
  Future<void> run(String request) async {
    if (isRunning) {
      throw StateError('An AI task is already running');
    }
    await initialize();
    final trimmed = request.trim();
    if (trimmed.isEmpty) {
      _failLocally('AGENT_INVALID_REQUEST', 'Enter a task for the AI agent.');
      return;
    }
    if (!_egressConsentGranted) {
      _failLocally(
        ShadowErrorCode.permApprovalRequired,
        'Explicit consent is required before sending task context to the AI provider.',
      );
      return;
    }
    final settings = _settings;
    if (settings == null || !isConfigured) {
      _failLocally(
        ShadowErrorCode.providerAuth,
        'Configure an AI provider and save an API key first.',
      );
      return;
    }

    String? apiKey;
    if (_brainOverride == null) {
      try {
        apiKey = await settingsStore.readApiKey(settings.providerId);
      } catch (error) {
        _failLocally(ShadowErrorCode.providerAuth,
            'Credential store unavailable: $error');
        return;
      }
      if (apiKey == null || apiKey.trim().isEmpty) {
        _hasApiKey = false;
        _status = AgentSessionStatus.unconfigured;
        _failLocally(
          ShadowErrorCode.providerAuth,
          'No API key is saved for ${settings.provider.label}.',
        );
        return;
      }
    }

    await _disposeAgent();
    _permissions.clearPendingApprovals();
    _clearPendingApproval(completeWithDenial: false);

    _status = AgentSessionStatus.running;
    _taskId = null;
    _summary = null;
    _errorCode = null;
    _errorMessage = null;
    _configurationError = null;
    _completedSteps = 0;
    _totalSteps = 0;
    _toolCallsUsed = 0;
    _estimatedTokens = null;
    _tokenBudget = null;
    _plan = const <PlanStep>[];
    _activity.clear();
    _taskDone = Completer<void>();
    _notify();

    try {
      final holder = AgentContextHolder();
      final registry = _toolRegistryOverride ?? _buildToolRegistry();
      final toolExecutor = ToolExecutor(
        registry: registry,
        permissions: _permissions,
      );
      final brain = _brainOverride ??
          ProviderAgentBrain(
            router: _buildRouter(settings),
            model: settings.model,
            providerId: settings.providerId,
            tools: registry.all,
            context: holder,
            // The transport owns the hard deadline; the router timer is a
            // slightly later safety net so a transport timeout wins cleanly.
            requestTimeout: providerTimeout + const Duration(seconds: 1),
          );
      final agent = AgentController(
        brain: brain,
        toolExecutor: DesktopToolExecutor(
          registry: registry,
          executor: toolExecutor,
        ),
        approvalGate: _SessionApprovalGate(this),
        contextHolder: holder,
      );
      _agent = agent;
      _events = agent.events.listen(_handleEvent, onError: _handleStreamError);

      final task = agent.createTask(
        request: trimmed,
        workspaceRoot: workspaceRoot,
        projectRevision: editor.revision,
        metadata: <String, Object?>{
          'media_assets': _mediaAssetSummaries(),
          'selected_clip_ids': <String>[
            if (editor.selectedClipId != null) editor.selectedClipId!,
          ],
        },
      );
      _taskId = task.id;
      _log('Task started');
      _notify();
    } catch (error) {
      _failLocally(
          ShadowErrorCode.toolFailed, 'Could not start AI task: $error');
    }
  }

  Future<void> waitForTask() => _taskDone?.future ?? Future<void>.value();

  Future<void> approvePending() async {
    final state = _pendingState;
    if (state == null) return;
    final token = _permissions.approve(state.request.requestId);
    _pendingState = null;
    _pendingApproval = null;
    if (!state.completer.isCompleted) state.completer.complete(token);
    _log(
      token == null
          ? 'Approval expired or invalid'
          : 'Approved ${state.request.toolName}',
      kind:
          token == null ? AgentActivityKind.error : AgentActivityKind.approval,
    );
    _notify();
  }

  void rejectPending() {
    final state = _pendingState;
    _permissions.clearPendingApprovals();
    _clearPendingApproval(completeWithDenial: true);
    if (state != null) {
      _log('Rejected ${state.request.toolName}', kind: AgentActivityKind.error);
    }
    _notify();
  }

  Future<void> cancel() async {
    if (!isRunning) return;
    _rejectPendingWithoutNotice();
    final agent = _agent;
    final taskId = _taskId;
    if (agent == null || taskId == null) {
      _status = AgentSessionStatus.cancelled;
      _notify();
      return;
    }
    await agent.cancelTask(taskId, reason: 'cancelled by user');
    _completeTask();
  }

  ToolRegistry _buildToolRegistry() {
    final registry = ToolRegistry();
    registry.register(const ListFilesTool());
    registry.register(MediaProbeTool(worker: editor.mediaLibrary.worker));
    registry.register(MediaAnalysisTool(worker: editor.mediaLibrary.worker));
    registry.register(
      TimelineEditTool(CoreEditingServiceAdapter(editor.editingService)),
    );
    return registry;
  }

  ProviderRouter _buildRouter(AgentSettings settings) {
    final transport = HttpClientProviderTransport(
      connectionTimeout: providerTimeout,
    );
    final baseUri =
        settings.baseUri ?? Uri.parse(settings.provider.defaultBaseUri);
    final provider = switch (settings.providerId) {
      'anthropic' => AnthropicAdapter(
          transport: transport,
          credentialStore: settingsStore.credentialStore,
          baseUri: baseUri,
          defaultTimeout: providerTimeout,
        ),
      'gemini' => GeminiAdapter(
          transport: transport,
          credentialStore: settingsStore.credentialStore,
          baseUri: baseUri,
          defaultTimeout: providerTimeout,
        ),
      'openrouter' => OpenRouterAdapter(
          transport: transport,
          credentialStore: settingsStore.credentialStore,
          baseUri: baseUri,
          defaultTimeout: providerTimeout,
        ),
      _ => OpenAIAdapter(
          transport: transport,
          credentialStore: settingsStore.credentialStore,
          baseUri: baseUri,
          defaultTimeout: providerTimeout,
        ),
    };
    return ProviderRouter(
      providers: <AIProvider>[provider],
      credentialStore: settingsStore.credentialStore,
      egressConsent: _SessionEgressConsent(this),
    );
  }

  List<Map<String, Object?>> _mediaAssetSummaries() {
    return editor.document.assets.values
        .map(
          (asset) => <String, Object?>{
            'id': asset.id,
            'name': p.basename(asset.uri),
            'kind': asset.kind.name,
            'duration_ticks': asset.durationTicks,
            'uri': asset.uri,
            if (asset.hash != null) 'hash': asset.hash,
          },
        )
        .toList(growable: false);
  }

  Future<ApprovalToken?> requestToolApproval({
    required String taskId,
    required String callId,
    required AgentTool tool,
    required Map<String, Object?> arguments,
  }) async {
    if (_pendingApproval != null) return null;
    try {
      final request = _permissions.requestApproval(
        toolName: tool.name,
        riskLevel: tool.riskLevel,
        declaredRiskLevel: tool.riskLevel,
        arguments: arguments,
        workspaceRoot: workspaceRoot,
        reason: 'AI wants to run a ${tool.riskLevel.name} tool',
      );
      final completer = Completer<ApprovalToken?>();
      _pendingState = _PendingApprovalState(
        PendingAgentApproval(
          requestId: request.requestId,
          callId: callId,
          toolName: request.toolName,
          riskLevel: request.riskLevel,
          arguments: request.arguments,
          expiresAt: request.expiresAt,
          reason: request.reason,
        ),
        request,
        completer,
      );
      _pendingApproval = _pendingState!.view;
      _log('Approval required for ${tool.name}',
          kind: AgentActivityKind.approval);
      _notify();
      return await completer.future;
    } catch (error) {
      _log('Approval request failed: $error', kind: AgentActivityKind.error);
      return null;
    }
  }

  void _handleEvent(AgentRuntimeEvent event) {
    switch (event) {
      case TaskStarted():
        _status = AgentSessionStatus.running;
        break;
      case PlanUpdated(:final steps, :final reason):
        _plan = steps;
        _totalSteps = steps.length;
        _completedSteps = steps
            .where((step) => step.status == PlanStepStatus.completed)
            .length;
        _log(reason == null ? 'Plan ready' : 'Plan updated: $reason');
        break;
      case StepStarted(:final stepId, :final description):
        _plan = <PlanStep>[
          for (final step in _plan)
            if (step.id == stepId)
              step.copyWith(status: PlanStepStatus.inProgress)
            else
              step,
        ];
        _log(description, kind: AgentActivityKind.info);
        break;
      case ToolCallRequested(:final toolName):
        _log('Requested $toolName', kind: AgentActivityKind.tool);
        break;
      case ToolExecutionStarted(:final toolName, :final attempt):
        _log('Running $toolName (attempt $attempt)',
            kind: AgentActivityKind.tool);
        break;
      case ToolExecutionCompleted(:final toolName, :final result):
        if (result.success) {
          _log('$toolName completed', kind: AgentActivityKind.success);
          if (toolName == 'timeline_edit') {
            editor.refreshAfterExternalEdit();
          }
        } else {
          _log(
            '$toolName failed: ${result.errorMessage ?? result.errorCode ?? 'unknown error'}',
            kind: AgentActivityKind.error,
          );
        }
        break;
      case ApprovalRequested(:final toolName):
        _log('Waiting for approval: $toolName',
            kind: AgentActivityKind.approval);
        break;
      case TaskProgress(
          :final message,
          :final completedSteps,
          :final totalSteps,
          :final toolCallsUsed,
        ):
        _completedSteps = completedSteps;
        _totalSteps = totalSteps;
        _toolCallsUsed = toolCallsUsed;
        _log(message);
        break;
      case ContextUpdated(:final snapshot):
        _estimatedTokens = snapshot.estimatedTokens;
        _tokenBudget = snapshot.tokenBudget;
        break;
      case TaskCompleted(:final summary):
        _status = AgentSessionStatus.succeeded;
        _summary = summary;
        _pendingApproval = null;
        _pendingState = null;
        _log(summary, kind: AgentActivityKind.success);
        _completeTask();
        break;
      case TaskFailed(:final code, :final message):
        _status = AgentSessionStatus.failed;
        _errorCode = code;
        _errorMessage = message;
        _clearPendingApproval(completeWithDenial: true);
        _log(message, kind: AgentActivityKind.error);
        _completeTask();
        break;
      case TaskCancelled(:final reason):
        _status = AgentSessionStatus.cancelled;
        _errorMessage = reason ?? 'Cancelled';
        _clearPendingApproval(completeWithDenial: true);
        _log(_errorMessage!, kind: AgentActivityKind.error);
        _completeTask();
        break;
    }
    _notify();
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    _status = AgentSessionStatus.failed;
    _errorCode = ShadowErrorCode.toolFailed;
    _errorMessage = 'Agent event stream failed: $error';
    _clearPendingApproval(completeWithDenial: true);
    _log(_errorMessage!, kind: AgentActivityKind.error);
    _completeTask();
    _notify();
  }

  void _completeTask() {
    final done = _taskDone;
    if (done != null && !done.isCompleted) done.complete();
    _notify();
  }

  void _failLocally(String code, String message) {
    _status = AgentSessionStatus.failed;
    _errorCode = code;
    _errorMessage = message;
    _log(message, kind: AgentActivityKind.error);
    _completeTask();
    _notify();
  }

  void _log(String message, {AgentActivityKind kind = AgentActivityKind.info}) {
    _activity.add(
      AgentActivityEntry(
        at: DateTime.now().toUtc(),
        message: message,
        kind: kind,
      ),
    );
    if (_activity.length > _maxActivityEntries) {
      _activity.removeRange(0, _activity.length - _maxActivityEntries);
    }
  }

  void _clearPendingApproval({required bool completeWithDenial}) {
    final state = _pendingState;
    _pendingState = null;
    _pendingApproval = null;
    if (completeWithDenial && state != null && !state.completer.isCompleted) {
      state.completer.complete(null);
    }
  }

  void _rejectPendingWithoutNotice() {
    _permissions.clearPendingApprovals();
    _clearPendingApproval(completeWithDenial: true);
  }

  Future<void> _disposeAgent() async {
    await _events?.cancel();
    _events = null;
    final agent = _agent;
    _agent = null;
    if (agent != null) {
      await agent.dispose();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _rejectPendingWithoutNotice();
    final agent = _agent;
    _agent = null;
    _events = null;
    if (agent != null) unawaited(agent.dispose());
    final done = _taskDone;
    if (done != null && !done.isCompleted) done.complete();
    super.dispose();
  }
}

class _SessionApprovalGate implements ApprovalGate {
  _SessionApprovalGate(this._owner);

  final AgentSessionController _owner;

  @override
  Future<ApprovalToken?> requestApproval({
    required String taskId,
    required String callId,
    required AgentTool tool,
    required Map<String, Object?> arguments,
  }) {
    return _owner.requestToolApproval(
      taskId: taskId,
      callId: callId,
      tool: tool,
      arguments: arguments,
    );
  }
}

class _SessionEgressConsent implements EgressConsentService {
  _SessionEgressConsent(this._owner);

  final AgentSessionController _owner;

  @override
  Future<bool> hasConsent({
    required String providerId,
    required List<EgressPayloadDescriptor> payloads,
    String? purpose,
  }) async =>
      _owner.egressConsentGranted;

  @override
  Future<bool> requestConsent({
    required String providerId,
    required List<EgressPayloadDescriptor> payloads,
    String? purpose,
  }) async =>
      false;
}
