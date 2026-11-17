import 'package:render_pipeline/render_pipeline.dart';
import 'package:test/test.dart';

import 'graph_fixtures.dart';

void main() {
  const planner = RenderPlanner();

  group('RenderPlanner', () {
    test('maps every source once and passes absolute paths', () {
      final plan = planner.plan(
        graph: validDoc(),
        preset: RenderPreset.mp4H2641080p,
      );

      expect(plan.inputs, hasLength(6));
      expect(plan.inputs, containsAllInOrder(<String>['-i', '/media/a.mp4']));
      expect(plan.inputs, containsAllInOrder(<String>['-i', '/media/a.wav']));
      expect(
        plan.inputs,
        containsAllInOrder(<String>['-i', '/cache/text/a.png']),
      );
    });

    test('lays a video track over the colour base', () {
      final plan = planner.plan(
        graph: validDoc(),
        preset: RenderPreset.mp4H2641080p,
      );
      final filter = plan.filterComplex!;

      expect(
        filter,
        contains('color=c=black:s=1920x1080:r=30:d=5.000000[base0]'),
      );
      expect(
        filter,
        contains('scale=1920x1080:force_original_aspect_ratio=decrease'),
      );
      expect(filter, contains('overlay=x=0:y=0[base1]'));
      expect(plan.videoLabel, 'vout');
      expect(plan.audioLabel, 'aout');
    });

    test('uses xfade for a declared transition and computes its offset', () {
      final plan = planner.plan(
        graph: validDoc(
          tracks: <Object?>[
            videoTrack(
              clips: <Object?>[
                videoClip(),
                videoClip(id: uuidC, startTicks: 4000000),
              ],
              transitions: <Object?>[
                <String, Object?>{
                  'id': uuidC,
                  'kind': 'crossfade',
                  'at_ticks': 3500000,
                  'duration_ticks': 500000,
                  'from_clip_id': uuidA,
                  'to_clip_id': uuidC,
                },
              ],
            ),
            audioTrack(clips: <Object?>[]),
          ],
        ),
        preset: RenderPreset.mp4H2641080p,
      );
      final filter = plan.filterComplex!;

      expect(
        filter,
        contains(
          'xfade=transition=crossfade:duration=0.500000:offset=3.500000',
        ),
      );
      expect(filter, isNot(contains('concat=')));
    });

    test('falls back to concat when no transition is declared', () {
      final plan = planner.plan(
        graph: validDoc(
          tracks: <Object?>[
            videoTrack(
              clips: <Object?>[
                videoClip(),
                videoClip(id: uuidC, startTicks: 4000000),
              ],
            ),
          ],
        ),
        preset: RenderPreset.mp4H2641080p,
      );

      expect(plan.filterComplex, contains('concat=n=2:v=1:a=0'));
    });

    test('overlays text rasters with their time window and position', () {
      final plan = planner.plan(
        graph: validDoc(),
        preset: RenderPreset.mp4H2641080p,
      );
      final filter = plan.filterComplex!;

      expect(filter, contains('format=rgba'));
      expect(
        filter,
        contains("overlay=x=10:y=20:enable='between(t,0.000000,3.000000)'"),
      );
      expect(filter, contains('fade=t=in:st=0.000000:d=0.250000:alpha=1'));
    });

    test('mixes multiple audio clips and applies per-clip gain', () {
      final plan = planner.plan(
        graph: validDoc(
          tracks: <Object?>[
            audioTrack(
              clips: <Object?>[
                audioClip(gainMb: -300),
                audioClip(id: uuidA, durationTicks: 2000000),
              ],
              position: 0,
            ),
          ],
        ),
        preset: RenderPreset.mp4H2641080p,
      );
      final filter = plan.filterComplex!;

      expect(filter, contains('amix=inputs=2:normalize=0'));
      expect(filter, contains('volume=-0.300dB'));
      expect(plan.audioArgs, containsAllInOrder(<String>['-c:a', 'aac']));
    });

    test('applies preset video arguments', () {
      final plan = planner.plan(
        graph: validDoc(),
        preset: RenderPreset.mp4H2641080p,
      );

      expect(
        plan.videoArgs,
        containsAllInOrder(<String>['-pix_fmt', 'yuv420p']),
      );
      expect(plan.videoArgs, containsAllInOrder(<String>['-r', '30/1']));
      expect(plan.outputArgs, containsAllInOrder(<String>['-t', '5.000000']));
      expect(plan.toArgs().first, '-i');
    });

    test('audio-only presets skip the video graph entirely', () {
      final plan = planner.plan(graph: validDoc(), preset: RenderPreset.wavPcm);

      expect(plan.hasVideo, isFalse);
      expect(plan.videoLabel, isNull);
      expect(plan.videoArgs, isEmpty);
      expect(plan.audioLabel, 'aout');
      expect(plan.filterComplex, isNot(contains('color=c=black')));
      expect(plan.toArgs().where((a) => a == '-c:v'), isEmpty);
    });

    test('rejects an empty video track set for a video preset gracefully', () {
      final plan = planner.plan(
        graph: validDoc(tracks: <Object?>[overlayTrack(position: 0)]),
        preset: RenderPreset.mp4H2641080p,
      );
      expect(plan.filterComplex, isNotNull);
      expect(plan.audioLabel, isNull);
    });
  });
}
