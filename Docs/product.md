# Product behaviour

MacPress is a menu-bar utility for people who record their Mac screen and want smaller, shareable files without manually operating FFmpeg. It watches a configurable folder and processes eligible `.mov` recordings automatically.

## User-visible workflow

1. A screen recording appears in the configured watched folder.
2. The app waits while macOS finishes writing it.
3. The menu shows the current file, encoder progress, sizes, elapsed time, speed, and overall batch progress when multiple recordings are waiting.
4. On success, the output `.mp4` appears in the same directory and the source is moved to Trash.
5. Recent successful items show the size reduction and can be clicked to reveal the output in Finder. Failed items show the source and concise error; detailed context is in the log.

The app is a menu-bar-only application (`LSUIElement`), with no persistent main window or Dock icon. The menu provides the preset picker, watched-folder selector, logs, advanced settings, Launch at Login, and Quit. The initial folder is restored from a security-scoped bookmark where available; otherwise MacPress may use the observed Screenshot.app location preference as a best-effort hint and otherwise asks the user to choose.

## Presets and settings

Balanced is the default. High, Balanced, Medium, and Low are fixed configurations designed for screen recordings; changing an advanced control derives Custom. Returning every control to a preset definition restores that preset label. Settings are persisted as Codable data in `UserDefaults` by `CompressionSettingsStore`.

Advanced settings live in a small native AppKit-hosted SwiftUI window because the menu-bar popover is intentionally compact. The window is titled “Advance Settings”. Each quality tab has its own editable draft: changes are discarded unless Save is pressed. Reset restores that tab's built-in preset defaults. Saved settings apply to jobs not yet started; `JobQueue` snapshots settings before each encode.

## Product rules

- Only visible, regular `.mov` files in the watched folder are watched; output `.mp4` files and hidden/temporary files are ignored.
- One hardware encode runs at a time.
- The original is never removed merely because FFmpeg returned success; output verification is required.
- Collision handling generates a new output name instead of overwriting a file.
- Recent history is in memory and bounded by `AppConfiguration.recentJobLimit`; it is not persistent history.
- Logs are under `~/Library/Logs/ScreenCompressor/` and rotate around the configured size.

## Not implemented

There is no settings database, cloud sync, notifications, codec software fallback, pause control, or automatic FFmpeg installation. Filesystem monitoring does not provide guaranteed Screenshot.app provenance. The legacy shell script/LaunchAgent is not migrated or changed automatically.
