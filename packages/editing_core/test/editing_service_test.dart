import 'package:editing_core/editing_core.dart';
import 'package:test/test.dart';

void main() {
  group('DefaultEditingService', () {
    late Asset videoAsset;
    late Track trackV1;
    late ProjectDocument initialDoc;
    late DefaultEditingService service;

    setUp(() {
      videoAsset = Asset(
        id: UuidV7.generate(),
        kind: AssetKind.video,
        uri: 'file:///media/sample.mp4',
        durationTicks: 20000000, // 20s
      );

      trackV1 = Track(
        id: UuidV7.generate(),
        kind: TrackKind.video,
        position: 0,
        name: 'V1',
      );

      initialDoc = ProjectDocument(
        name: 'Service Test Project',
        profile: ProjectProfile.hd1080p(),
        timebase: Timebase.fps30(),
        tracks: [trackV1],
        assets: {videoAsset.id: videoAsset},
      );

      service = DefaultEditingService(initialDocument: initialDoc, initialRevision: 0);
    });

    test('starts with revision 0 and empty undo/redo stacks', () {
      expect(service.revision, equals(0));
      expect(service.canUndo, isFalse);
      expect(service.canRedo, isFalse);
      expect(service.currentDocument, equals(initialDoc));
    });

    test('rejects application on revision mismatch with EDIT_REVISION_MISMATCH and leaves state untouched', () async {
      final clip = Clip.video(
        id: UuidV7.generate(),
        assetId: videoAsset.id,
        timelineStartTicks: 0,
        durationTicks: 3000000,
      );

      final txn = EditTransaction.single(AddClipCommand(trackId: trackV1.id, clip: clip));

      // service is at revision 0, caller expects revision 5
      final outcome = await service.apply(txn, expectedRevision: 5);

      expect(outcome.isFailure, isTrue);
      expect(outcome.error, isNotNull);
      expect(outcome.error!.code, equals('EDIT_REVISION_MISMATCH'));
      expect(outcome.error!.retryable, isTrue);
      expect(outcome.error!.category, equals('edit'));

      // Service state is 100% untouched
      expect(service.revision, equals(0));
      expect(service.canUndo, isFalse);
      expect(service.currentDocument.tracks[0].clips, isEmpty);
    });

    test('atomic rollback of a failing transaction: 0 changes committed on invariant failure', () async {
      final clip1 = Clip.video(
        id: UuidV7.generate(),
        assetId: videoAsset.id,
        timelineStartTicks: 0,
        durationTicks: 5000000,
      );

      // clip2 overlaps clip1 -> violates track overlap invariant!
      final clip2Bad = Clip.video(
        id: UuidV7.generate(),
        assetId: videoAsset.id,
        timelineStartTicks: 2000000, // overlaps!
        durationTicks: 4000000,
      );

      final txn = EditTransaction(
        description: 'Add two clips (second overlaps)',
        commands: [
          AddClipCommand(trackId: trackV1.id, clip: clip1),
          AddClipCommand(trackId: trackV1.id, clip: clip2Bad),
        ],
      );

      final outcome = await service.apply(txn, expectedRevision: 0);

      expect(outcome.isFailure, isTrue);
      expect(outcome.error!.code, equals('EDIT_INVALID_OPERATION'));

      // Complete atomic rollback: clip1 was NOT committed!
      expect(service.revision, equals(0));
      expect(service.canUndo, isFalse);
      expect(service.currentDocument.tracks[0].clips, isEmpty);
      expect(service.currentDocument, equals(initialDoc));
    });

    test('successful transaction commits state, increments revision, and adds to undo stack', () async {
      final clip = Clip.video(
        id: UuidV7.generate(),
        assetId: videoAsset.id,
        timelineStartTicks: 0,
        durationTicks: 3000000,
      );

      final txn = EditTransaction.single(AddClipCommand(trackId: trackV1.id, clip: clip));
      final outcome = await service.apply(txn, expectedRevision: 0);

      expect(outcome.isSuccess, isTrue);
      expect(service.revision, equals(1));
      expect(service.canUndo, isTrue);
      expect(service.canRedo, isFalse);
      expect(service.currentDocument.tracks[0].clips.length, equals(1));
    });

    test('undo/redo sequence restores exact document at every step', () async {
      final clip1 = Clip.video(
        id: UuidV7.generate(),
        assetId: videoAsset.id,
        timelineStartTicks: 0,
        durationTicks: 2000000,
      );
      final clip2 = Clip.video(
        id: UuidV7.generate(),
        assetId: videoAsset.id,
        timelineStartTicks: 2000000,
        durationTicks: 3000000,
      );

      // Step 1: Add clip1 -> revision 1
      await service.apply(
        EditTransaction.single(AddClipCommand(trackId: trackV1.id, clip: clip1)),
        expectedRevision: 0,
      );
      final docAtRev1 = service.currentDocument;
      expect(service.revision, equals(1));

      // Step 2: Add clip2 -> revision 2
      await service.apply(
        EditTransaction.single(AddClipCommand(trackId: trackV1.id, clip: clip2)),
        expectedRevision: 1,
      );
      final docAtRev2 = service.currentDocument;
      expect(service.revision, equals(2));
      expect(docAtRev2.tracks[0].clips.length, equals(2));

      // Step 3: Undo step 2 -> revision 3, restores docAtRev1
      final undo1Outcome = await service.undo(expectedRevision: 2);
      expect(undo1Outcome.isSuccess, isTrue);
      expect(service.revision, equals(3));
      expect(service.currentDocument, equals(docAtRev1));
      expect(service.canUndo, isTrue);
      expect(service.canRedo, isTrue);

      // Step 4: Undo step 1 -> revision 4, restores initialDoc
      final undo2Outcome = await service.undo(expectedRevision: 3);
      expect(undo2Outcome.isSuccess, isTrue);
      expect(service.revision, equals(4));
      expect(service.currentDocument, equals(initialDoc));
      expect(service.canUndo, isFalse);
      expect(service.canRedo, isTrue);

      // Step 5: Redo step 1 -> revision 5, restores docAtRev1
      final redo1Outcome = await service.redo(expectedRevision: 4);
      expect(redo1Outcome.isSuccess, isTrue);
      expect(service.revision, equals(5));
      expect(service.currentDocument, equals(docAtRev1));

      // Step 6: Redo step 2 -> revision 6, restores docAtRev2
      final redo2Outcome = await service.redo(expectedRevision: 5);
      expect(redo2Outcome.isSuccess, isTrue);
      expect(service.revision, equals(6));
      expect(service.currentDocument, equals(docAtRev2));
      expect(service.canRedo, isFalse);
    });

    test('new edit after undo clears redo history (Spec §3.5.3)', () async {
      final clip1 = Clip.video(
        id: UuidV7.generate(),
        assetId: videoAsset.id,
        timelineStartTicks: 0,
        durationTicks: 2000000,
      );
      final clip2 = Clip.video(
        id: UuidV7.generate(),
        assetId: videoAsset.id,
        timelineStartTicks: 2000000,
        durationTicks: 3000000,
      );
      final clipAlternative = Clip.video(
        id: UuidV7.generate(),
        assetId: videoAsset.id,
        timelineStartTicks: 5000000,
        durationTicks: 1000000,
      );

      // Add clip1 (rev 1), then clip2 (rev 2)
      await service.apply(
        EditTransaction.single(AddClipCommand(trackId: trackV1.id, clip: clip1)),
        expectedRevision: 0,
      );
      await service.apply(
        EditTransaction.single(AddClipCommand(trackId: trackV1.id, clip: clip2)),
        expectedRevision: 1,
      );

      // Undo clip2 -> rev 3
      await service.undo(expectedRevision: 2);
      expect(service.canRedo, isTrue);

      // Apply alternative edit -> rev 4
      await service.apply(
        EditTransaction.single(AddClipCommand(trackId: trackV1.id, clip: clipAlternative)),
        expectedRevision: 3,
      );

      // Redo stack must be cleared!
      expect(service.canRedo, isFalse);
      expect(service.redoStackDepth, equals(0));

      final attemptRedo = await service.redo(expectedRevision: 4);
      expect(attemptRedo.isFailure, isTrue);
      expect(attemptRedo.error!.code, equals('EDIT_INVALID_OPERATION'));
    });

    test('undo on empty stack fails with EDIT_INVALID_OPERATION', () async {
      final outcome = await service.undo(expectedRevision: 0);
      expect(outcome.isFailure, isTrue);
      expect(outcome.error!.code, equals('EDIT_INVALID_OPERATION'));
      expect(service.revision, equals(0));
    });

    test('determinism: apply -> undo -> redo yields a document equal to the first apply', () async {
      final clip = Clip.video(
        id: UuidV7.generate(),
        assetId: videoAsset.id,
        timelineStartTicks: 1000000,
        durationTicks: 8000000,
        sourceInTicks: 1000000,
      );

      // Base: add the clip
      await service.apply(
        EditTransaction.single(AddClipCommand(trackId: trackV1.id, clip: clip)),
        expectedRevision: 0,
      );

      // Split clip with a specified new clip ID (pure, deterministic inputs)
      final secondClipId = UuidV7.generate();
      final splitTxn = EditTransaction.single(
        SplitClipCommand(
          trackId: trackV1.id,
          clipId: clip.id,
          splitAtTick: 4000000,
          newClipId: secondClipId,
        ),
      );

      final firstApplyOutcome = await service.apply(splitTxn, expectedRevision: 1);
      expect(firstApplyOutcome.isSuccess, isTrue);
      final documentAfterFirstApply = service.currentDocument;

      // Undo the split
      final undoOutcome = await service.undo(expectedRevision: 2);
      expect(undoOutcome.isSuccess, isTrue);

      // Redo the split
      final redoOutcome = await service.redo(expectedRevision: 3);
      expect(redoOutcome.isSuccess, isTrue);

      // Strict document equality check: apply -> undo -> redo yields identical document
      expect(service.currentDocument, equals(documentAfterFirstApply));
    });

    test('save without file path throws ShadowError.invalidOperation', () {
      expect(
        () => service.save(),
        throwsA(
          isA<ShadowError>().having(
            (e) => e.code,
            'code',
            'EDIT_INVALID_OPERATION',
          ),
        ),
      );
    });

    test('resolveGraph throws revision mismatch on mismatched revision', () {
      expect(
        () => service.resolveGraph(
          revision: 999,
          range: const RangeTicks(startTicks: 0, durationTicks: 1000000),
        ),
        throwsA(
          isA<ShadowError>().having(
            (e) => e.code,
            'code',
            'EDIT_REVISION_MISMATCH',
          ),
        ),
      );
    });

    test('resolveGraph resolves valid RenderGraph at current revision', () {
      final graph = service.resolveGraph(
        revision: service.revision,
        range: const RangeTicks(startTicks: 0, durationTicks: 1000000),
      );
      expect(graph.graphSchema, equals('shadow.rendergraph/1'));
      expect(graph.projectRevision, equals(service.revision));
      expect(graph.range.durationTicks, equals(1000000));
    });
  });
}
