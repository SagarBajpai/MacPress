# Testing and verification

## Test layers

`ScreenCompressorTests/UtilitiesTests.swift` contains filename, progress, ratio, process, stabilization, compression safety, real pipeline, queue, batch, and folder watcher tests. `CompressionSettingsTests.swift` covers preset normalization, persistence, argument construction, media probing, and batch progress. `MenuBarIconTests.swift` checks generated icon states. `PresetBenchmarks.swift` is an opt-in measurement test.

## Required checks

Run the normal suite:

```bash
swift test
```

Run the real bundled-media path after building the app:

```bash
./scripts/build.sh
SCREEN_COMPRESSOR_INTEGRATION_TESTS=1 SCREEN_COMPRESSOR_TEST_APP="$PWD/dist/ScreenCompressor.app" swift test
```

Build the Xcode target:

```bash
xcodebuild -project ScreenCompressor.xcodeproj -scheme ScreenCompressor -configuration Release build CODE_SIGN_IDENTITY=-
```

For preset tuning:

```bash
SCREEN_COMPRESSOR_BENCHMARK_SOURCE="/path/to/recording.mov" swift test --filter PresetBenchmarks
```

## Safety coverage

Tests explicitly cover FFmpeg failure, invalid/empty output, FFprobe failure, source mutation, cancellation, Trash failure, output collisions, duplicate scans, serial encoding, stabilization, and missing FFprobe indeterminate progress. Any change to cleanup, output naming, probing, cancellation, or queue state should add a regression test before implementation is considered complete.

## Verification limits

The normal suite does not prove visual quality for every screen-recording workload and skips hardware integration/benchmark tests unless requested. A passing test suite proves the tested invariants, not a universal compression ratio or notarization result. Release verification additionally depends on Apple signing credentials and notarization service availability.
