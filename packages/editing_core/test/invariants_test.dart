import 'package:editing_core/editing_core.dart';
import 'package:test/test.dart';

void main() {
  group('DocumentInvariants', () {
    late Asset videoAsset;
    late Asset audioAsset;

    setUp(() {
      videoAsset = Asset(
        id: UuidV7.generate(),
        kind: AssetKind.video,
        uri: 'file:///media/video.mp4',
        durationTicks: 10000000, // 10s
      );
      audioAsset = Asset(
        id: UuidV7.generate(),
        kind: AssetKind.audio,
        uri: 'file:///media/audio.wav',
        durationTicks: 8000000, // 8s
      );
    });

    test('valid document passes invariant checks without error', () {
      final doc = ProjectDocument(
        name: 'Valid Doc',
        profile: ProjectProfile.hd1080p(),
        timebase: Timebase.fps30(),
        tracks: [
          Track(
            id: UuidV7.generate(),
            kind: TrackKind.video,
            position: 0,
            name: 'V1',
            clips: [
              Clip.video(
                id: UuidV7.generate(),
                assetId: videoAsset.id,
                timelineStartTicks: 0,
                durationTicks: 4000000,
                sourceInTicks: 0,
              ),
              Clip.video(
                id: UuidV7.generate(),
                assetId: videoAsset.id,
                timelineStartTicks: 4000000, // touching boundary is valid
                durationTicks: 3000000,
                sourceInTicks: 4000000,
              ),
            ],
          ),
        ],
        assets: {videoAsset.id: videoAsset},
      );

      expect(() => DocumentInvariants.validate(doc), returnsNormally);
      expect(DocumentInvariants.check(doc), isEmpty);
    });

    test('rejects overlapping clips on the same track with EDIT_INVALID_OPERATION', () {
      final doc = ProjectDocument(
        name: 'Overlapping',
        profile: ProjectProfile.hd1080p(),
        timebase: Timebase.fps30(),
        tracks: [
          Track(
            id: UuidV7.generate(),
            kind: TrackKind.video,
            position: 0,
            name: 'V1',
            clips: [
              Clip.video(
                id: UuidV7.generate(),
                assetId: videoAsset.id,
                timelineStartTicks: 0,
                durationTicks: 5000000, // ends at 5s
              ),
              Clip.video(
                id: UuidV7.generate(),
                assetId: videoAsset.id,
                timelineStartTicks: 4000000, // starts at 4s -> overlaps by 1s!
                durationTicks: 3000000,
              ),
            ],
          ),
        ],
        assets: {videoAsset.id: videoAsset},
      );

      final violations = DocumentInvariants.check(doc);
      expect(violations, isNotEmpty);
      expect(violations.first, contains('Overlap on track'));

      expect(
        () => DocumentInvariants.validate(doc),
        throwsA(
          isA<ShadowError>()
              .having((e) => e.code, 'code', 'EDIT_INVALID_OPERATION')
              .having((e) => e.retryable, 'retryable', isFalse),
        ),
      );
    });

    test('rejects clip exceeding asset bounds with EDIT_INVALID_OPERATION', () {
      final doc = ProjectDocument(
        name: 'Out of bounds',
        profile: ProjectProfile.hd1080p(),
        timebase: Timebase.fps30(),
        tracks: [
          Track(
            id: UuidV7.generate(),
            kind: TrackKind.video,
            position: 0,
            name: 'V1',
            clips: [
              Clip.video(
                id: UuidV7.generate(),
                assetId: videoAsset.id,
                timelineStartTicks: 0,
                durationTicks: 6000000,
                sourceInTicks: 6000000, // 6s + 6s = 12s > asset's 10s!
              ),
            ],
          ),
        ],
        assets: {videoAsset.id: videoAsset},
      );

      expect(
        () => DocumentInvariants.validate(doc),
        throwsA(
          isA<ShadowError>()
              .having((e) => e.code, 'code', 'EDIT_INVALID_OPERATION')
              .having((e) => e.details['violations'].toString(), 'violations', contains('exceeds asset')),
        ),
      );
    });

    test('rejects non-positive duration with EDIT_INVALID_OPERATION', () {
      // In constructor, clip checks durationTicks >= 1
      expect(
        () => Clip.video(
          id: UuidV7.generate(),
          assetId: videoAsset.id,
          timelineStartTicks: 0,
          durationTicks: 0,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects asset kind not matching track kind with EDIT_INVALID_OPERATION', () {
      // Audio asset on Video track
      final docBadVideo = ProjectDocument(
        name: 'Mismatched Audio on Video',
        profile: ProjectProfile.hd1080p(),
        timebase: Timebase.fps30(),
        tracks: [
          Track(
            id: UuidV7.generate(),
            kind: TrackKind.video,
            position: 0,
            name: 'V1',
            clips: [
              Clip(
                id: UuidV7.generate(),
                assetId: audioAsset.id,
                kind: ClipKind.video,
                timelineStartTicks: 0,
                durationTicks: 2000000,
              ),
            ],
          ),
        ],
        assets: {audioAsset.id: audioAsset},
      );

      expect(
        () => DocumentInvariants.validate(docBadVideo),
        throwsA(
          isA<ShadowError>().having((e) => e.code, 'code', 'EDIT_INVALID_OPERATION'),
        ),
      );

      // Video asset on Audio track
      final docBadAudio = ProjectDocument(
        name: 'Mismatched Video on Audio',
        profile: ProjectProfile.hd1080p(),
        timebase: Timebase.fps30(),
        tracks: [
          Track(
            id: UuidV7.generate(),
            kind: TrackKind.audio,
            position: 0,
            name: 'A1',
            clips: [
              Clip.audio(
                id: UuidV7.generate(),
                assetId: videoAsset.id,
                timelineStartTicks: 0,
                durationTicks: 2000000,
              ),
            ],
          ),
        ],
        assets: {videoAsset.id: videoAsset},
      );

      expect(
        () => DocumentInvariants.validate(docBadAudio),
        throwsA(
          isA<ShadowError>().having((e) => e.code, 'code', 'EDIT_INVALID_OPERATION'),
        ),
      );
    });

    test('rejects duplicate IDs with EDIT_INVALID_OPERATION', () {
      final sharedClipId = UuidV7.generate();

      final doc = ProjectDocument(
        name: 'Duplicate Clip IDs',
        profile: ProjectProfile.hd1080p(),
        timebase: Timebase.fps30(),
        tracks: [
          Track(
            id: UuidV7.generate(),
            kind: TrackKind.video,
            position: 0,
            name: 'V1',
            clips: [
              Clip.video(
                id: sharedClipId,
                assetId: videoAsset.id,
                timelineStartTicks: 0,
                durationTicks: 2000000,
              ),
            ],
          ),
          Track(
            id: UuidV7.generate(),
            kind: TrackKind.video,
            position: 1,
            name: 'V2',
            clips: [
              Clip.video(
                id: sharedClipId,
                assetId: videoAsset.id,
                timelineStartTicks: 0,
                durationTicks: 2000000,
              ),
            ],
          ),
        ],
        assets: {videoAsset.id: videoAsset},
      );

      expect(
        () => DocumentInvariants.validate(doc),
        throwsA(
          isA<ShadowError>()
              .having((e) => e.code, 'code', 'EDIT_INVALID_OPERATION')
              .having((e) => e.message, 'message', contains('Duplicate clip ID')),
        ),
      );
    });

    test('rejects transitions not on cut boundary or exceeding duration limit', () {
      final clip1 = Clip.video(
        id: UuidV7.generate(),
        assetId: videoAsset.id,
        timelineStartTicks: 0,
        durationTicks: 4000000, // 0..4s
      );
      final clip2 = Clip.video(
        id: UuidV7.generate(),
        assetId: videoAsset.id,
        timelineStartTicks: 4000000, // 4..7s
        durationTicks: 3000000,
      );

      // Transition off the boundary (at 3s instead of 4s)
      final docBadBoundary = ProjectDocument(
        name: 'Bad Transition Boundary',
        profile: ProjectProfile.hd1080p(),
        timebase: Timebase.fps30(),
        tracks: [
          Track(
            id: UuidV7.generate(),
            kind: TrackKind.video,
            position: 0,
            name: 'V1',
            clips: [clip1, clip2],
            transitions: [
              Transition(
                id: UuidV7.generate(),
                kind: 'crossfade',
                atTicks: 3000000, // Not at cut point 4000000!
                durationTicks: 1000000,
                fromClipId: clip1.id,
                toClipId: clip2.id,
              ),
            ],
          ),
        ],
        assets: {videoAsset.id: videoAsset},
      );

      expect(
        () => DocumentInvariants.validate(docBadBoundary),
        throwsA(
          isA<ShadowError>()
              .having((e) => e.code, 'code', 'EDIT_INVALID_OPERATION')
              .having((e) => e.details['violations'].toString(), 'violations', contains('not on boundary')),
        ),
      );

      // Transition duration exceeding half the shortest clip
      // shortest clip is clip2 (3s = 3000000 ticks). Max allowed transition = 1500000 ticks.
      final docBadDuration = ProjectDocument(
        name: 'Bad Transition Duration',
        profile: ProjectProfile.hd1080p(),
        timebase: Timebase.fps30(),
        tracks: [
          Track(
            id: UuidV7.generate(),
            kind: TrackKind.video,
            position: 0,
            name: 'V1',
            clips: [clip1, clip2],
            transitions: [
              Transition(
                id: UuidV7.generate(),
                kind: 'crossfade',
                atTicks: 4000000,
                durationTicks: 2000000, // > 1500000!
                fromClipId: clip1.id,
                toClipId: clip2.id,
              ),
            ],
          ),
        ],
        assets: {videoAsset.id: videoAsset},
      );

      expect(
        () => DocumentInvariants.validate(docBadDuration),
        throwsA(
          isA<ShadowError>()
              .having((e) => e.code, 'code', 'EDIT_INVALID_OPERATION')
              .having((e) => e.details['violations'].toString(), 'violations', contains('exceeds half')),
        ),
      );
    });
  });
}
