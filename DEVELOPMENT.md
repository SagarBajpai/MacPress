# MacPress — Technical & Development Guide

This document contains technical details about MacPress, its compression pipeline, privacy model, file-safety guarantees, development workflow, and bundled FFmpeg distribution.

For installation and basic usage, see the main [README.md](README.md).

---

## ✨ Features

### 🎥 Native macOS recording workflow

MacPress works alongside the screen recorder already built into macOS.

Continue using:

<kbd>⌘</kbd> <kbd>⇧</kbd> <kbd>5</kbd>

There is no replacement recorder and no additional recording shortcut to learn.

MacPress operates on eligible `.mov` files after they appear in the configured watched folder.

---

### ⚡ Apple Silicon accelerated

MacPress uses hardware-accelerated FFmpeg encoding on Apple Silicon for fast local video compression.

---

### 🗜️ Automatic compression

Choose your recording folder once and MacPress watches it in the background.

When an eligible `.mov` file appears, MacPress waits for the file to finish changing before starting compression.

---

### 🎚️ Compression presets

MacPress provides:

- **High**
- **Balanced**
- **Medium**
- **Low**
- **Custom**

Use a preset for simplicity or Custom mode when you need more control over compression settings.

---

### 📊 Live progress

While a recording is being compressed, MacPress can display:

- compression progress
- current output size
- elapsed time
- encoder speed

---

### 📂 Configurable watched folder

Choose the folder MacPress should monitor using the native macOS folder picker.

MacPress remembers the explicitly selected folder between launches.

On first launch, it may use the observed macOS Screenshot save-location preference as a best-effort hint.

If a suitable folder cannot be determined, MacPress asks the user to choose one.

> [!NOTE]
> MacPress watches eligible files in the configured folder. Filesystem events cannot prove that a particular `.mov` was created by Apple's Screenshot app.

---

### 📚 Multiple recordings

MacPress maintains a serial compression queue.

If multiple recordings arrive, they are processed safely one at a time.

---

### 📦 FFmpeg included

MacPress bundles arm64 builds of FFmpeg and FFprobe.

A separate Homebrew or FFmpeg installation is not required for normal application use.

---

## 🔄 Compression pipeline

MacPress does not immediately modify or delete a newly detected recording.

The high-level lifecycle is:

```text
New .mov detected
        │
        ▼
Wait until file is stable
        │
        ▼
Probe source
        │
        ▼
Encode temporary output
        │
        ▼
Probe + verify output
        │
        ├──── Verification failed
        │           │
        │           └── Preserve original
        │
        ▼
Verification passed
        │
        ▼
Finalize .mp4
        │
        ▼
Move original to Trash
```

The compressed `.mp4` is written beside its source recording.

For example:

```text
Screen Recording 2026-09-24 at 10.30.00.mov
                        │
                        ▼
Screen Recording 2026-09-24 at 10.30.00.mp4
```

MacPress never intentionally overwrites an existing output.

---

## 🛡️ File safety

Protecting the original recording is more important than completing compression.

MacPress keeps the source recording when:

- FFmpeg encoding fails
- FFprobe fails
- output verification fails
- compression is cancelled
- filesystem permissions prevent completion
- output finalization fails
- cleanup fails

The original is moved to Trash only after the compressed result successfully passes verification.

---

## 🔒 Privacy

### Your recordings stay on your Mac.

MacPress does not:

- upload recordings
- require an account
- collect telemetry
- send analytics
- use cloud compression
- require a cloud service for normal compression

FFmpeg and FFprobe run locally as child processes.

The normal processing flow is entirely local:

```text
Local recording
      ↓
Local FFmpeg
      ↓
Local verification
      ↓
Local MP4
```

---

## 💻 Requirements

| Requirement                 | Support                             |
| --------------------------- | ----------------------------------- |
| macOS                       | **14+**                             |
| CPU                         | **Apple Silicon (arm64)**           |
| Intel Macs                  | ❌ Not currently supported          |
| FFmpeg installation         | ✅ Bundled                          |
| Homebrew                    | ❌ Not required at runtime          |
| Account                     | ❌ Not required                     |
| Cloud service               | ❌ Not required                     |
| Screen Recording permission | ❌ Not required for folder watching |

MacPress requires access to its configured watched folder.

macOS may request Files & Folders or other filesystem permissions when protected locations are selected.

---

## 📁 Watched-folder implementation

MacPress monitors one configurable directory for eligible `.mov` files.

On startup:

1. Restore the user's explicitly selected watched folder when available.
2. Otherwise, MacPress may inspect the observed Screenshot.app save-location preference as a best-effort hint.
3. If no suitable directory can be determined, ask the user to choose one.

Filesystem events are used to discover potential recordings.

An event does not necessarily mean that a recording has finished writing, so MacPress waits for the file to become stable before processing it.

MacPress does not claim guaranteed Screenshot.app provenance based solely on filesystem events.

---

## 🛠️ Development

### Clone

```bash
git clone https://github.com/SagarBajpai/macpress.git
cd macpress
```

### Run tests

```bash
swift test
```

### Build

```bash
./scripts/build.sh
```

The resulting application is written to:

```text
dist/MacPress.app
```

### Install locally

```bash
./scripts/install.sh
```

Launch it with:

```bash
open "$HOME/Applications/MacPress.app"
```

Local builds are ad-hoc signed.

---

## 📦 Creating a release build

The root `VERSION` file is the common release version source. `scripts/public_dmg.sh` synchronizes the app metadata, Xcode project, README, and cask when publishing.

Run:

```bash
./scripts/release.sh
```

The release script:

1. runs the relevant tests
2. builds MacPress
3. applies the ad-hoc signature
4. creates the release DMG
5. calculates its SHA-256 checksum

It does not publish anything automatically.

It does not require Apple Developer credentials.

## 🚀 Publishing a DMG release

Use the public release command when the working tree is ready and you intend to publish externally:

```bash
gh auth login
./scripts/public_dmg.sh 0.1.0
```

If no version is supplied, the script asks for one and defaults to `VERSION`. It runs `release.sh`, updates the cask checksum, commits the release, creates and pushes the matching Git tag, creates the GitHub Release, and updates `SagarBajpai/homebrew-macpress`. It requires write access to both repositories.

The resulting output will look similar to:

```text
dist/
├── MacPress.app
└── MacPress-0.1.0-arm64.dmg
```

---

## 🔧 FFmpeg

MacPress bundles arm64 builds of:

- FFmpeg
- FFprobe

The bundled tools and their source/license notices are located under:

[`ThirdParty/FFmpeg`](ThirdParty/FFmpeg)

Normal MacPress development does not require rebuilding FFmpeg.

When intentionally rebuilding the bundled tools, use:

```bash
./scripts/build-ffmpeg.sh
```

FFmpeg is a separate project distributed under its applicable LGPL terms.

See:

[`ThirdParty/FFmpeg/NOTICE.md`](ThirdParty/FFmpeg/NOTICE.md)

for licensing and source information.

---

## 🤝 Contributing

Contributions are welcome.

Please see [CONTRIBUTING.md](CONTRIBUTING.md) for the project's development setup, testing requirements, and pull-request expectations.

Good contributions should aim to:

- keep MacPress lightweight
- preserve source-file safety
- maintain native macOS behaviour
- avoid unnecessary dependencies
- keep processing local-first
- include appropriate tests when behaviour changes

---

## 🐛 Reporting bugs

When opening an issue, useful information includes:

- macOS version
- Mac model/chip
- MacPress version
- selected compression preset
- source recording size/resolution when relevant
- expected behaviour
- actual behaviour
- relevant MacPress logs

> [!WARNING]
> Do not upload private or sensitive screen recordings when reporting bugs.

---

## 🧭 Project philosophy

MacPress intentionally does not try to replace the native macOS screen recorder.

The core idea is:

> **The Mac already has a screen recorder. MacPress just makes its recordings smaller.**

The project aims to remain:

- lightweight
- local-first
- menu-bar native
- focused
- predictable
- safe

Feature additions should support that philosophy rather than turning MacPress into a general-purpose video editor or recording suite.

---

## 📄 License

MacPress is released under the [MIT License](LICENSE).

FFmpeg is a separate project distributed under its applicable LGPL license.

See [`ThirdParty/FFmpeg/NOTICE.md`](ThirdParty/FFmpeg/NOTICE.md) and the accompanying source/license files for details.
