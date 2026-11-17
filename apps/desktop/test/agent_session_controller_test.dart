import 'dart:io';

import 'package:desktop/src/agent/agent_session_controller.dart';
import 'package:desktop/src/agent/agent_settings.dart';
import 'package:desktop/src/controller/editor_controller.dart';
import 'package:editing_core/editing_core.dart' as core;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';
import 'package:shadow_agent_runtime/agent_runtime.dart';
import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:shadow_tool_system/tool_system.dart';

void main() {
  late Directory cacheDir;
  late FakeMediaWorker worker;
  late core.DefaultEditingService editing;
  late EditorController editor;
  late AgentSessionController session;

  setUp(() {
    cacheDir = Directory.systemTemp.createTempSync('ss_agent_session_');
    worker = FakeMediaWorker();
    editing = core.DefaultEditingService(
      initialDocument: _buildDocument(),
    );
    editor = EditorController(
      editingService: editing,
      mediaLibrary: MediaLibraryService(worker: worker, cacheDir: cacheDir),
      initialProjectPath: '${cacheDir.path}/project.ssproj',
    );
    editor.selectClip('clip_1', trackId: 'track_v1');
  });

  tearDown(() {
    session.dispose();
    editor.dispose();
    worker.dispose();
    if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
  });

  test(
    'two consecutive timeline edits run through real approvals and refresh',
    () async {
      var nextDecision = 0;
      final brain = CallbackAgentBrain(
        onNextDecision: (
            {required plan, required currentStepId, required history}) async {
          switch (nextDecision++) {
            case 0:
              return const ToolCallsDecision(<AIToolCall>[
                AIToolCall(
                  id: 'call_1',
                  name: 'timeline_edit',
                  arguments: <String, Object?>{
                    'operations': <Object?>[
                      <String, Object?>{
                        'type': 'trim_clip',
                        'target': 'track_v1',
                        'payload': <String, Object?>{
                          'clipId': 'clip_1',
                          'durationTicks': 1500000,
                          'inTick': 0,
                        },
                      },
                    ],
                    'label': 'AI trim one',
                  },
                ),
              ]);
            case 1:
              return const ToolCallsDecision(<AIToolCall>[
                AIToolCall(
                  id: 'call_2',
                  name: 'timeline_edit',
                  arguments: <String, Object?>{
                    'operations': <Object?>[
                      <String, Object?>{
                        'type': 'trim_clip',
                        'target': 'track_v1',
                        'payload': <String, Object?>{
                          'clipId': 'clip_1',
                          'durationTicks': 1200000,
                          'inTick': 0,
                        },
                      },
                    ],
                    'label': 'AI trim two',
                  },
                ),
              ]);
            default:
              return const CompleteDecision(summary: 'Timeline trimmed twice.');
          }
        },
      );

      final registry = ToolRegistry()
        ..register(TimelineEditTool(CoreEditingServiceAdapter(editing)));
      session = AgentSessionController(
        editor: editor,
        settingsStore: AgentSettingsStore(
          configDirectory: cacheDir.path,
          environment: const <String, String>{},
        ),
        brainOverride: brain,
        toolRegistryOverride: registry,
      );
      await session.initialize();
      session.setEgressConsent(true);

      var refreshes = 0;
      editor.addListener(() => refreshes++);

      await session.run('Trim the first clip twice.');
      await _driveToCompletion(session);

      expect(
        session.status,
        AgentSessionStatus.succeeded,
        reason:
            '${session.errorCode} ${session.errorMessage}\n${session.activity.map((e) => e.message).join('\n')}',
      );
      expect(session.summary, 'Timeline trimmed twice.');
      expect(editing.revision, 2);
      expect(editor.document.tracks.first.clips.first.durationTicks, 1200000);
      expect(refreshes, greaterThanOrEqualTo(2));
      expect(
        session.activity
            .where((entry) => entry.message == 'timeline_edit completed'),
        hasLength(2),
      );
    },
  );

  test('run is refused until egress consent is explicit', () async {
    session = AgentSessionController(
      editor: editor,
      settingsStore: AgentSettingsStore(
        configDirectory: cacheDir.path,
        environment: const <String, String>{},
      ),
      brainOverride: CallbackAgentBrain(),
    );
    await session.initialize();

    await session.run('Do anything');

    expect(session.status, AgentSessionStatus.failed);
    expect(session.errorCode, ShadowErrorCode.permApprovalRequired);
    expect(editing.revision, 0);
  });

  test('approval rejection does not edit the project', () async {
    final brain = CallbackAgentBrain(
      onNextDecision: (
          {required plan, required currentStepId, required history}) async {
        if (history.any((message) => message.role == AIMessageRole.tool)) {
          return const CompleteDecision(summary: 'Stopped after denial.');
        }
        return const ToolCallsDecision(<AIToolCall>[
          AIToolCall(
            id: 'call_rejected',
            name: 'timeline_edit',
            arguments: <String, Object?>{
              'operations': <Object?>[
                <String, Object?>{
                  'type': 'trim_clip',
                  'target': 'track_v1',
                  'payload': <String, Object?>{
                    'clipId': 'clip_1',
                    'durationTicks': 500000,
                    'inTick': 0,
                  },
                },
              ],
              'label': 'Rejected trim',
            },
          ),
        ]);
      },
    );
    final registry = ToolRegistry()
      ..register(TimelineEditTool(CoreEditingServiceAdapter(editing)));
    session = AgentSessionController(
      editor: editor,
      settingsStore: AgentSettingsStore(
        configDirectory: cacheDir.path,
        environment: const <String, String>{},
      ),
      brainOverride: brain,
      toolRegistryOverride: registry,
    );
    await session.initialize();
    session.setEgressConsent(true);

    await session.run('Try a rejected trim.');
    await _waitForApproval(session);
    session.rejectPending();
    await _driveToCompletion(session);

    expect(editing.revision, 0);
    expect(editor.document.tracks.first.clips.first.durationTicks, 2000000);
    expect(session.status, AgentSessionStatus.succeeded);
  });
}

core.ProjectDocument _buildDocument() {
  const assetId = 'asset_1';
  return core.ProjectDocument(
    id: 'project_1',
    name: 'agent_test',
    sequenceId: 'seq_1',
    profile: core.ProjectProfile.hd1080p(),
    timebase: core.Timebase.ntsc2997(),
    tracks: <core.Track>[
      core.Track(
        id: 'track_v1',
        kind: core.TrackKind.video,
        position: 0,
        name: 'V1',
        clips: <core.Clip>[
          core.Clip(
            id: 'clip_1',
            assetId: assetId,
            kind: core.ClipKind.video,
            timelineStartTicks: 0,
            durationTicks: 2000000,
            sourceInTicks: 0,
          ),
        ],
      ),
    ],
    assets: const <String, core.Asset>{
      assetId: core.Asset(
        id: assetId,
        kind: core.AssetKind.video,
        uri: 'file:///media/source.mp4',
        durationTicks: 3000000,
      ),
    },
  );
}

Future<void> _driveToCompletion(AgentSessionController session) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (session.status == AgentSessionStatus.running) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Agent task did not finish before timeout');
    }
    final pending = session.pendingApproval;
    if (pending != null) {
      await session.approvePending();
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  await session.waitForTask();
}

Future<void> _waitForApproval(AgentSessionController session) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (session.pendingApproval == null) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Agent did not request approval before timeout');
    }
    if (session.status != AgentSessionStatus.running) {
      fail(
        'Agent stopped without requesting approval: '
        '${session.errorCode} ${session.errorMessage}\n'
        '${session.activity.map((e) => e.message).join('\n')}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}
