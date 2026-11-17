import 'package:render_pipeline/render_pipeline.dart';

const uuidA = '0192f0c0-1234-7abc-8def-0123456789ab';
const uuidB = '0192f0c0-1234-7abc-8def-0123456789ac';
const uuidC = '0192f0c0-1234-7abc-8def-0123456789ad';
const hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Map<String, Object?> transformJson() => <String, Object?>{
  'x_px': 10,
  'y_px': 20,
  'scale_x_ppm': 1000000,
  'scale_y_ppm': 1000000,
  'rotation_quarter_turns': 0,
  'anchor': 'center',
  'crop_left_px': 0,
  'crop_right_px': 0,
  'crop_top_px': 0,
  'crop_bottom_px': 0,
};

Map<String, Object?> videoClip({
  String id = uuidA,
  String uri = 'file:///media/a.mp4',
  int startTicks = 0,
  int durationTicks = 4000000,
  int opacityPpm = 1000000,
}) => <String, Object?>{
  'id': id,
  'asset_id': uuidB,
  'kind': 'video',
  'source_uri': uri,
  'source_hash': hashA,
  'stream_index': 0,
  'timeline_start_ticks': startTicks,
  'duration_ticks': durationTicks,
  'source_in_ticks': 0,
  'speed_num': 1,
  'speed_den': 1,
  'opacity_ppm': opacityPpm,
  'enabled': true,
  'transform': transformJson(),
  'effects': <Object?>[],
};

Map<String, Object?> audioClip({
  String id = uuidC,
  int durationTicks = 4000000,
  int gainMb = 0,
}) => <String, Object?>{
  'id': id,
  'asset_id': uuidB,
  'source_uri': 'file:///media/a.wav',
  'source_hash': hashB,
  'stream_index': 0,
  'timeline_start_ticks': 0,
  'duration_ticks': durationTicks,
  'source_in_ticks': 0,
  'speed_num': 1,
  'speed_den': 1,
  'gain_mb': gainMb,
  'fade_in_ticks': 0,
  'fade_out_ticks': 0,
  'enabled': true,
};

Map<String, Object?> textLayer({
  int startTicks = 0,
  int durationTicks = 3000000,
}) => <String, Object?>{
  'id': uuidA,
  'raster_uri': 'file:///cache/text/a.png',
  'raster_hash': hashA,
  'raster_width': 640,
  'raster_height': 200,
  'start_ticks': startTicks,
  'duration_ticks': durationTicks,
  'opacity_ppm': 1000000,
  'transform': transformJson(),
  'animation_in': <String, Object?>{'kind': 'fade', 'duration_ticks': 250000},
  'animation_out': <String, Object?>{'kind': 'none', 'duration_ticks': 0},
};

Map<String, Object?> videoTrack({
  List<Object?>? clips,
  List<Object?>? transitions,
  int position = 0,
}) => <String, Object?>{
  'id': uuidB,
  'kind': 'video',
  'position': position,
  'name': 'V1',
  'enabled': true,
  'clips': clips ?? <Object?>[videoClip()],
  if (transitions != null) 'transitions': transitions,
};

Map<String, Object?> audioTrack({
  List<Object?>? clips,
  int gainMb = -300,
  int position = 1,
}) => <String, Object?>{
  'id': uuidC,
  'kind': 'audio',
  'position': position,
  'name': 'A1',
  'enabled': true,
  'gain_mb': gainMb,
  'pan_ppm': 0,
  'audio_clips': clips ?? <Object?>[audioClip()],
};

Map<String, Object?> overlayTrack({List<Object?>? layers, int position = 2}) =>
    <String, Object?>{
      'id': uuidA,
      'kind': 'overlay',
      'position': position,
      'name': 'T1',
      'enabled': true,
      'text_layers': layers ?? <Object?>[textLayer()],
    };

Map<String, Object?> validGraph({List<Object?>? tracks}) => <String, Object?>{
  'graph_schema': 'shadow.rendergraph/1',
  'sequence_id': uuidA,
  'project_revision': 7,
  'timebase': <String, Object?>{
    'ticks_per_second': 1000000,
    'fps_num': 30,
    'fps_den': 1,
    'sample_rate': 48000,
    'channels': 2,
  },
  'profile': <String, Object?>{
    'width': 1920,
    'height': 1080,
    'pixel_format': 'yuv420p',
    'color_space': 'bt709',
    'interlaced': false,
  },
  'range': <String, Object?>{'start_ticks': 0, 'duration_ticks': 5000000},
  'background_rgba': '#000000FF',
  'tracks': tracks ?? <Object?>[videoTrack(), audioTrack(), overlayTrack()],
};

RenderGraphDoc validDoc({List<Object?>? tracks}) =>
    RenderGraphDoc.parse(validGraph(tracks: tracks));
