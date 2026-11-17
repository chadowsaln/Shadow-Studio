import 'package:editing_core/editing_core.dart';
import 'package:test/test.dart';

void main() {
  group('Performance (QG-2, QG-10)', () {
    test('300-clip document operations execute in < 50 ms', () async {
      final assets = <String, Asset>{};
      for (var a = 0; a < 10; a++) {
        final id = UuidV7.generate();
        assets[id] = Asset(
          id: id,
          kind: a < 5 ? AssetKind.video : AssetKind.audio,
          uri: 'file:///fixtures/asset_$a.mp4',
          durationTicks: 200000000, // 200 seconds
        );
      }

      final videoAssetIds = assets.values
          .where((a) => a.kind == AssetKind.video)
          .map((a) => a.id)
          .toList();
      final audioAssetIds = assets.values
          .where((a) => a.kind == AssetKind.audio)
          .map((a) => a.id)
          .toList();

      // Create 6 tracks: 3 video, 3 audio
      final tracks = <Track>[];
      for (var t = 0; t < 6; t++) {
        final isVideo = t < 3;
        final trackClips = <Clip>[];
        final assetPool = isVideo ? videoAssetIds : audioAssetIds;

        // 50 clips per track = 300 clips total
        for (var c = 0; c < 50; c++) {
          final clipId = UuidV7.generate();
          final assetId = assetPool[c % assetPool.length];
          final start = c * 2000000; // each clip 1s, placed every 2s (gap 1s, no overlap)
          final duration = 1000000;

          trackClips.add(
            isVideo
                ? Clip.video(
                    id: clipId,
                    assetId: assetId,
                    timelineStartTicks: start,
                    durationTicks: duration,
                    sourceInTicks: 100000,
                  )
                : Clip.audio(
                    id: clipId,
                    assetId: assetId,
                    timelineStartTicks: start,
                    durationTicks: duration,
                    sourceInTicks: 100000,
                  ),
          );
        }

        tracks.add(
          Track(
            id: UuidV7.generate(),
            kind: isVideo ? TrackKind.video : TrackKind.audio,
            position: t,
            name: isVideo ? 'V${t + 1}' : 'A${t - 2}',
            clips: trackClips,
          ),
        );
      }

      final doc300 = ProjectDocument(
        name: '300-Clip Performance Project',
        profile: ProjectProfile.hd1080p(),
        timebase: Timebase.fps30(),
        tracks: tracks,
        assets: assets,
      );

      // Verify invariant checking of 300 clips passes
      final stopwatch = Stopwatch()..start();
      DocumentInvariants.validate(doc300);
      final validationMs = stopwatch.elapsedMilliseconds;
      expect(validationMs, lessThan(100), reason: 'DocumentInvariants.validate took too long');

      final service = DefaultEditingService(initialDocument: doc300, initialRevision: 0);

      // Perform an edit transaction: split a clip, trim another clip, move a third clip
      final targetTrack = doc300.tracks[0];
      final clipToSplit = targetTrack.clips[5];
      final clipToTrim = targetTrack.clips[10];
      final clipToMove = targetTrack.clips[15];

      final splitCmd = SplitClipCommand(
        trackId: targetTrack.id,
        clipId: clipToSplit.id,
        splitAtTick: clipToSplit.timelineStartTicks + (clipToSplit.durationTicks ~/ 2),
        newClipId: UuidV7.generate(),
      );

      final trimCmd = TrimClipCommand(
        trackId: targetTrack.id,
        clipId: clipToTrim.id,
        newTimelineStartTicks: clipToTrim.timelineStartTicks,
        newDurationTicks: clipToTrim.durationTicks ~/ 2,
        newSourceInTicks: clipToTrim.sourceInTicks,
      );

      // Gap between clips is 1s (1,000,000 ticks). Move clip 15 forward by 200,000 ticks (still in gap).
      final moveCmd = MoveClipCommand(
        clipId: clipToMove.id,
        fromTrackId: targetTrack.id,
        toTrackId: targetTrack.id,
        newTimelineStartTicks: clipToMove.timelineStartTicks + 200000,
      );

      final txn = EditTransaction(
        description: 'Complex 3-command edit on 300-clip project',
        commands: [splitCmd, trimCmd, moveCmd],
      );

      // JIT Warm-up on a small document
      final warmupDoc = ProjectDocument.createBlank(name: 'Warmup');
      final warmupService = DefaultEditingService(initialDocument: warmupDoc);
      final warmupTrack = Track(id: UuidV7.generate(), kind: TrackKind.video, position: 0, name: 'W');
      await warmupService.apply(
        EditTransaction.single(AddTrackCommand(warmupTrack)),
        expectedRevision: 0,
      );
      await warmupService.undo(expectedRevision: 1);

      stopwatch.reset();
      final applyOutcome = await service.apply(txn, expectedRevision: 0);
      final applyMs = stopwatch.elapsedMilliseconds;

      expect(applyOutcome.isSuccess, isTrue);
      expect(applyMs, lessThan(100), reason: 'Apply transaction on 300-clip project took $applyMs ms (> 100 ms budget)');

      // Benchmark Undo
      stopwatch.reset();
      final undoOutcome = await service.undo(expectedRevision: 1);
      final undoMs = stopwatch.elapsedMilliseconds;

      expect(undoOutcome.isSuccess, isTrue);
      expect(undoMs, lessThan(100), reason: 'Undo on 300-clip project took $undoMs ms (> 100 ms budget)');
      expect(service.currentDocument, equals(doc300));

      // Benchmark Redo
      stopwatch.reset();
      final redoOutcome = await service.redo(expectedRevision: 2);
      final redoMs = stopwatch.elapsedMilliseconds;

      expect(redoOutcome.isSuccess, isTrue);
      expect(redoMs, lessThan(100), reason: 'Redo on 300-clip project took $redoMs ms (> 100 ms budget)');

      expect(redoOutcome.isSuccess, isTrue);
      expect(redoMs, lessThan(50), reason: 'Redo on 300-clip project took $redoMs ms (> 50 ms budget)');
    });
  });
}
