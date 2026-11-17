# media_core

Desktop media client and worker abstraction for Shadow Studio.

## Architecture & Responsibilities (Spec §2.2 & §10)

Per Spec §2.2 (Module 9), `media_core` is the Dart client responsible for media probing, stream inspection, BLAKE3 deduplication, thumbnail rendering, proxy generation, and waveform computation.

It adheres to the following core constraints:
- **Desktop-First & Direct IPC**: Runs inside the Flutter desktop process without any backend, HTTP, or loopback servers.
- **Integer Ticks Only**: All time values, durations, and timestamps are represented strictly as integer ticks (`1 tick = 1/1,000,000 s`). Never uses `double` for time.
- **Non-Destructive Editing**: Original source media files are strictly read-only and never modified.
- **Atomic File Operations**: Derived artifacts (such as proxies) use atomic write semantics (`<file>.part` -> fsync -> rename) to guarantee crash safety.
- **Standardized Error Handling**: Strictly implements Spec §14.3 error taxonomy (`MEDIA_ASSET_MISSING`, `MEDIA_UNSUPPORTED`, `MEDIA_CORRUPT`, `MEDIA_ENGINE_CRASH`, `MEDIA_WORKER_UNAVAILABLE`).
- **Decoupled Architecture**: Logic packages are pure Dart with zero Flutter imports.

## Public API

### Media Ingestion & Service
- `MediaLibraryService`: High-level service orchestrating file ingestion, probe inspection, BLAKE3 deduplication, and asset caching.
- `MediaHashRegistry`: Fast in-memory registry of known BLAKE3 content digests for cross-project deduplication.

### Worker Implementations
- `MediaWorker`: Abstract interface for media engine operations.
- `FakeMediaWorker`: In-memory mocked worker for fast, hermetic, offline tests (< 10 ms execution).
- `FfmpegMediaWorker`: Interim CLI runner wrapping system `ffprobe` and `ffmpeg` binaries.

### Cryptographic Hashing
- `Blake3`: Pure Dart streaming implementation of the BLAKE3 cryptographic hash function matching Python and Rust reference implementations.

### Data Models
- `MediaProbeResult`: Container format, file size, bitrate, and stream topologies.
- `VideoStreamInfo`: Codec, resolution, frame rate numerator/denominator, duration in ticks, and rotation.
- `AudioStreamInfo`: Codec, sample rate, channel count, duration in ticks, and channel layout.
- `WaveformData`: Normalized peak audio waveform samples for visual timeline display.
- `ImportedMediaAsset`: Ingested asset descriptor referencing source paths, hashes, and derived caches.

## Testing

Run tests with Dart CLI:

```bash
dart test packages/media_core
```
