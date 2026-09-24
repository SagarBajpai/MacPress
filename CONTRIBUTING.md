# Contributing to MacPress

## Development requirements

- macOS 14 or later on Apple Silicon
- Xcode 16 or later with Swift 6 command-line tools
- FFmpeg build prerequisites only if rebuilding `ThirdParty/FFmpeg`

## Build and test

```bash
git clone <repository-url>
cd MacPress
swift test
./scripts/build.sh
./scripts/install.sh
```

Use `SCREEN_COMPRESSOR_INTEGRATION_TESTS=1 swift test` for the optional real VideoToolbox integration test. A real `.mov` source is required for the preset benchmark.

## Pull requests

- Keep changes focused and preserve source-recording safety.
- Add or update focused tests for behavior changes.
- Run `swift test`, the Release build, and `git diff --check`.
- Do not commit recordings, build products, signing credentials, or private machine configuration.
- Describe user-visible changes and any macOS-version limitations.
