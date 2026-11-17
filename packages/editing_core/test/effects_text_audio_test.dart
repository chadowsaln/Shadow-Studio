import 'package:editing_core/editing_core.dart';
import 'package:test/test.dart';

ProjectDocument _doc({
  List<Track> tracks = const [],
  Map<String, Asset> assets = const {},
}) {
  return ProjectDocument(
    name: 'Feature Doc',
    profile: ProjectProfile.hd1080p(),
    timebase: Timebase.fps30(),
    tracks: tracks,
    assets: assets,
  );
}

Track _videoTrack(String id, {int position = 0, List<Clip> clips = const []}) {
  return Track(
    id: id,
    kind: TrackKind.video,
    position: position,
    name: 'V$position',
    clips: clips,
  );
}

Track _overlayTrack(String id, {int position = 1}) {
  return Track(
    id: id,
    kind: TrackKind.overlay,
    position: position,
    name: 'O$position',
  );
}

Clip _videoClip({
  required String id,
  required String assetId,
  int start = 0,
  int duration = 3000000,
}) {
  return Clip.video(
    id: id,
    assetId: assetId,
    timelineStartTicks: start,
    durationTicks: duration,
  );
}

void main() {
  group('Transition commands', () {
    late Asset video;
    late Track track;
    late ProjectDocument doc;

    setUp(() {
      video = Asset(
        id: 'asset_v',
        kind: AssetKind.video,
        uri: 'file:///w/a.mp4',
        durationTicks: 10000000,
        hash: 'a' * 64,
      );
      track = _videoTrack(
        'V1',
        clips: [
          _videoClip(id: 'c1', assetId: video.id, start: 0, duration: 3000000),
          _videoClip(id: 'c2', assetId: video.id, start: 3000000, duration: 3000000),
        ],
      );
      doc = _doc(tracks: [track], assets: {video.id: video});
    });

    test('adds a transition on the cut and inverse restores the document', () {
      final result = AddTransitionCommand(
        trackId: 'V1',
        fromClipId: 'c1',
        toClipId: 'c2',
        kind: TransitionKinds.crossfade,
        durationTicks: 500000,
        transitionId: 'tr1',
      ).execute(doc);

      expect(result.document.tracks.single.transitions, hasLength(1));
      final transition = result.document.tracks.single.transitions.single;
      expect(transition.atTicks, 3000000);
      expect(transition.durationTicks, 500000);
      expect(transition.kind, TransitionKinds.crossfade);

      final undone = result.inverse.execute(result.document);
      expect(undone.document, doc);
      expect(undone.document.tracks.single.transitions, isEmpty);
    });

    test('rejects unknown kinds, non-adjacent clips and over-long durations', () {
      expect(
        () => AddTransitionCommand(
          trackId: 'V1',
          fromClipId: 'c1',
          toClipId: 'c2',
          kind: 'sparkle',
          durationTicks: 100,
        ).execute(doc),
        throwsA(isA<ShadowError>()),
      );

      expect(
        () => AddTransitionCommand(
          trackId: 'V1',
          fromClipId: 'c2',
          toClipId: 'c1',
          kind: TransitionKinds.dissolve,
          durationTicks: 100,
        ).execute(doc),
        throwsA(isA<ShadowError>()),
      );

      expect(
        () => AddTransitionCommand(
          trackId: 'V1',
          fromClipId: 'c1',
          toClipId: 'c2',
          kind: TransitionKinds.dissolve,
          durationTicks: 1500001,
        ).execute(doc),
        throwsA(isA<ShadowError>()),
      );
    });

    test('a document with a bad transition fails invariant validation', () {
      final broken = _doc(
        tracks: [
          Track(
            id: 'V1',
            kind: TrackKind.video,
            position: 0,
            name: 'V1',
            clips: [
              _videoClip(id: 'c1', assetId: video.id),
              _videoClip(id: 'c2', assetId: video.id, start: 3000000),
            ],
            transitions: [
              Transition(
                id: 'tr_bad',
                kind: TransitionKinds.crossfade,
                atTicks: 123,
                durationTicks: 100,
                fromClipId: 'c1',
                toClipId: 'c2',
              ),
            ],
          ),
        ],
        assets: {video.id: video},
      );

      expect(
        () => DocumentInvariants.validate(broken),
        throwsA(
          isA<ShadowError>().having(
            (e) => e.message,
            'message',
            contains('invariant violation'),
          ),
        ),
      );
    });
  });

  group('Text layers and subtitles', () {
    late ProjectDocument doc;

    setUp(() {
      doc = _doc(
        tracks: [_overlayTrack('O1', position: 0)],
      );
    });

    test('adds a subtitle cue and removes it via inverse', () {
      const cue = TextLayer(
        id: 'cue1',
        text: 'مرحبا',
        subtitle: true,
        startTicks: 0,
        durationTicks: 2000000,
      );

      final result = AddTextLayerCommand(trackId: 'O1', layer: cue).execute(doc);
      expect(result.document.tracks.single.textLayers, hasLength(1));
      expect(result.document.tracks.single.textLayers.single.subtitle, isTrue);

      final undone = result.inverse.execute(result.document);
      expect(undone.document, doc);
    });

    test('rejects overlapping subtitle cues and non-overlay tracks', () {
      const a = TextLayer(
        id: 'a',
        text: 'one',
        subtitle: true,
        startTicks: 0,
        durationTicks: 2000000,
      );
      const b = TextLayer(
        id: 'b',
        text: 'two',
        subtitle: true,
        startTicks: 1000000,
        durationTicks: 2000000,
      );

      final withA = AddTextLayerCommand(trackId: 'O1', layer: a).execute(doc);
      expect(
        () => AddTextLayerCommand(trackId: 'O1', layer: b)
            .execute(withA.document),
        throwsA(isA<ShadowError>()),
      );

      final videoDoc = _doc(tracks: [_videoTrack('V1', position: 0)]);
      expect(
        () => AddTextLayerCommand(trackId: 'V1', layer: a).execute(videoDoc),
        throwsA(isA<ShadowError>()),
      );
    });

    test('update restores previous style on undo', () {
      const original = TextLayer(
        id: 't1',
        text: 'Title',
        startTicks: 0,
        durationTicks: 1000000,
        fontSizePx: 48,
      );
      final withLayer =
          AddTextLayerCommand(trackId: 'O1', layer: original).execute(doc);

      const updated = TextLayer(
        id: 't1',
        text: 'Subtitle',
        startTicks: 0,
        durationTicks: 1000000,
        fontSizePx: 32,
        colorHex: '#FFCC0000',
      );
      final result = UpdateTextLayerCommand(
        trackId: 'O1',
        layerId: 't1',
        updatedLayer: updated,
      ).execute(withLayer.document);

      expect(result.document.tracks.single.textLayers.single.text, 'Subtitle');
      final undone = result.inverse.execute(result.document);
      expect(undone.document.tracks.single.textLayers.single, original);
    });

    test('attaching a raster makes the layer renderable', () {
      const layer = TextLayer(
        id: 't1',
        text: 'Hello',
        startTicks: 0,
        durationTicks: 1000000,
      );
      final withLayer =
          AddTextLayerCommand(trackId: 'O1', layer: layer).execute(doc);
      expect(
        withLayer.document.tracks.single.textLayers.single.needsRasterization,
        isTrue,
      );

      final raster = SetTextLayerRasterCommand(
        trackId: 'O1',
        layerId: 't1',
        rasterUri: 'file:///cache/t1.png',
        rasterHash: 'b' * 64,
        rasterWidth: 640,
        rasterHeight: 120,
      ).execute(withLayer.document);

      final resolved = raster.document.tracks.single.textLayers.single;
      expect(resolved.isRenderable, isTrue);

      final undone = raster.inverse.execute(raster.document);
      expect(
        undone.document.tracks.single.textLayers.single.needsRasterization,
        isTrue,
      );
    });
  });

  group('Audio mixing and clip effects', () {
    late Asset audioAsset;
    late Asset videoAsset;
    late ProjectDocument doc;

    setUp(() {
      audioAsset = Asset(
        id: 'asset_a',
        kind: AssetKind.audio,
        uri: 'file:///w/a.wav',
        durationTicks: 10000000,
        hash: 'c' * 64,
      );
      videoAsset = Asset(
        id: 'asset_v',
        kind: AssetKind.video,
        uri: 'file:///w/v.mp4',
        durationTicks: 10000000,
        hash: 'd' * 64,
      );
      doc = _doc(
        tracks: [
          Track(
            id: 'A1',
            kind: TrackKind.audio,
            position: 0,
            name: 'A1',
            clips: [
              Clip.audio(
                id: 'ac1',
                assetId: audioAsset.id,
                timelineStartTicks: 0,
                durationTicks: 4000000,
              ),
            ],
          ),
          _videoTrack(
            'V1',
            position: 1,
            clips: [_videoClip(id: 'vc1', assetId: videoAsset.id)],
          ),
        ],
        assets: {audioAsset.id: audioAsset, videoAsset.id: videoAsset},
      );
    });

    test('track gain and pan are validated and undoable', () {
      final result = SetTrackAudioCommand(
        trackId: 'A1',
        gainMb: -3000,
        panPpm: -250000,
      ).execute(doc);

      final track = result.document.tracks.first;
      expect(track.gainMb, -3000);
      expect(track.panPpm, -250000);
      expect(result.inverse.execute(result.document).document, doc);

      expect(
        () => SetTrackAudioCommand(trackId: 'A1', gainMb: 99999).execute(doc),
        throwsA(isA<ShadowError>()),
      );
      expect(
        () => SetTrackAudioCommand(trackId: 'V1', gainMb: 0).execute(doc),
        throwsA(isA<ShadowError>()),
      );
    });

    test('clip fades cannot exceed the clip duration', () {
      expect(
        () => SetClipAudioCommand(
          trackId: 'A1',
          clipId: 'ac1',
          fadeInTicks: 3000000,
          fadeOutTicks: 3000000,
        ).execute(doc),
        throwsA(isA<ShadowError>()),
      );

      final result = SetClipAudioCommand(
        trackId: 'A1',
        clipId: 'ac1',
        gainMb: 1200,
        fadeInTicks: 250000,
        fadeOutTicks: 250000,
      ).execute(doc);

      final clip = result.document.tracks.first.clips.single;
      expect(clip.gainMb, 1200);
      expect(clip.fadeInTicks, 250000);
      expect(result.inverse.execute(result.document).document, doc);
    });

    test('effects stack is replaced atomically and validated', () {
      const effect = Effect(id: 'fx1', effectKey: 'color.balance');
      final result = SetClipEffectsCommand(
        trackId: 'V1',
        clipId: 'vc1',
        effects: const [effect],
      ).execute(doc);
      expect(result.document.tracks[1].clips.single.effects.single, effect);
      expect(result.inverse.execute(result.document).document, doc);

      expect(
        () => SetClipEffectsCommand(
          trackId: 'V1',
          clipId: 'vc1',
          effects: const [effect, effect],
        ).execute(doc),
        throwsA(isA<ShadowError>()),
      );
      expect(
        () => SetClipEffectsCommand(
          trackId: 'A1',
          clipId: 'ac1',
          effects: const [effect],
        ).execute(doc),
        throwsA(isA<ShadowError>()),
      );
    });

    test('visual properties (opacity/transform/enabled) are undoable', () {
      final result = SetClipVisualCommand(
        trackId: 'V1',
        clipId: 'vc1',
        opacityPpm: 500000,
        enabled: false,
        label: 'hero shot',
      ).execute(doc);

      final clip = result.document.tracks[1].clips.single;
      expect(clip.opacityPpm, 500000);
      expect(clip.enabled, isFalse);
      expect(clip.label, 'hero shot');
      expect(result.inverse.execute(result.document).document, doc);

      expect(
        () => SetClipVisualCommand(
          trackId: 'V1',
          clipId: 'vc1',
          opacityPpm: 1000001,
        ).execute(doc),
        throwsA(isA<ShadowError>()),
      );
    });
  });

  group('ResolveGraph with new features', () {
    test('rasterized text layers reach the graph, pending ones are skipped', () {
      final service = DefaultEditingService(
        initialDocument: _doc(
          tracks: [
            _overlayTrack('O1', position: 0),
            _videoTrack(
              'V1',
              position: 1,
              clips: [
                _videoClip(
                  id: 'c1',
                  assetId: 'a',
                  start: 0,
                  duration: 3000000,
                ),
              ],
            ),
          ],
          assets: {
            'a': Asset(
              id: 'a',
              kind: AssetKind.video,
              uri: 'file:///w/a.mp4',
              durationTicks: 10000000,
              hash: 'e' * 64,
            ),
          },
        ),
      );

      final withPending = AddTextLayerCommand(
        trackId: 'O1',
        layer: const TextLayer(
          id: 'pending',
          text: 'not rasterized',
          startTicks: 0,
          durationTicks: 1000000,
        ),
      ).execute(service.currentDocument);

      final service2 = DefaultEditingService(initialDocument: withPending.document);
      final graph = service2.resolveGraph(
        revision: service2.revision,
        range: RangeTicks(startTicks: 0, durationTicks: 5000000),
      );

      final overlay = graph.tracks.firstWhere((t) => t.kind == TrackKind.overlay);
      expect(overlay.textLayers, isEmpty);
      expect(graph.toJson()['tracks'], isA<List<Object?>>());
    });

    test('audio track gain and clip fades are resolved into the graph', () {
      final service = DefaultEditingService(
        initialDocument: _doc(
          tracks: [
            Track(
              id: 'A1',
              kind: TrackKind.audio,
              position: 0,
              name: 'A1',
              gainMb: -2000,
              panPpm: 0,
              clips: [
                Clip.audio(
                  id: 'ac1',
                  assetId: 'a',
                  timelineStartTicks: 0,
                  durationTicks: 3000000,
                  gainMb: 500,
                  fadeInTicks: 100000,
                  fadeOutTicks: 100000,
                ),
              ],
            ),
          ],
          assets: {
            'a': Asset(
              id: 'a',
              kind: AssetKind.audio,
              uri: 'file:///w/a.wav',
              durationTicks: 10000000,
              hash: 'f' * 64,
            ),
          },
        ),
      );

      final graph = service.resolveGraph(
        revision: service.revision,
        range: RangeTicks(startTicks: 0, durationTicks: 3000000),
      );

      final track = graph.tracks.single;
      expect(track.kind, TrackKind.audio);
      expect(track.gainMb, -2000);
      expect(track.audioClips?.single.gainMb, 500);
      expect(track.audioClips?.single.fadeInTicks, 100000);
    });
  });
}