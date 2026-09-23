# Product behaviour

Screen Compressor is a menu-bar utility for people who record their Mac screen and want smaller, shareable files without manually operating FFmpeg. It watches the standard `~/Screenshots` folder and processes `.mov` recordings automatically.

## User-visible workflow

1. A screen recording appears in `~/Screenshots`.
2. The app waits while macOS finishes writing it.
3. The menu shows the current file, encoder progress, sizes, elapsed time, speed, and overall batch progress when multiple recordings are waiting.
4. On success, the output `.mp4` appears in the same directory and the source is moved to Trash.
5. Recent successful items show the size reduction and can be clicked to reveal the output in Finder. Failed items show the source and concise error; detailed context is in the log.

The app is a menu-bar-only application (`LSUIElement`), with no persistent main window or Dock icon. The menu provides the preset picker, Screenshots folder, logs, advanced settings, Launch at Login, and Quit.

## Presets and settings

Balanced is the default. High, Balanced, Medium, and Low are fixed configurations designed for screen recordings; changing an advanced control derives Custom. Returning every control to a preset definition restores that preset label. Settings are persisted as Codable data in `UserDefaults` by `CompressionSettingsStore`.

Advanced settings live in a small native AppKit-hosted SwiftUI window because the menu-bar popover is intentionally compact. Settings changes apply to jobs not yet started; `JobQueue` snapshots settings before each encode.

## Product rules

- Only `.mov` files are watched; output `.mp4` files and hidden/temporary files are ignored.
- One hardware encode runs at a time.
- The original is never removed merely because FFmpeg returned success; output verification is required.
- Collision handling generates a new output name instead of overwriting a file.
- Recent history is in memory and bounded by `AppConfiguration.recentJobLimit`; it is not persistent history.
- Logs are under `~/Library/Logs/ScreenCompressor/` and rotate around the configured size.

## Not implemented

There is no settings database, cloud sync, notifications, custom watched-folder UI, codec software fallback, pause control, or automatic FFmpeg installation. The legacy shell script/LaunchAgent is not migrated or changed automatically.
