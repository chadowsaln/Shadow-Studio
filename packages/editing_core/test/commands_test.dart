import 'package:editing_core/editing_core.dart';
import 'package:test/test.dart';

void main() {
  group('Pure Commands and Inverses', () {
    late ProjectDocument baseDoc;
    late Asset sampleVideoAsset;
    late Asset sampleAudioAsset;

    setUp(() {
      sampleVideoAsset = Asset(
        id: UuidV7.generate(),
        kind: AssetKind.video,
        uri: 'file:///workspace/media/intro.mp4',
        durationTicks: 10000000, // 10 seconds
        hash: '0' * 64,
      );

      sampleAudioAsset = Asset(
        id: UuidV7.generate(),
        kind: AssetKind.audio,
        uri: 'file:///workspace/media/voice.wav',
        durationTicks: 15000000, // 15 seconds
        hash: '1' * 64,
      );

      final track0 = Track(
        id: UuidV7.generate(),
        kind: TrackKind.video,
        position: 0,
        name: 'V1',
      );

      final track1 = Track(
        id: UuidV7.generate(),
        kind: TrackKind.audio,
        position: 1,
        name: 'A1',
      );

      baseDoc = ProjectDocument(
        name: 'Test Project',
        profile: ProjectProfile.hd1080p(),
        timebase: Timebase.ntsc2997(),
        tracks: [track0, track1],
        assets: {
          sampleVideoAsset.id: sampleVideoAsset,
          sampleAudioAsset.id: sampleAudioAsset,
        },
      );
    });

    test('AddTrackCommand and inverse restores exact previous document', () {
      final newTrack = Track(
        id: UuidV7.generate(),
        kind: TrackKind.video,
        position: 1,
        name: 'V2',
      );

      final cmd = AddTrackCommand(newTrack);
      final forwardResult = cmd.execute(baseDoc);

      expect(forwardResult.document.tracks.length, equals(3));
      expect(forwardResult.document.tracks[1].id, equals(newTrack.id));
      expect(forwardResult.document.tracks[1].position, equals(1));
      expect(forwardResult.document.tracks[2].position, equals(2));

      // Execute inverse
      final inverseResult = forwardResult.inverse.execute(forwardResult.document);
      expect(inverseResult.document, equals(baseDoc));
    });

    test('RemoveTrackCommand and inverse restores exact previous document', () {
      final trackToRemove = baseDoc.tracks[0];
      final cmd = RemoveTrackCommand(trackId: trackToRemove.id);

      final forwardResult = cmd.execute(baseDoc);
      expect(forwardResult.document.tracks.length, equals(1));
      expect(forwardResult.document.tracks[0].position, equals(0));

      // Execute inverse
      final inverseResult = forwardResult.inverse.execute(forwardResult.document);
      expect(inverseResult.document, equals(baseDoc));
    });

    test('AddClipCommand and inverse restores exact previous document', () {
      final clip = Clip.video(
        id: UuidV7.generate(),
        assetId: sampleVideoAsset.id,
        timelineStartTicks: 0,
        durationTicks: 3000000, // 3 seconds
        sourceInTicks: 1000000,
        label: 'Intro Clip',
      );

      final cmd = AddClipCommand(trackId: baseDoc.tracks[0].id, clip: clip);
      final forwardResult = cmd.execute(baseDoc);

      expect(forwardResult.document.tracks[0].clips.length, equals(1));
      expect(forwardResult.document.tracks[0].clips[0].id, equals(clip.id));

      // Execute inverse
      final inverseResult = forwardResult.inverse.execute(forwardResult.document);
      expect(inverseResult.document, equals(baseDoc));
    });

    test('RemoveClipCommand and inverse restores exact previous document', () {
      final clip = Clip.video(
        id: UuidV7.generate(),
        assetId: sampleVideoAsset.id,
        timelineStartTicks: 0,
        durationTicks: 2000000,
      );

      final docWithClip = AddClipCommand(
        trackId: baseDoc.tracks[0].id,
        clip: clip,
      ).execute(baseDoc).document;

      final cmd = RemoveClipCommand(
        trackId: docWithClip.tracks[0].id,
        clipId: clip.id,
      );
      final forwardResult = cmd.execute(docWithClip);
      expect(forwardResult.document.tracks[0].clips, isEmpty);

      // Execute inverse
      final inverseResult = forwardResult.inverse.execute(forwardResult.document);
      expect(inverseResult.document, equals(docWithClip));
    });

    test('MoveClipCommand within same track and inverse restores exact previous document', () {
      final clip = Clip.video(
        id: UuidV7.generate(),
        assetId: sampleVideoAsset.id,
        timelineStartTicks: 1000000,
        durationTicks: 2000000,
      );

      final docWithClip = AddClipCommand(
        trackId: baseDoc.tracks[0].id,
        clip: clip,
      ).execute(baseDoc).document;

      final cmd = MoveClipCommand(
        clipId: clip.id,
        fromTrackId: baseDoc.tracks[0].id,
        toTrackId: baseDoc.tracks[0].id,
        newTimelineStartTicks: 4000000,
      );

      final forwardResult = cmd.execute(docWithClip);
      expect(forwardResult.document.tracks[0].clips[0].timelineStartTicks, equals(4000000));

      // Execute inverse
      final inverseResult = forwardResult.inverse.execute(forwardResult.document);
      expect(inverseResult.document, equals(docWithClip));
    });

    test('MoveClipCommand across tracks and inverse restores exact previous document', () {
      // Add another video track
      final track2 = Track(
        id: UuidV7.generate(),
        kind: TrackKind.video,
        position: 2,
        name: 'V2',
      );
      final docWith2Tracks = AddTrackCommand(track2).execute(baseDoc).document;

      final clip = Clip.video(
        id: UuidV7.generate(),
        assetId: sampleVideoAsset.id,
        timelineStartTicks: 0,
        durationTicks: 2000000,
      );

      final docWithClip = AddClipCommand(
        trackId: docWith2Tracks.tracks[0].id,
        clip: clip,
      ).execute(docWith2Tracks).document;

      final cmd = MoveClipCommand(
        clipId: clip.id,
        fromTrackId: docWithClip.tracks[0].id,
        toTrackId: track2.id,
        newTimelineStartTicks: 5000000,
      );

      final forwardResult = cmd.execute(docWithClip);
      expect(forwardResult.document.findTrack(docWithClip.tracks[0].id)!.clips, isEmpty);
      expect(forwardResult.document.findTrack(track2.id)!.clips.length, equals(1));
      expect(forwardResult.document.findTrack(track2.id)!.clips[0].timelineStartTicks, equals(5000000));

      // Execute inverse
      final inverseResult = forwardResult.inverse.execute(forwardResult.document);
      expect(inverseResult.document, equals(docWithClip));
    });

    test('TrimClipCommand and inverse restores exact previous document', () {
      final clip = Clip.video(
        id: UuidV7.generate(),
        assetId: sampleVideoAsset.id,
        timelineStartTicks: 1000000,
        durationTicks: 4000000,
        sourceInTicks: 1000000,
      );

      final docWithClip = AddClipCommand(
        trackId: baseDoc.tracks[0].id,
        clip: clip,
      ).execute(baseDoc).document;

      final cmd = TrimClipCommand(
        trackId: baseDoc.tracks[0].id,
        clipId: clip.id,
        newTimelineStartTicks: 1500000,
        newDurationTicks: 3000000,
        newSourceInTicks: 1500000,
      );

      final forwardResult = cmd.execute(docWithClip);
      final trimmedClip = forwardResult.document.tracks[0].clips[0];
      expect(trimmedClip.timelineStartTicks, equals(1500000));
      expect(trimmedClip.durationTicks, equals(3000000));
      expect(trimmedClip.sourceInTicks, equals(1500000));

      // Execute inverse
      final inverseResult = forwardResult.inverse.execute(forwardResult.document);
      expect(inverseResult.document, equals(docWithClip));
    });

    test('SplitClipCommand and inverse restores exact previous document', () {
      final clip = Clip.video(
        id: UuidV7.generate(),
        assetId: sampleVideoAsset.id,
        timelineStartTicks: 1000000,
        durationTicks: 6000000, // 6 seconds [1s..7s]
        sourceInTicks: 1000000,
      );

      final docWithClip = AddClipCommand(
        trackId: baseDoc.tracks[0].id,
        clip: clip,
      ).execute(baseDoc).document;

      final newClipId = UuidV7.generate();
      final splitAtTick = 4000000; // cut at 4s (3s into clip)

      final cmd = SplitClipCommand(
        trackId: baseDoc.tracks[0].id,
        clipId: clip.id,
        splitAtTick: splitAtTick,
        newClipId: newClipId,
      );

      final forwardResult = cmd.execute(docWithClip);
      final clips = forwardResult.document.tracks[0].clips;
      expect(clips.length, equals(2));

      // First piece
      expect(clips[0].id, equals(clip.id));
      expect(clips[0].timelineStartTicks, equals(1000000));
      expect(clips[0].durationTicks, equals(3000000));
      expect(clips[0].sourceInTicks, equals(1000000));

      // Second piece
      expect(clips[1].id, equals(newClipId));
      expect(clips[1].timelineStartTicks, equals(4000000));
      expect(clips[1].durationTicks, equals(3000000));
      expect(clips[1].sourceInTicks, equals(4000000));

      // Execute inverse (JoinClipCommand)
      final inverseResult = forwardResult.inverse.execute(forwardResult.document);
      expect(inverseResult.document, equals(docWithClip));
    });

    test('AddAssetCommand and RemoveAssetCommand inverses restore exact document', () {
      final newAsset = Asset(
        id: UuidV7.generate(),
        kind: AssetKind.image,
        uri: 'file:///workspace/media/logo.png',
        durationTicks: 5000000,
      );

      final addCmd = AddAssetCommand(newAsset);
      final addResult = addCmd.execute(baseDoc);
      expect(addResult.document.assets.containsKey(newAsset.id), isTrue);

      // Inverse of add is remove
      final removeResult = addResult.inverse.execute(addResult.document);
      expect(removeResult.document, equals(baseDoc));

      // Direct remove command and inverse
      final directRemoveCmd = RemoveAssetCommand(assetId: sampleAudioAsset.id);
      final directRemoveResult = directRemoveCmd.execute(baseDoc);
      expect(directRemoveResult.document.assets.containsKey(sampleAudioAsset.id), isFalse);

      final restoreAssetResult = directRemoveResult.inverse.execute(directRemoveResult.document);
      expect(restoreAssetResult.document, equals(baseDoc));
    });
  });
}
