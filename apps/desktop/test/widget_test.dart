import 'dart:io';

import 'package:desktop/src/app.dart';
import 'package:desktop/src/ui/shell/right_dock.dart';
import 'package:editing_core/editing_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';

void main() {
  testWidgets('ShadowStudioApp boots full desktop layout cleanly',
      (WidgetTester tester) async {
    // Set a desktop viewport size (1440x900)
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final tempDir = Directory.systemTemp.createTempSync('ss_widget_test_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final fakeWorker = FakeMediaWorker();
    addTearDown(() => fakeWorker.dispose());

    final initialDoc = ProjectDocument(
      name: 'widget_test_proj',
      profile: ProjectProfile.hd1080p(),
      timebase: Timebase.ntsc2997(),
      tracks: [
        Track(
            id: 'track_v1',
            kind: TrackKind.video,
            position: 0,
            name: 'V1 (Video)'),
        Track(
            id: 'track_a1',
            kind: TrackKind.audio,
            position: 1,
            name: 'A1 (Audio)'),
        Track(
            id: 'track_t1',
            kind: TrackKind.overlay,
            position: 2,
            name: 'T1 (Titles)'),
      ],
      assets: const {},
    );
    final editingService = DefaultEditingService(initialDocument: initialDoc);

    await tester.pumpWidget(
      ShadowStudioApp(
        customEditingService: editingService,
        customMediaWorker: fakeWorker,
        customCacheDir: tempDir,
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify TopBar elements
    expect(find.text('Shadow Studio'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);

    // 2. Verify StatusBar
    expect(find.text('Ready'), findsOneWidget);
    expect(find.textContaining('Rev 0'),
        findsNWidgets(2)); // StatusBar & InspectorPanel

    // 3. Verify Media Bin
    expect(find.textContaining('Media Bin'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);

    // 4. Verify Track Headers in Timeline
    expect(find.text('V1 (Video)'), findsOneWidget);
    expect(find.text('A1 (Audio)'), findsOneWidget);
    expect(find.text('T1 (Titles)'), findsOneWidget);

    // 5. Verify Inspector Sequence Settings
    expect(find.text('Project Settings'), findsOneWidget);
    expect(find.text('1920 x 1080'), findsOneWidget);

    // 6. AI tab is reachable from the right dock
    expect(find.text('Inspector'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(RightDock),
        matching: find.text('AI'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('AI Agent'), findsOneWidget);

    // 7. Test Export Dialog modal trigger
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();

    expect(find.text('Export Sequence'), findsOneWidget);
    expect(find.textContaining('YouTube 1080p'), findsOneWidget);
    expect(find.text('Start Render'), findsOneWidget);

    // Close export dialog
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Export Sequence'), findsNothing);
  });
}
