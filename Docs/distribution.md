# Build and distribution

## Local build

`Package.swift` supports `swift build` and `swift test`. `scripts/build.sh` builds the release executable, creates `dist/ScreenCompressor.app`, copies `Info.plist`, copies/signs FFmpeg resources, verifies arm64 architecture and dependencies, and performs a strict ad-hoc code-signature check.

The Xcode target in `ScreenCompressor.xcodeproj` includes all Swift sources, macOS 14/arm64 settings, hardened runtime configuration, and a shell build phase that packages and verifies FFmpeg. The Xcode project and CLI script are both supported build paths.

## Bundled FFmpeg

`ThirdParty/FFmpeg/` contains FFmpeg 9.0.2 arm64 `ffmpeg`/`ffprobe`, shared libraries, the exact source archive, LGPL text, and `NOTICE.md`. `scripts/build-ffmpeg.sh` rebuilds from the pinned archive using Apple clang, VideoToolbox/AudioToolbox, shared libraries, no network, no GPL, no nonfree components, and no external Homebrew libraries. Its checksum is verified before extraction/build.

`scripts/verify-ffmpeg-bundle.sh` checks executable architecture, FFmpeg capabilities, source checksum, license files, and absence of Homebrew/local-library paths. Inside an app, the executables use `@rpath`/`@loader_path` to find `Contents/Frameworks`.

The FFmpeg build is LGPL-2.1-or-later. The distributed app includes corresponding source and notices under `Contents/Resources/FFmpeg`. The FFmpeg notice also records the replaceable-library and patent caveats. Do not remove these materials when changing the bundle.

## DMG and release

`scripts/create-dmg.sh` creates a read-only compressed DMG containing the app and an `/Applications` symlink. It refuses to overwrite an existing output. `scripts/release.sh` requires:

- `DEVELOPER_ID_APPLICATION`: a Developer ID Application certificate name in the keychain.
- `NOTARY_PROFILE`: a `notarytool` keychain profile created with Apple credentials.

The release script builds, runs the hardware integration test, signs nested libraries/tools and the app with hardened runtime/timestamps, creates and signs the DMG, submits it with `notarytool`, staples and validates the ticket, and runs `spctl`. Without Apple credentials, local ad-hoc builds are for development only and are not a public notarized release.

## Legacy installation

The old `~/.local/scripts/compress-screen-recording.sh`, LaunchAgent plist, and legacy logs may exist on developer machines. The app neither removes nor unloads them. An explicit migration must disable the old watcher first to avoid duplicate processing.
