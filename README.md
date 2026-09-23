# Screen Compressor

Screen Compressor is a native macOS menu-bar app that watches `~/Screenshots` for `.mov` recordings and converts them to HEVC `.mp4` files. It processes one recording at a time, shows ffmpeg progress, verifies each output, and then moves the original to Trash. Failed or cancelled jobs keep the original.

Requires macOS 14 or later on Apple Silicon. The app includes arm64 `ffmpeg`, `ffprobe`, and their shared FFmpeg libraries; users do not need Homebrew, Terminal, or any separate tool installation. It uses the bundled tools first, then searches `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, and `PATH` only if a bundled tool is absent.

## Install from a release

Download the signed and notarized `ScreenCompressor-*-arm64.dmg`, open it, and drag Screen Compressor to Applications. Open the app from Applications. It runs in the menu bar rather than the Dock. macOS may ask for access to the Screenshots folder. Enable Launch at Login from the menu if desired. No command-line setup is needed.

## Build and install

```bash
./scripts/build.sh
swift test
SCREEN_COMPRESSOR_INTEGRATION_TESTS=1 swift test
./scripts/install.sh
open "$HOME/Applications/ScreenCompressor.app"
```

`build.sh` produces an ad-hoc signed, self-contained menu-bar app at `dist/ScreenCompressor.app`. This is for local development, not public distribution. `install.sh` copies it into `~/Applications`. Open `ScreenCompressor.xcodeproj` in Xcode to edit and build the app; its build phase copies and signs the bundled tools and libraries. The Swift package remains available for command-line builds and XCTest. Launch at Login works from an installed app bundle.

## Release build

The checked-in FFmpeg 9.0.2 binaries are built from the included source archive with Apple VideoToolbox support and without GPL/nonfree or Homebrew-linked libraries. To rebuild them on Apple Silicon with Xcode command-line tools, run `./scripts/build-ffmpeg.sh`. The script verifies the source archive's SHA-256 before compiling and validates the resulting arm64 tools. After any rebuild, run the app build and tests again.

Public release requires an Apple Developer ID Application certificate in the keychain and notarization credentials stored with `xcrun notarytool store-credentials`. Set `DEVELOPER_ID_APPLICATION` to the certificate name and `NOTARY_PROFILE` to that stored profile, then run `./scripts/release.sh`. The script builds and tests, signs every FFmpeg dylib and executable with the hardened runtime, signs the app, creates a drag-to-Applications DMG, submits it for notarization, staples the ticket, and verifies it. It refuses to overwrite an existing DMG. Without those Apple credentials, a distributable notarized release cannot be produced; an ad-hoc local build is not equivalent.

FFmpeg's LGPL-2.1-or-later notice, upstream license notes, and complete corresponding source archive are included in the app under `Contents/Resources/FFmpeg/` and in `ThirdParty/FFmpeg/`. The FFmpeg shared libraries are in `Contents/Frameworks/` so they can be replaced with compatible versions. See [the FFmpeg notice](ThirdParty/FFmpeg/NOTICE.md) for the exact build and attribution details. Distributors should review media patent obligations for their jurisdictions.

Logs are stored in `~/Library/Logs/ScreenCompressor/` and rotate at roughly 1 MB. Recent jobs are kept in memory for the session. The app creates `~/Screenshots` if it is missing.

## Legacy installation

An older shell script or LaunchAgent may also be watching the folder. If the legacy LaunchAgent is loaded, unload it explicitly before opening Screen Compressor:

```bash
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.screen-recording-compressor.plist"
```

This project does not change or remove legacy files or services. The previously used locations may include `~/.local/scripts/compress-screen-recording.sh`, `~/Library/LaunchAgents/local.screen-recording-compressor.plist`, and `~/.local/logs/compress-screen-recording.log`.
