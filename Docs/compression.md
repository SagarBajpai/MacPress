# Compression configuration

## Model

`CompressionConfiguration` is Codable, Equatable, Sendable, and contains all encoder choices. Its related enums cover codec, quality mode, bitrate, bitrate ceiling, frame rate, resolution, pixel format, profile, keyframe interval, audio, and scaling quality.

`CompressionPreset` definitions are in `ScreenCompressor/CompressionSettings.swift`. `normalized()` repairs incompatible combinations and derives the preset label. `coerced()` is used at the encode boundary so malformed or stale persisted data cannot produce an invalid invocation.

## Preset intent

| Preset | Current behaviour |
| --- | --- |
| High | HEVC Main10, source frame rate/resolution, quality 55, 192 kbps AAC. |
| Balanced | HEVC Main10, 30 fps, source resolution, quality 45, 128 kbps AAC. Default. |
| Medium | HEVC Main10, 30 fps, source resolution, quality 32, 96 kbps AAC. |
| Low | 8-bit HEVC, 30 fps, 1080p cap, quality 18, 64 kbps AAC. |

These are engineering defaults, not guaranteed compression ratios. `PresetBenchmarks.swift` can measure a real recording; its normal test run skips without `SCREEN_COMPRESSOR_BENCHMARK_SOURCE`.

## Argument boundary

Only `FFmpegArgumentBuilder` constructs encoding arguments. It passes paths as separate `Process.arguments` entries. It can downscale and drop frames, but never upscales or invents frames. It combines filters with commas and adds `-progress pipe:1` and `-nostats` for real progress.

Constant-quality mode uses `-q:v`; target-bitrate mode uses `-b:v` with optional `-maxrate`, `-bufsize`, and constant-bitrate flag. Codec/profile/pixel format and keyframe interval are emitted only from the normalized configuration. AAC can be disabled with `-an`.

`MediaProbe` parses FFprobe JSON into duration, dimensions, frame rate, bitrate, and codec. Frame-rate rationals such as `79940/1343` are converted safely; malformed fields degrade to unknown rather than crashing.

## Changing compression behaviour safely

Do not tune a preset from one file or promise a fixed percentage. Use a representative `.mov`, run the opt-in benchmark, inspect text/UI quality and output size, then update configuration tests and this document. Verify that the bundled FFmpeg build actually supports any new encoder option. Preserve output verification and source safety.
