import 'dart:io';

import 'package:desktop/src/agent/agent_session_controller.dart';
import 'package:desktop/src/agent/agent_settings.dart';
import 'package:desktop/src/controller/editor_controller.dart';
import 'package:desktop/src/theme/shadow_theme.dart';
import 'package:desktop/src/ui/ai/ai_panel.dart';
import 'package:editing_core/editing_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';
import 'package:shadow_agent_runtime/agent_runtime.dart';

void main() {
  late Directory tempDir;
  late FakeMediaWorker worker;
  late EditorController editor;
  late AgentSessionController session;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('ss_ai_panel_');
    worker = FakeMediaWorker();
    final editing = core.DefaultEditingService(
      initialDocument: core.ProjectDocument(
        id: 'project_ui',
        name: 'ui_test',
        sequenceId: 'seq_ui',
        profile: core.ProjectProfile.hd1080p(),
        timebase: core.Timebase.ntsc2997(),
        tracks: <core.Track>[
          core.Track(
            id: 'track_v1',
            kind: core.TrackKind.video,
            position: 0,
            name: 'V1',
          ),
        ],
      ),
    );
    editor = EditorController(
      editingService: editing,
      mediaLibrary: MediaLibraryService(worker: worker, cacheDir: tempDir),
      initialProjectPath: '${tempDir.path}/project.ssproj',
    );
    session = AgentSessionController(
      editor: editor,
      settingsStore: AgentSettingsStore(
        configDirectory: tempDir.path,
        environment: const <String, String>{},
      ),
      brainOverride: CallbackAgentBrain(),
    );
    await session.initialize();
  });

  tearDown(() {
    session.dispose();
    editor.dispose();
    worker.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    await tester.pumpWidget(
      MaterialApp(
        theme: ShadowTheme.dark(),
        home: Scaffold(
          body: SizedBox(width: 320, child: AiPanel(session: session)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('task runs after explicit consent and reports completion', (
    tester,
  ) async {
    await pumpPanel(tester);

    expect(find.text('AI Agent'), findsOneWidget);
    expect(find.text('AI provider not configured'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Finish this task');
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.runAsync(session.waitForTask);
    await tester.pumpAndSettle();

    expect(find.textContaining('Completed'), findsWidgets);
    expect(
      session.status,
      AgentSessionStatus.succeeded,
      reason: '${session.errorCode} ${session.errorMessage}',
    );
  });

  testWidgets('settings dialog opens from the panel header', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('AI Provider'), findsOneWidget);
    expect(find.text('Provider'), findsOneWidget);
    expect(find.text('Model'), findsOneWidget);
    expect(find.text('API key'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('AI Provider'), findsNothing);
  });
}
