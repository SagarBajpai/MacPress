# Agent instructions for Screen Compressor

Read this file first, then [ARCHITECTURE.md](ARCHITECTURE.md) and [Docs/README.md](Docs/README.md). The source code is authoritative when documentation and implementation disagree; update documentation when implementation changes.

## Repository identity

This is a native Swift/SwiftUI macOS menu-bar app, not a web application. It has no JavaScript, backend, API server, authentication, authorization, maps, telemetry, or database. It targets Apple Silicon macOS 14+.

The product watches `~/Screenshots`, encodes `.mov` recordings serially using bundled FFmpeg VideoToolbox tools, verifies outputs, and trashes originals only after successful verification.

## Safe change workflow

1. Read `ARCHITECTURE.md`.
2. Read the relevant entry in `Docs/README.md`.
3. Inspect actual callers and tests, not only the named file.
4. Preserve source-recording safety and serial queue semantics.
5. Keep settings translation in `FFmpegArgumentBuilder`.
6. Add focused tests for changed business logic.
7. Run tests, build the app, review `git diff`, and check `git status`.

## Non-negotiable safety rules

- Never Trash or permanently delete a source before output verification succeeds.
- Preserve the source on FFmpeg failure, cancellation, probe failure, invalid output, permissions errors, shutdown, and cleanup errors.
- Delete only a partial output owned by the current job; never recursively delete `~/Screenshots`.
- Never overwrite user output. Use `FileNameGenerator` and collision-safe finalization.
- Pass paths through `Process.arguments`; never build shell command strings.
- Keep FFmpeg, FFprobe, stabilization, and large filesystem work off the main actor.

## Architecture rules

- UI state belongs in `@MainActor` `MenuBarViewModel`.
- `JobQueue` and `CompressionSettingsStore` are actors.
- `FFmpegArgumentBuilder` is the single settings/source-facts to FFmpeg-arguments boundary.
- Native filesystem events are preferred over polling.
- Progress comes from FFmpeg `-progress pipe:1`; never fake progress with timers.
- Launch at Login uses `SMAppService.mainApp`; do not recreate the legacy LaunchAgent architecture.

## Commands

```bash
swift test
SCREEN_COMPRESSOR_INTEGRATION_TESTS=1 SCREEN_COMPRESSOR_TEST_APP="$PWD/dist/ScreenCompressor.app" swift test
./scripts/build.sh
xcodebuild -project ScreenCompressor.xcodeproj -scheme ScreenCompressor -configuration Release build CODE_SIGN_IDENTITY=-
```

The optional benchmark needs a real recording:

```bash
SCREEN_COMPRESSOR_BENCHMARK_SOURCE="/path/to/recording.mov" swift test --filter PresetBenchmarks
```

Use `./scripts/install.sh` for local installation. Quit any existing app first so two watchers do not process the same folder.

## Important paths

- Manifest: `Package.swift`
- Xcode project: `ScreenCompressor.xcodeproj/project.pbxproj`
- Metadata/entitlements: `Resources/`
- Bundled FFmpeg, source, notices: `ThirdParty/FFmpeg/`
- Build/release scripts: `scripts/`
- Tests: `ScreenCompressorTests/`
- Detailed documentation: `Docs/`

Do not add third-party dependencies, webviews, polling loops, shell interpolation, or automatic package installation without a concrete requirement and documentation update. Do not modify or unload the legacy user LaunchAgent automatically; migration is explicit.

Use meaningful Conventional Commits when asked to commit. Exclude unrelated local files such as `.vscode/`.
