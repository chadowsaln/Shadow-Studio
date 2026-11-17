@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:editing_core/editing_core.dart';
import 'package:test/test.dart';

void main() {
  group('Phase 3 Golden Test: EditingService.resolveGraph -> tools/media-spike', () {
    late DefaultEditingService service;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('golden_spike_test_');

      // Build document matching the normative rendergraph.example.json
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
        label: '',
        transform: const TransformBox.identity(),
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

      final doc = ProjectDocument(
        id: '0198f3b2-7c41-7f0a-9a1e-3d1c2b4a5e60',
        sequenceId: '0198f3b2-7c41-7f0a-9a1e-3d1c2b4a5e60',
        name: 'Golden Example Project',
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
        initialDocument: doc,
        initialRevision: 218,
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('resolveGraph produces graph valid against rendergraph.schema.json and consumed by tools/media-spike', () async {
      // 1. Resolve RenderGraph via EditingService
      final graph = service.resolveGraph(
        revision: 218,
        range: const RangeTicks(startTicks: 0, durationTicks: 10000000),
      );

      final graphJson = jsonEncode(graph.toJson());
      final graphFile = File('${tempDir.path}/derived_graph.json');
      await graphFile.writeAsString(graphJson);

      // Find root directory
      final repoRoot = Directory.current.path.contains('packages')
          ? Directory.current.parent.parent.path
          : Directory.current.path;

      // 2. Validate using Python schema validator (validate_schema.py)
      final pythonScript = '''
import json
import sys
from pathlib import Path

repo_root = Path("$repoRoot")
sys.path.insert(0, str(repo_root / "docs/architecture/contracts"))
sys.path.insert(0, str(repo_root / "tools/media-spike"))

import validate_schema
import graphcontract
from compile_plan import compile_graph
from media_fixtures import build_fixtures, probe_fixtures, make_raster
from media_common import blake3_file, path_to_uri

schema_path = repo_root / "docs/architecture/contracts/rendergraph.schema.json"
effects_path = repo_root / "docs/architecture/contracts/rendergraph.effects.json"
schema = json.loads(schema_path.read_text(encoding="utf-8"))
effects = json.loads(effects_path.read_text(encoding="utf-8"))

# Load derived graph from Dart
derived_graph = json.loads(Path("${graphFile.path}").read_text(encoding="utf-8"))

# 1. Structural schema validation
errors = []
def fail(msg):
    errors.append(msg)
def ok(msg):
    pass

validate_schema.validate_instance(schema, {"\$ref": "#/\$defs/RenderGraph"}, derived_graph, "derived_graph", fail, ok)
if errors:
    print(f"SCHEMA_ERRORS: {errors}", file=sys.stderr)
    sys.exit(1)

# 2. Contract & Semantic checks via media-spike
existing_fixtures = repo_root / "tools/media-spike/out/fixtures"
fixture_dir = existing_fixtures if (existing_fixtures / "intro-4k.mp4").exists() else Path("${tempDir.path}/fixtures")
paths = build_fixtures(fixture_dir)
sources = probe_fixtures(paths)

# Bind derived graph URIs and BLAKE3 hashes to generated fixtures
for track in derived_graph["tracks"]:
    for clip in track.get("clips") or []:
        if "intro" in clip.get("label", "") or "intro" in clip.get("source_uri", ""):
            clip["source_uri"] = path_to_uri(paths["intro"])
            clip["source_hash"] = blake3_file(paths["intro"])
        elif "outro" in clip.get("label", "") or "outro" in clip.get("source_uri", ""):
            clip["source_uri"] = path_to_uri(paths["outro"])
            clip["source_hash"] = blake3_file(paths["outro"])
    for clip in track.get("audio_clips") or []:
        clip["source_uri"] = path_to_uri(paths["audio"])
        clip["source_hash"] = blake3_file(paths["audio"])
    for layer in track.get("text_layers") or []:
        layer["raster_uri"] = path_to_uri(paths["raster"])
        layer["raster_hash"] = blake3_file(paths["raster"])

raster_info = {layer["raster_uri"]: sources[layer["raster_uri"]] for track in derived_graph["tracks"] for layer in track.get("text_layers") or []}

summary = graphcontract.check(derived_graph, sources, rasters=raster_info)
assert summary["stage"] == "semantics", f"Expected semantics checks to pass, got: {summary}"

# 3. Plan compilation by tools/media-spike
example_json = json.loads((repo_root / "docs/architecture/contracts/rendergraph.example.json").read_text(encoding="utf-8"))
preset = example_json["render_start_request"]["preset"]
plan = compile_graph(derived_graph, preset=preset, sources=sources, rasters=sources[path_to_uri(paths["raster"])])
assert len(plan["inputs"]) == 4, f"Expected 4 inputs, got {len(plan['inputs'])}"
assert plan["filter_complex"], "Filter complex must not be empty"

print("SUCCESS_DERIVED_GRAPH_CONSUMED")
''';

      final scriptFile = File('${tempDir.path}/validate_derived.py');
      await scriptFile.writeAsString(pythonScript);

      final result = await Process.run('python3', [scriptFile.path]);

      expect(
        result.exitCode,
        equals(0),
        reason: 'Python validation script failed:\nstdout: ${result.stdout}\nstderr: ${result.stderr}',
      );

      expect(result.stdout.toString(), contains('SUCCESS_DERIVED_GRAPH_CONSUMED'));
    });
  });
}
