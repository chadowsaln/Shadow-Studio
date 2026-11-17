import 'package:render_pipeline/render_pipeline.dart';
import 'package:test/test.dart';

import 'graph_fixtures.dart';

void main() {
  test('plans a 300-clip timeline inside the 2s CPU budget', () {
    const clipCount = 300;
    const ticksPerSecond = 1000000;
    final clips = <Object?>[
      for (var i = 0; i < clipCount; i++)
        videoClip(
          startTicks: i * ticksPerSecond,
          durationTicks: ticksPerSecond,
        ),
    ];
    final graphJson = validGraph(tracks: <Object?>[videoTrack(clips: clips)]);
    graphJson['range'] = <String, Object?>{
      'start_ticks': 0,
      'duration_ticks': clipCount * ticksPerSecond,
    };

    final parseWatch = Stopwatch()..start();
    final graph = RenderGraphDoc.parse(graphJson);
    parseWatch.stop();

    final planWatch = Stopwatch()..start();
    final plan = const RenderPlanner().plan(
      graph: graph,
      preset: RenderPreset.mp4H264720p,
    );
    planWatch.stop();

    // ignore: avoid_print
    print(
      'render benchmark: $clipCount clips, parse=${parseWatch.elapsedMilliseconds}ms, '
      'plan=${planWatch.elapsedMilliseconds}ms, '
      'filter_chars=${plan.filterComplex?.length ?? 0}',
    );

    expect(plan.filterComplex, isNotNull);
    expect(plan.hasVideo, isTrue);
    expect(
      parseWatch.elapsed + planWatch.elapsed,
      lessThan(const Duration(seconds: 2)),
    );
  });
}
