import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:editing_core/editing_core.dart' as core;
import 'package:media_core/media_core.dart';
import 'package:shadow_agent_runtime/agent_runtime.dart';
import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:shadow_permissions/permissions.dart' as permissions;
import 'package:shadow_provider_gateway/provider_gateway.dart';
import 'package:shadow_tool_system/tool_system.dart';
import 'package:test/test.dart';

/// End-to-end acceptance scenario:
/// "Create a professional 30-second advertisement from this video."
///
/// Everything is real: ffmpeg/ffprobe inspect a generated 30s source, the real
/// tool registry validates arguments and permissions, the timeline is edited
/// through the Editing Core, and the provider is a scripted [MockProvider]
/// (no network, no keys). The deliverable is the editable timeline plus a
/// verified project revision; rendering an MP4 is not part of this scenario.
class _ToolExecutorAdapter implements ToolCallExecutor {
  _ToolExecutorAdapter(this._executor, this._registry);

  final ToolExecutor _executor;
  final ToolRegistry _registry;

  @override
  AgentTool? resolve(String name) => _registry.resolve(name);

  @override
  Future<ToolResult> execute({
    required AIToolCall call,
    required ToolContext context,
    required AgentTool tool,
  }) async {
    final outcome = await _executor.executeCall(
      toolName: call.name,
      arguments: call.arguments,
      context: context,
    );
    return outcome.result;
  }
}

/// Approval gate backed by the real [permissions.PermissionManager].
///
/// No human is present in the test, so the gate explicitly approves the
/// request; the manager still binds the token to the exact tool call and
/// arguments, and the tool cannot run without it.
class _ExplicitApprovalGate implements ApprovalGate {
  _ExplicitApprovalGate(this._manager, {required this.workspaceRoot});

  final permissions.PermissionManager _manager;
  final String workspaceRoot;
  final List<ApprovalToken> issued = <ApprovalToken>[];

  @override
  Future<ApprovalToken?> requestApproval({
    required String taskId,
    required String callId,
    required AgentTool tool,
    required Map<String, Object?> arguments,
  }) async {
    final request = _manager.requestApproval(
      toolName: tool.name,
      riskLevel: tool.riskLevel,
      arguments: arguments,
      workspaceRoot: workspaceRoot,
    );
    final token = _manager.approve(request.requestId);
    if (token != null) issued.add(token);
    return token;
  }
}

Future<ManagedTask> _awaitTask(AgentController controller, ManagedTask task) {
  final completer = Completer<ManagedTask>();
  late final StreamSubscription<Object> subscription;
  subscription = controller.events.listen((event) {
    if (event.taskId != task.id) return;
    if (event is TaskCompleted ||
        event is TaskFailed ||
        event is TaskCancelled) {
      if (!completer.isCompleted) {
        completer.complete(controller.task(task.id) ?? task);
      }
    }
  });
  return completer.future.whenComplete(subscription.cancel);
}

bool _hasFfmpeg() {
  try {
    return Process.runSync('ffmpeg', <String>['-version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

void main() {
  const durationTicks30s = 30 * 1000 * 1000;

  late Directory workspace;
  late String sourcePath;

  setUpAll(() {
    if (!_hasFfmpeg()) return;
    workspace = Directory.systemTemp.createTempSync('shadow_accept_');
    sourcePath = '${workspace.path}/source.mp4';
    final generated = Process.runSync('ffmpeg', <String>[
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      '-f',
      'lavfi',
      '-i',
      'testsrc2=size=640x360:rate=30:duration=15',
      '-f',
      'lavfi',
      '-i',
      'smptehdbars=size=640x360:rate=30:duration=15',
      '-filter_complex',
      '[0:v][1:v]concat=n=2:v=1:a=0[v]',
      '-map',
      '[v]',
      '-pix_fmt',
      'yuv420p',
      '-c:v',
      'libx264',
      '-preset',
      'ultrafast',
      sourcePath,
    ]);
    if (generated.exitCode != 0) {
      workspace.deleteSync(recursive: true);
      throw StateError(
        'ffmpeg failed to generate the source: ${generated.stderr}',
      );
    }
  });

  tearDownAll(() {
    if (workspace.existsSync()) workspace.deleteSync(recursive: true);
  });

  test('30s advertisement from a real source video', () async {
    if (!_hasFfmpeg()) {
      markTestSkipped('ffmpeg unavailable');
      return;
    }

    final worker = FfmpegMediaWorker();
    final assetId = core.UuidV7.generate();
    final assetHash = await worker.computeBlake3(sourcePath);

    final coreService = core.DefaultEditingService(
      initialDocument: core.ProjectDocument(
        name: 'Shadow Studio 30s Ad',
        profile: core.ProjectProfile.hd1080p(),
        timebase: core.Timebase.fps30(),
        tracks: <core.Track>[
          core.Track(
            id: 'main',
            kind: core.TrackKind.video,
            position: 0,
            name: 'Main',
          ),
        ],
        assets: <String, core.Asset>{
          assetId: core.Asset(
            id: assetId,
            kind: core.AssetKind.video,
            uri: sourcePath,
            durationTicks: durationTicks30s,
            hash: assetHash,
          ),
        },
      ),
      projectFilePath: '${workspace.path}/ad.shadow',
    );
    final editing = CoreEditingServiceAdapter(coreService);

    final registry = ToolRegistry()
      ..register(MediaProbeTool(worker: worker))
      ..register(MediaAnalysisTool(worker: worker))
      ..register(TimelineEditTool(editing));

    final permissionManager = permissions.PermissionManager();
    final executor = _ToolExecutorAdapter(
      ToolExecutor(registry: registry, permissions: permissionManager),
      registry,
    );

    final credentials = InMemoryCredentialStore();
    await credentials.saveApiKey(providerId: 'mock', apiKey: 'test-key');

    var decisionCalls = 0;
    final analysisResults = <ToolResult>[];
    final provider = MockProvider(
      id: 'mock',
      onStream: (request, cancel) async* {
        final system = request.messages.first.content ?? '';
        if (system.contains('planning stage')) {
          yield const AITextDeltaEvent(
            '{"steps":['
            '{"description":"Analyze the source video","expected_outcome":"metadata and scenes known"},'
            '{"description":"Build the 30 second timeline","expected_outcome":"project revision increased"}'
            ']}',
          );
          yield const AICompletedEvent(finishReason: 'stop');
          return;
        }

        final decisionIndex = decisionCalls++;
        if (decisionIndex == 0) {
          yield const AITextDeltaEvent(
            '{"action":"tool_calls","calls":[{"name":"media_analysis",'
            '"arguments":{"path":"source.mp4"}}]}',
          );
        } else if (decisionIndex == 1) {
          // revision comes from ToolContext, never from model arguments
          final arguments = jsonEncode(<String, Object?>{
            'label': 'assemble 30s ad',
            'operations': <Object?>[
              <String, Object?>{
                'type': 'add_clip',
                'target': 'main',
                'payload': <String, Object?>{
                  'kind': 'video',
                  'assetId': assetId,
                  'startTick': 0,
                  'durationTicks': durationTicks30s ~/ 2,
                  'label': 'ad_part_1',
                },
              },
              <String, Object?>{
                'type': 'add_clip',
                'target': 'main',
                'payload': <String, Object?>{
                  'kind': 'video',
                  'assetId': assetId,
                  'startTick': durationTicks30s ~/ 2,
                  'durationTicks': durationTicks30s ~/ 2,
                  'label': 'ad_part_2',
                },
              },
            ],
          });
          yield AITextDeltaEvent(
            '{"action":"tool_calls","calls":[{"name":"timeline_edit",'
            '"arguments":$arguments}]}',
          );
        } else {
          yield const AITextDeltaEvent(
            '{"action":"complete","summary":"30s advertisement assembled",'
            '"result":{"deliverable":"editable 30s timeline"}}',
          );
        }
        yield const AICompletedEvent(finishReason: 'stop');
      },
    );

    final brain = ProviderAgentBrain(
      router: ProviderRouter(
        providers: <AIProvider>[provider],
        credentialStore: credentials,
      ),
      model: 'mock-model',
      providerId: 'mock',
      tools: registry.all,
    );

    final gate = _ExplicitApprovalGate(
      permissionManager,
      workspaceRoot: workspace.path,
    );

    final controller = AgentController(
      brain: brain,
      toolExecutor: executor,
      approvalGate: gate,
    );
    final agent = SpecializedAgent(
      role: AgentRole.videoEditing,
      controllerFactory: () => controller,
    );
    final subscription = controller.events.listen((event) {
      if (event is ToolExecutionCompleted &&
          event.toolName == 'media_analysis' &&
          event.result.success) {
        analysisResults.add(event.result);
      }
    });

    final outcome = await agent.run(
      request: 'Create a professional 30-second advertisement from source.mp4',
      workspaceRoot: workspace.path,
      projectRevision: 0,
    );
    await subscription.cancel();
    await agent.dispose();

    // The analysis really ran through ffmpeg on the generated file.
    expect(outcome.state, ManagedTaskState.succeeded);
    expect(analysisResults, hasLength(1));
    final analysis =
        analysisResults.single.data['analysis'] as Map<String, Object?>;
    expect(analysis['has_video'], isTrue);
    expect(analysis['scenes'] as List<Object?>, isNotEmpty);

    // Both restricted tools required exactly one explicit approval each.
    expect(gate.issued.map((t) => t.toolName), <String>[
      'media_analysis',
      'timeline_edit',
    ]);

    // The deliverable is a real 30 second timeline at revision 1.
    expect(coreService.revision, 1);
    final clips = coreService.currentDocument.tracks.single.clips;
    expect(clips, hasLength(2));
    expect(coreService.currentDocument.durationTicks, durationTicks30s);
    expect(clips.first.timelineStartTicks, 0);
    expect(clips.last.timelineStartTicks, durationTicks30s ~/ 2);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the same scenario fails loudly when the source is missing', () async {
    if (!_hasFfmpeg()) {
      markTestSkipped('ffmpeg unavailable');
      return;
    }

    final registry = ToolRegistry()
      ..register(MediaProbeTool(worker: FfmpegMediaWorker()));
    final executor = _ToolExecutorAdapter(
      ToolExecutor(
        registry: registry,
        permissions: permissions.PermissionManager(),
      ),
      registry,
    );

    final store = InMemoryCredentialStore();
    await store.saveApiKey(providerId: 'mock', apiKey: 'test-key');
    var calls = 0;
    final provider = MockProvider(
      id: 'mock',
      onStream: (request, cancel) async* {
        calls++;
        yield const AITextDeltaEvent(
          '{"action":"tool_calls","calls":[{"name":"media_probe",'
          '"arguments":{"path":"missing.mp4"}}]}',
        );
        yield const AICompletedEvent(finishReason: 'stop');
      },
    );

    final brain = ProviderAgentBrain(
      router: ProviderRouter(
        providers: <AIProvider>[provider],
        credentialStore: store,
      ),
      model: 'mock-model',
      providerId: 'mock',
      tools: registry.all,
    );

    final controller = AgentController(brain: brain, toolExecutor: executor);
    final task = controller.createTask(
      request: 'Probe missing.mp4',
      workspaceRoot: workspace.path,
      projectRevision: 0,
    );
    final outcome = await _awaitTask(controller, task);
    await controller.dispose();

    expect(outcome.state, ManagedTaskState.failed);
    expect(outcome.errorCode, isNotNull);
    expect(calls, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
