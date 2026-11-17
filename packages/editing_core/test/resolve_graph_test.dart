import 'package:editing_core/editing_core.dart';
import 'package:test/test.dart';

void main() {
  group('EditingService.resolveGraph (Phase 3 RenderGraph Derivation)', () {
    late DefaultEditingService service;
    late ProjectDocument testDoc;

    final introAsset = Asset(
      id: '0198f3b2-b000-7000-8000-0000000000aa',
      kind: AssetKind.video,
      uri: 'file:///media/user/broll/intro-4k.mp4',
      durationTicks: 10000000,
      hash: '9f2c1d4e5a6b7c8d9e0f1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f',
    );

    final outroAsset = Asset(
      id: '0198f3b2-b000-7000-8000-0000000000ab',
      kind: AssetKind.video,
      uri: 'file:///media/user/broll/outro-hd.mp4',
      durationTicks: 15000000,
      hash: '1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7f809',
    );

    final audioAsset = Asset(
      id: '0198f3b2-b000-7000-8000-0000000000ac',
      kind: AssetKind.audio,
      uri: 'file:///media/user/audio/vo-take3.wav',
      durationTicks: 12000000,
      hash: '7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e',
    );

    setUp(() {
      final videoClip1 = Clip.video(
        id: '0198f3b3-0001-7000-8000-0000000000a1',
        assetId: introAsset.id,
        timelineStartTicks: 0,
        durationTicks: 4000000,
        sourceInTicks: 500000,
        speedNum: 1,
        speedDen: 1,
        label: 'intro',
        transform: const TransformBox.identity(),
        effects: [
          Effect(
            id: '0198f3b3-1001-7000-8000-0000000000e1',
            effectKey: 'shadow.blur.gaussian',
            enabled: true,
            params: [
              const Param(
                name: 'radius_px',
                type: 'int',
                value: 12,
                keyframes: [],
              ),
              const Param(
                name: 'amount_ppm',
                type: 'ppm',
                value: 0,
                keyframes: [
                  Keyframe(atTicks: 0, value: 0, easing: 'linear'),
                  Keyframe(atTicks: 2000000, value: 500000, easing: 'ease_in_out'),
                ],
              ),
            ],
          ),
        ],
      );

      final videoClip2 = Clip.video(
        id: '0198f3b3-0002-7000-8000-0000000000a2',
        assetId: outroAsset.id,
        timelineStartTicks: 4000000,
        durationTicks: 6000000,
        sourceInTicks: 0,
        speedNum: 1,
        speedDen: 1,
        label: 'outro',
      );

      final transition = Transition(
        id: '0198f3b4-0001-7000-8000-0000000000c1',
        kind: 'crossfade',
        atTicks: 4000000,
        durationTicks: 1000000,
        fromClipId: videoClip1.id,
        toClipId: videoClip2.id,
      );

      final textLayer = TextLayer(
        id: '0198f3b5-0001-7000-8000-0000000000d1',
        rasterUri: 'file:///home/user/.cache/shadow-studio/derived/4f/4f9c2d1e8a7b.rgba',
        rasterHash: '4f9c2d1e8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d',
        rasterWidth: 1200,
        rasterHeight: 180,
        startTicks: 1000000,
        durationTicks: 3000000,
        opacityPpm: 1000000,
        transform: const TransformBox(
          xPx: 0,
          yPx: 820,
          scaleXPpm: 1000000,
          scaleYPpm: 1000000,
          anchor: 'top_left',
        ),
        animationIn: const TextLayerAnimation.fade(250000),
        animationOut: const TextLayerAnimation.none(),
      );

      final audioClip = Clip.audio(
        id: '0198f3b6-0001-7000-8000-0000000000f1',
        assetId: audioAsset.id,
        timelineStartTicks: 0,
        durationTicks: 10000000,
        sourceInTicks: 0,
        speedNum: 1,
        speedDen: 1,
        gainMb: -3000,
        fadeInTicks: 200000,
        fadeOutTicks: 400000,
      );

      testDoc = ProjectDocument(
        id: '0198f3b2-7c41-7f0a-9a1e-3d1c2b4a5e60',
        sequenceId: '0198f3b2-7c41-7f0a-9a1e-3d1c2b4a5e60',
        name: 'Phase 3 Golden Project',
        profile: ProjectProfile.hd1080p(),
        timebase: Timebase.ntsc2997(),
        tracks: [
          Track(
            id: '0198f3b2-9000-7000-8000-000000000001',
            kind: TrackKind.video,
            position: 0,
            name: 'V1',
            clips: [videoClip1, videoClip2],
            transitions: [transition],
          ),
          Track(
            id: '0198f3b2-9000-7000-8000-000000000002',
            kind: TrackKind.overlay,
            position: 1,
            name: 'T1',
            textLayers: [textLayer],
          ),
          Track(
            id: '0198f3b2-9000-7000-8000-000000000003',
            kind: TrackKind.audio,
            position: 2,
            name: 'A1',
            gainMb: 0,
            panPpm: 0,
            clips: [audioClip],
          ),
        ],
        assets: {
          introAsset.id: introAsset,
          outroAsset.id: outroAsset,
          audioAsset.id: audioAsset,
        },
      );

      service = DefaultEditingService(
        initialDocument: testDoc,
        initialRevision: 218,
      );
    });

    test('revision mismatch throws EDIT_REVISION_MISMATCH with zero mutation', () {
      expect(
        () => service.resolveGraph(
          revision: 217,
          range: const RangeTicks(startTicks: 0, durationTicks: 10000000),
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

    test('invalid range bounds throw AssertionError on RangeTicks creation', () {
      expect(
        () => RangeTicks(startTicks: -100, durationTicks: 10000000),
        throwsA(isA<AssertionError>()),
      );

      expect(
        () => RangeTicks(startTicks: 0, durationTicks: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('resolves full timeline range matching RenderGraph schema and bounds', () {
      final graph = service.resolveGraph(
        revision: 218,
        range: const RangeTicks(startTicks: 0, durationTicks: 10000000),
      );

      expect(graph.graphSchema, equals('shadow.rendergraph/1'));
      expect(graph.sequenceId, equals('0198f3b2-7c41-7f0a-9a1e-3d1c2b4a5e60'));
      expect(graph.projectRevision, equals(218));
      expect(graph.backgroundRgba, equals('#000000FF'));
      expect(graph.tracks.length, equals(3));

      // Video track
      final vTrack = graph.tracks[0];
      expect(vTrack.kind, equals(TrackKind.video));
      expect(vTrack.position, equals(0));
      expect(vTrack.clips?.length, equals(2));
      expect(vTrack.transitions?.length, equals(1));

      final vClip1 = vTrack.clips![0];
      expect(vClip1.id, equals('0198f3b3-0001-7000-8000-0000000000a1'));
      expect(vClip1.sourceUri, equals('file:///media/user/broll/intro-4k.mp4'));
      expect(vClip1.sourceHash, equals('9f2c1d4e5a6b7c8d9e0f1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f'));
      expect(vClip1.effects.length, equals(1));
      expect(vClip1.effects[0].effectKey, equals('shadow.blur.gaussian'));

      // Overlay track
      final tTrack = graph.tracks[1];
      expect(tTrack.kind, equals(TrackKind.overlay));
      expect(tTrack.position, equals(1));
      expect(tTrack.textLayers?.length, equals(1));

      // Audio track
      final aTrack = graph.tracks[2];
      expect(aTrack.kind, equals(TrackKind.audio));
      expect(aTrack.position, equals(2));
      expect(aTrack.audioClips?.length, equals(1));
      expect(aTrack.gainMb, equals(0));
      expect(aTrack.panPpm, equals(0));
      final aClip = aTrack.audioClips![0];
      expect(aClip.gainMb, equals(-3000));
      expect(aClip.fadeInTicks, equals(200000));
      expect(aClip.fadeOutTicks, equals(400000));
    });

    test('sub-range slicing correctly clamps clips and scales source offsets', () {
      // Sub-range: 2,000,000 to 5,000,000 (duration: 3,000,000)
      // videoClip1 was [0, 4,000,000) with sourceIn = 500,000
      // Inside sub-range: [2,000,000, 4,000,000), sliced duration = 2,000,000
      // sourceIn = 500,000 + 2,000,000 = 2,500,000
      // videoClip2 was [4,000,000, 10,000,000) with sourceIn = 0
      // Inside sub-range: [4,000,000, 5,000,000), sliced duration = 1,000,000
      // Transition was at 4,000,000 with duration 1,000,000 (window [4000000, 5000000))
      // Both clips and transition fit!
      final graph = service.resolveGraph(
        revision: 218,
        range: const RangeTicks(startTicks: 2000000, durationTicks: 3000000),
      );

      final vTrack = graph.tracks[0];
      expect(vTrack.clips?.length, equals(2));

      final c1 = vTrack.clips![0];
      expect(c1.timelineStartTicks, equals(2000000));
      expect(c1.durationTicks, equals(2000000));
      expect(c1.sourceInTicks, equals(2500000));

      final c2 = vTrack.clips![1];
      expect(c2.timelineStartTicks, equals(4000000));
      expect(c2.durationTicks, equals(1000000));
      expect(c2.sourceInTicks, equals(0));

      // Audio clip [0, 10,000,000) sliced to [2,000,000, 5,000,000)
      final aTrack = graph.tracks[2];
      expect(aTrack.audioClips?.length, equals(1));
      final ac = aTrack.audioClips![0];
      expect(ac.timelineStartTicks, equals(2000000));
      expect(ac.durationTicks, equals(3000000));
      expect(ac.sourceInTicks, equals(2000000));
    });

    test('sub-range completely excluding clips leaves tracks empty without error', () {
      // Sub-range: 15,000,000 to 18,000,000 (beyond document duration)
      final graph = service.resolveGraph(
        revision: 218,
        range: const RangeTicks(startTicks: 15000000, durationTicks: 3000000),
      );

      expect(graph.tracks[0].clips, isEmpty);
      expect(graph.tracks[0].transitions, isEmpty);
      expect(graph.tracks[1].textLayers, isEmpty);
      expect(graph.tracks[2].audioClips, isEmpty);
    });
  });
}
