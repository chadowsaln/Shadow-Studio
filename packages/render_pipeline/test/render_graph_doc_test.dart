import 'package:render_pipeline/render_pipeline.dart';
import 'package:test/test.dart';

import 'graph_fixtures.dart';

void main() {
  group('RenderGraphDoc.parse', () {
    test('parses a complete graph', () {
      final doc = validDoc();

      expect(doc.graphSchema, 'shadow.rendergraph/1');
      expect(doc.sequenceId, uuidA);
      expect(doc.projectRevision, 7);
      expect(doc.fps, 30);
      expect(doc.durationTicks, 5000000);
      expect(doc.endTicks, 5000000);
      expect(doc.tracks, hasLength(3));
      expect(doc.videoTracks.single.clips.single.effects, isEmpty);
      expect(doc.audioTracks.single.gainMb, -300);
      expect(
        doc.overlayTracks.single.textLayers.single.animationInKind,
        'fade',
      );
    });

    test('round-trips through toJson', () {
      final json = validGraph();
      final reparsed = RenderGraphDoc.parse(
        RenderGraphDoc.parse(json).toJson(),
      );
      expect(reparsed.toJson(), json);
    });

    test('rejects an unknown top-level field', () {
      final json = validGraph()..['extra'] = true;
      expect(
        () => RenderGraphDoc.parse(json),
        throwsA(
          isA<RenderGraphException>().having(
            (e) => e.code,
            'code',
            'RG_UNKNOWN_FIELD',
          ),
        ),
      );
    });

    test('rejects a non-UUIDv7 sequence id', () {
      final json = validGraph()..['sequence_id'] = 'not-a-uuid';
      expect(
        () => RenderGraphDoc.parse(json),
        throwsA(
          isA<RenderGraphException>().having(
            (e) => e.code,
            'code',
            'RG_SCHEMA_VERSION',
          ),
        ),
      );
    });

    test('rejects a clip track redeclared as audio', () {
      final json = validGraph();
      final track0 =
          (json['tracks'] as List<Object?>)[0] as Map<String, Object?>;
      track0['kind'] = 'audio';
      expect(
        () => RenderGraphDoc.parse(json),
        throwsA(
          isA<RenderGraphException>().having(
            (e) => e.code,
            'code',
            'RG_TRACK_KIND_FIELD',
          ),
        ),
      );
    });

    test('rejects a transition with an unknown kind', () {
      final json = validGraph(
        tracks: <Object?>[
          videoTrack(
            clips: <Object?>[
              videoClip(),
              videoClip(id: uuidC, startTicks: 4000000),
            ],
            transitions: <Object?>[
              <String, Object?>{
                'id': uuidC,
                'kind': 'spin',
                'at_ticks': 3500000,
                'duration_ticks': 500000,
                'from_clip_id': uuidA,
                'to_clip_id': uuidC,
              },
            ],
          ),
        ],
      );
      expect(
        () => RenderGraphDoc.parse(json),
        throwsA(
          isA<RenderGraphException>().having(
            (e) => e.code,
            'code',
            'RG_TRANSITION_BOUNDARY',
          ),
        ),
      );
    });

    test('rejects yuv420p with odd dimensions', () {
      final json = validGraph();
      (json['profile'] as Map<String, Object?>)['height'] = 1081;
      expect(
        () => RenderGraphDoc.parse(json),
        throwsA(
          isA<RenderGraphException>().having(
            (e) => e.code,
            'code',
            'RG_UNSUPPORTED_PROFILE',
          ),
        ),
      );
    });

    test('rejects an empty range', () {
      final json = validGraph();
      (json['range'] as Map<String, Object?>)['duration_ticks'] = 0;
      expect(
        () => RenderGraphDoc.parse(json),
        throwsA(
          isA<RenderGraphException>().having(
            (e) => e.code,
            'code',
            'RG_RANGE_INVALID',
          ),
        ),
      );
    });

    test('rejects text animations that overrun the layer', () {
      final json = validGraph(
        tracks: <Object?>[
          overlayTrack(
            position: 0,
            layers: <Object?>[textLayer(durationTicks: 1000000)],
          ),
        ],
      );
      final track =
          (json['tracks'] as List<Object?>).single as Map<String, Object?>;
      final layer =
          (track['text_layers'] as List<Object?>).single
              as Map<String, Object?>;
      (layer['animation_in'] as Map<String, Object?>)['duration_ticks'] =
          2000000;
      expect(
        () => RenderGraphDoc.parse(json),
        throwsA(
          isA<RenderGraphException>().having(
            (e) => e.code,
            'code',
            'RG_TEXT_RASTER',
          ),
        ),
      );
    });
  });

  group('RenderPreset', () {
    test('resolves builtins by id', () {
      expect(
        RenderPreset.byId(RenderPreset.mp4H2641080p.id),
        RenderPreset.mp4H2641080p,
      );
      expect(RenderPreset.byId(RenderPreset.wavPcm.id), RenderPreset.wavPcm);
      expect(() => RenderPreset.byId('does-not-exist'), throwsArgumentError);
    });

    test('builtins are keyed by their own id', () {
      for (final preset in RenderPreset.builtins.values) {
        expect(RenderPreset.builtins[preset.id], same(preset));
        expect(preset.label, isNotEmpty);
      }
    });

    test('custom presets override the base and keep the container', () {
      final custom = RenderPreset.custom(
        id: 'custom-720',
        label: 'Custom 720p',
        base: RenderPreset.mp4H2641080p,
        width: 1280,
        height: 720,
        crf: 20,
      );
      expect(custom.width, 1280);
      expect(custom.height, 720);
      expect(custom.crf, 20);
      expect(custom.container, RenderPreset.mp4H2641080p.container);
    });
  });
}
