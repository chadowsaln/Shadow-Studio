/// Media core module for Shadow Studio.
///
/// Implements media probing, stream inspection, BLAKE3 deduplication,
/// thumbnail rendering, proxy generation, and waveform computation.
library media_core;

export 'src/error/media_error.dart';
export 'src/hash/blake3.dart';
export 'src/model/imported_media_asset.dart';
export 'src/model/media_kind.dart';
export 'src/model/media_probe_result.dart';
export 'src/model/media_stream_info.dart';
export 'src/model/waveform_data.dart';
export 'src/service/media_hash_registry.dart';
export 'src/service/media_library_service.dart';
export 'src/worker/fake_media_worker.dart';
export 'src/worker/ffmpeg_media_worker.dart';
export 'src/worker/media_worker.dart';
