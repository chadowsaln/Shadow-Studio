import 'dart:io';

import 'package:desktop/src/controller/editor_controller.dart';
import 'package:editing_core/editing_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';

void main() {
  late Directory tempDir;
  late FakeMediaWorker worker;
  late DefaultEditingService editing;
  late EditorController editor;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ss_editor_refresh_');
    worker = FakeMediaWorker();
    editing = DefaultEditingService(
      initialDocument: ProjectDocument(
        id: 'refresh_project',
        name: 'refresh',
        sequenceId: 'refresh_seq',
        profile: ProjectProfile.hd1080p(),
        timebase: Timebase.ntsc2997(),
        tracks: <Track>[
          Track(
            id: 'track_v1',
            kind: TrackKind.video,
            position: 0,
            name: 'V1',
            clips: <Clip>[
              Clip(
                id: 'clip_1',
                kind: ClipKind.video,
                timelineStartTicks: 0,
                durationTicks: 1000000,
              ),
            ],
          ),
        ],
      ),
    );
    editor = EditorController(
      editingService: editing,
      mediaLibrary: MediaLibraryService(worker: worker, cacheDir: tempDir),
      initialProjectPath: '${tempDir.path}/project.ssproj',
    );
  });

  tearDown(() {
    editor.dispose();
    worker.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('refresh keeps a still-valid selection and clears a removed clip',
      () async {
    editor.selectClip('clip_1', trackId: 'track_v1');
    expect(editor.selectedClipId, 'clip_1');

    var notified = 0;
    editor.addListener(() => notified++);
    editor.refreshAfterExternalEdit();

    expect(notified, greaterThan(0));
    expect(editor.selectedClipId, 'clip_1');

    await editing.apply(
      EditTransaction(
        description: 'External remove',
        commands: const <EditCommand>[
          RemoveClipCommand(trackId: 'track_v1', clipId: 'clip_1'),
        ],
      ),
      expectedRevision: editing.revision,
    );

    editor.refreshAfterExternalEdit();

    expect(editor.selectedClipId, isNull);
    expect(editor.selectedTrackId, isNull);
    expect(editor.document.tracks.first.clips, isEmpty);
  });
}
