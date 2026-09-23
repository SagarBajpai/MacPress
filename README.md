# Screen Compressor

Screen Compressor is a native macOS menu-bar app that watches `~/Screenshots` for `.mov` recordings and converts them to HEVC `.mp4` files. It processes one recording at a time, shows ffmpeg progress, verifies each output, and then moves the original to Trash. Failed or cancelled jobs keep the original.

Requires macOS 14 or later and `ffmpeg` with VideoToolbox support. `ffprobe` is recommended for media validation and progress percentages. The app looks in `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, and `PATH` for each tool independently. It never installs either tool.

## Build and install

```bash
./scripts/build.sh
swift test
SCREEN_COMPRESSOR_INTEGRATION_TESTS=1 swift test
./scripts/install.sh
open "$HOME/Applications/ScreenCompressor.app"
```

`build.sh` produces an ad-hoc signed, menu-bar-only app at `dist/ScreenCompressor.app`. `install.sh` copies it into `~/Applications`. Open the Swift package in Xcode to edit and debug the project. The menu has controls to open the Screenshots folder, view logs, and enable Launch at Login. Launch at Login works from an installed app bundle.

Logs are stored in `~/Library/Logs/ScreenCompressor/` and rotate at roughly 1 MB. Recent jobs are kept in memory for the session. The app creates `~/Screenshots` if it is missing.

## Legacy installation

An older shell script or LaunchAgent may also be watching the folder. If the legacy LaunchAgent is loaded, unload it explicitly before opening Screen Compressor:

```bash
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.screen-recording-compressor.plist"
```

This project does not change or remove legacy files or services. The previously used locations may include `~/.local/scripts/compress-screen-recording.sh`, `~/Library/LaunchAgents/local.screen-recording-compressor.plist`, and `~/.local/logs/compress-screen-recording.log`.
