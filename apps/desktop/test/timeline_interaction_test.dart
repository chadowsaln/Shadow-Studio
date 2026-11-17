import 'dart:io';

import 'package:desktop/src/app.dart';
import 'package:desktop/src/ui/timeline/clip_widget.dart';
import 'package:editing_core/editing_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';

void main() {
  testWidgets('Interactive UI: transport, zoom, tools, and theme toggling', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final tempDir = Directory.systemTemp.createTempSync('ss_interactive_test_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final fakeWorker = FakeMediaWorker();
    addTearDown(() => fakeWorker.dispose());

    final initialDoc = ProjectDocument(
      name: 'interactive_test_proj',
      profile: ProjectProfile.hd1080p(),
      timebase: Timebase.ntsc2997(),
      tracks: [
        Track(
          id: 'track_v1',
          kind: TrackKind.video,
          position: 0,
          name: 'V1',
          clips: [
            Clip.video(
              id: 'clip_sample_1',
              assetId: 'asset_1',
              timelineStartTicks: 0,
              durationTicks: 3000000,
              label: 'Sample Video Clip',
            ),
          ],
        ),
        Track(id: 'track_a1', kind: TrackKind.audio, position: 1, name: 'A1'),
      ],
      assets: const {
        'asset_1': Asset(
          id: 'asset_1',
          kind: AssetKind.video,
          uri: 'file:///media/sample.mp4',
          durationTicks: 5000000,
        ),
      },
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

    // 1. Verify clip is rendered on timeline
    expect(find.byType(ClipWidget), findsOneWidget);
    expect(find.descendant(of: find.byType(ClipWidget), matching: find.text('Sample Video Clip')), findsOneWidget);

    // 2. Select Clip by clicking on it
    await tester.tap(find.byType(ClipWidget));
    await tester.pumpAndSettle();
    expect(find.text('Clip Inspector'), findsOneWidget);
    expect(find.text('TIMING & BOUNDS'), findsOneWidget);

    // 3. Test Tool Switching (Select -> Razor -> Select)
    await tester.tap(find.byIcon(Icons.content_cut));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.navigation_outlined));
    await tester.pumpAndSettle();

    // 4. Test Transport Controls (Play / Pause)
    await tester.tap(find.byIcon(Icons.play_circle_filled));
    await tester.pump();
    expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause_circle_filled));
    await tester.pump();
    expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);

    // 5. Test Zoom In / Zoom Out in timeline toolbar
    await tester.tap(find.byTooltip('Zoom In (Ctrl+=)'));
    await tester.pumpAndSettle();
    expect(find.text('63 px/s'), findsNWidgets(2)); // in timeline toolbar & status bar

    await tester.tap(find.byTooltip('Zoom Out (Ctrl+-)'));
    await tester.pumpAndSettle();
    expect(find.text('50 px/s'), findsNWidgets(2));

    // 6. Test Theme Mode Toggle (Dark -> Light -> Dark)
    await tester.tap(find.byIcon(Icons.light_mode));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.dark_mode), findsOneWidget);

    await tester.tap(find.byIcon(Icons.dark_mode));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.light_mode), findsOneWidget);
  });
}
