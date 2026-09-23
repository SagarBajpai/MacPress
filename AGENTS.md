# AGENTS.md

## Project Overview

**Screen Compressor** is a native macOS menu-bar application that automatically detects macOS screen recordings, compresses them using hardware-accelerated HEVC/H.265 via `ffmpeg`, verifies the result, and safely moves the original recording to Trash.

The application replaces a previous Bash + `fswatch` + LaunchAgent implementation.

The application should feel like a small, polished native macOS utility.

Primary priorities, in order:

1. Never lose a user's original recording.
2. Reliability.
3. Correctness.
4. Native macOS UX.
5. Simplicity.
6. Performance.
7. Extensibility.

---

# Technology

Use:

- Swift
- SwiftUI
- `MenuBarExtra`
- Foundation
- AppKit where required
- `Process`
- `FileManager`
- `SMAppService`
- Swift Concurrency
- native macOS filesystem APIs
- `ffmpeg`
- `ffprobe`
- XCTest

Target modern macOS.

Apple Silicon is the primary target.

Do NOT introduce:

- Electron
- Tauri
- React
- Node.js
- Python
- webviews
- unnecessary third-party dependencies
- `fswatch`

Prefer Apple frameworks and the Swift standard library.

A third-party dependency must have a strong justification before being introduced.

---

# Repository Structure

Keep responsibilities separated.

Preferred structure:

```text
ScreenCompressor/
├── App/
│   └── ScreenCompressorApp.swift
│
├── MenuBar/
│   ├── MenuBarView.swift
│   └── MenuBarViewModel.swift
│
├── Models/
│   ├── CompressionJob.swift
│   ├── CompressionStatus.swift
│   └── CompressionResult.swift
│
├── Services/
│   ├── FolderWatcher.swift
│   ├── CompressionService.swift
│   ├── FileStabilizationService.swift
│   ├── FFmpegService.swift
│   ├── LaunchAtLoginService.swift
│   ├── LoggingService.swift
│   └── FileCleanupService.swift
│
├── Utilities/
│   ├── FileNameGenerator.swift
│   ├── FileSizeFormatter.swift
│   └── FFmpegProgressParser.swift
│
└── Resources/

ScreenCompressorTests/

scripts/
├── build.sh
└── install.sh
```

This structure is guidance rather than a rigid rule.

If functionality grows substantially, create a dedicated type/file instead of allowing existing files to become excessively large.

---

# Architecture

The primary processing pipeline is:

```text
FolderWatcher
     ↓
Job Queue
     ↓
FileStabilizationService
     ↓
FileNameGenerator
     ↓
FFmpegService
     ↓
Output Verification
     ↓
FileCleanupService
     ↓
CompressionResult
     ↓
MenuBarViewModel
```

Each component should have one clear responsibility.

Do not put filesystem monitoring, ffmpeg execution, filename generation, cleanup, and UI state management into the same object.

---

# Data Safety

This is the most important rule in this repository.

## NEVER delete or Trash the source recording until the output has been successfully verified.

The safe lifecycle is:

```text
source.mov
    ↓
stabilize
    ↓
compress
    ↓
temporary/new output
    ↓
ffmpeg success
    ↓
verify output exists
    ↓
verify output size > 0
    ↓
verify media when possible
    ↓
ONLY NOW
    ↓
move source.mov to Trash
```

If anything fails before verification:

```text
source.mov MUST remain untouched
```

This includes:

- ffmpeg failure
- ffmpeg crash
- app crash
- cancellation
- invalid output
- ffprobe failure
- filesystem error
- permission error
- application shutdown

When uncertain, preserve the original.

---

# File Deletion Rules

Never:

```swift
try FileManager.default.removeItem(at: sourceURL)
```

for an original recording during the normal successful workflow.

Use macOS Trash:

```swift
try FileManager.default.trashItem(
    at: sourceURL,
    resultingItemURL: nil
)
```

Only partial output files created by this application may be permanently removed automatically.

Before deleting a partial output, verify that it belongs to the current compression attempt.

Never recursively delete:

```text
~/Screenshots
```

or any watched directory.

Never perform broad wildcard deletion.

---

# Existing Files

Never overwrite an existing recording or compressed output.

If:

```text
23 Sep 4:45PM.mp4
```

already exists, generate another filename.

For example:

```text
23 Sep 4:45PM 23.mp4
```

If that exists too, continue generating a unique filename.

Collision handling must be deterministic and safe.

Use `FileNameGenerator`.

Do not solve collisions by passing `-y` to ffmpeg against an existing user file.

If `-y` is used for application-created temporary destinations, the application must first guarantee that the path is exclusively owned by the current job.

---

# Watched Directory

Default:

```text
~/Screenshots
```

Watch for:

```text
.mov
```

case-insensitively.

Ignore:

- `.mp4`
- directories
- hidden files
- temporary files
- files created by this application's output process
- unrelated file formats

Use native filesystem monitoring.

Avoid polling loops unless a native API cannot reasonably provide the required behavior.

---

# Startup Scan

When the application launches, scan the watched directory for unprocessed `.mov` files.

A file can have states such as:

```text
detected
queued
stabilizing
processing
completed
failed
```

Do not enqueue the same file multiple times during the same application session.

Filesystem events may fire multiple times for the same file. The application must tolerate this.

---

# File Stabilization

Screen recordings may appear in the directory before macOS has finished writing them.

Never immediately start compression after receiving a filesystem event.

Default stabilization behavior:

```text
check size
wait 2 seconds
check size
wait 2 seconds
check size
```

Require the file to remain unchanged for at least two consecutive checks.

Maximum default stabilization wait:

```text
30 seconds
```

Do not block the main thread.

Use async operations.

Stabilization configuration should remain centralized and configurable.

---

# Compression Queue

Only one recording should be compressed at a time.

Do not run multiple hardware HEVC encoding jobs concurrently.

Expected behavior:

```text
A → processing
B → queued
C → queued
```

followed by:

```text
A → completed
B → processing
C → queued
```

Queue coordination should be race-safe.

Prefer an `actor` when appropriate.

---

# Swift Concurrency

Prefer modern Swift concurrency.

Use:

- `async/await`
- `Task`
- actors
- `@MainActor`

where appropriate.

Do not introduce unnecessary callback pyramids.

Never perform:

- ffmpeg execution
- ffprobe execution
- stabilization waiting
- large filesystem operations

synchronously on the main thread.

UI state belongs on the main actor.

---

# ffmpeg

Expected primary path:

```text
/opt/homebrew/bin/ffmpeg
```

Also support common alternatives such as:

```text
/usr/local/bin/ffmpeg
```

and PATH discovery when practical.

Do not assume Homebrew is always installed at one location.

If ffmpeg is unavailable, fail gracefully.

Never automatically install ffmpeg.

---

# ffprobe

Use ffprobe for media metadata such as duration and output validation.

Discover it independently instead of blindly assuming it exists because ffmpeg exists.

If ffprobe is unavailable, degrade gracefully where possible.

A missing ffprobe must not crash the application.

---

# Process Execution

Launch ffmpeg using `Process`.

Correct approach:

```swift
let process = Process()

process.executableURL = ffmpegURL
process.arguments = arguments
```

Do NOT use:

```text
/bin/bash -c "ffmpeg ..."
```

Do NOT construct shell command strings using user-controlled filenames.

Passing arguments directly prevents shell escaping and injection problems.

Capture:

- stdout
- stderr
- termination status

---

# Compression Defaults

Default video configuration:

```text
Codec: HEVC / H.265
Encoder: hevc_videotoolbox
Quality: 28
```

Default audio:

```text
Codec: AAC
Bitrate: 128k
```

Preferred equivalent command:

```bash
ffmpeg \
  -hwaccel videotoolbox \
  -i input.mov \
  -c:v hevc_videotoolbox \
  -q:v 28 \
  -c:a aac \
  -b:a 128k \
  -tag:v hvc1 \
  -progress pipe:1 \
  -nostats \
  output.mp4
```

Compression configuration must be centralized.

Do not scatter values such as `28`, `128k`, stabilization intervals, or directory paths throughout the codebase.

---

# Progress Reporting

Progress must come from ffmpeg.

Do not fake progress with timers.

Use:

```text
-progress pipe:1
```

Parse values including:

```text
out_time_us
out_time_ms
out_time
speed
progress
```

Obtain total source duration using ffprobe.

Calculate:

```text
processedDuration / totalDuration
```

Clamp progress between:

```text
0.0 ... 1.0
```

If total duration is unavailable, use an indeterminate progress state.

Do not invent a percentage.

---

# FFmpegProgressParser

Progress parsing should remain independent of UI code.

Example input:

```text
frame=120
fps=60
out_time_us=4821000
speed=3.14x
progress=continue
```

The parser should return structured values.

Malformed or unknown fields should not crash processing.

ffmpeg may introduce fields that the parser does not recognize.

Ignore unknown fields safely.

---

# Output Naming

Default format:

```text
dd MMM h:mma
```

Example:

```text
23 Sep 4:45PM.mp4
```

Prefer using the recording timestamp when appropriate.

Collision example:

```text
23 Sep 4:45PM 23.mp4
```

Never overwrite.

Filename generation belongs in:

```text
FileNameGenerator
```

and should be unit-tested.

---

# Output Verification

Do not trust ffmpeg exit status alone.

Successful compression requires at minimum:

```text
ffmpeg exit code == 0
AND
output exists
AND
output size > 0
```

When ffprobe is available, validate that the output is readable media.

Only then may source cleanup begin.

---

# Partial Outputs

If compression fails:

```text
source.mov
```

must remain.

An incomplete MP4 created by the current job should be removed.

Prefer using a temporary output strategy where practical:

```text
23 Sep 4:45PM.processing.mp4
```

then after successful verification:

```text
23 Sep 4:45PM.mp4
```

A temporary file must never be mistaken for a completed recording.

If implementing atomic rename/finalization, ensure the final destination still cannot overwrite an existing user file.

---

# Cancellation

Cancellation must be safe.

If processing is cancelled:

1. Request ffmpeg termination.
2. Wait appropriately for process termination.
3. Remove only the partial output created by the job.
4. Preserve the source.
5. Update job state.

Application shutdown must follow the same principle.

---

# Menu-Bar UI

The primary interface is `MenuBarExtra`.

The application should normally have:

```text
no Dock icon
no persistent main window
```

Keep UI native and compact.

Example:

```text
Screen Compressor

● Compressing

Recording.mov
██████████████░░░ 72%

8.4 MB → 1.8 MB
Elapsed 00:07

Recent
✓ 23 Sep 12:20PM.mp4
✓ 23 Sep 11:48AM.mp4

Open Screenshots Folder
View Logs
Launch at Login ✓
Quit
```

Use:

- SwiftUI
- SF Symbols
- native controls
- native typography
- native spacing

Do not create web-style UI components.

---

# UI State

At minimum represent:

```text
Idle
Processing
Error
```

The menu-bar icon should reflect these states without becoming distracting.

Keep detailed technical errors out of the primary UI.

Display concise user-facing messages and send detailed information to logs.

---

# Recent Jobs

Keep approximately five recent jobs in memory.

Successful result should contain:

```text
source URL
output URL
source size
output size
compression percentage
completion date
```

Failed result should contain:

```text
source URL
failure reason
timestamp
```

Persistent history is not required yet.

Do not introduce a database for V1.

---

# Logging

Logs belong under:

```text
~/Library/Logs/ScreenCompressor/
```

Primary log:

```text
screen-compressor.log
```

Log useful lifecycle events:

```text
application startup
watcher started
file detected
job queued
stabilization started
stabilization completed
compression started
compression progress milestones
compression completed
verification completed
source trashed
errors
application shutdown
```

Avoid logging every tiny progress event if it creates excessive log volume.

Progress milestone logging such as:

```text
10%
25%
50%
75%
100%
```

is preferable.

Do not allow logs to grow indefinitely.

Keep rotation simple.

---

# Errors

Errors should be typed where useful.

Examples:

```swift
enum CompressionError: Error {
    case ffmpegNotFound
    case ffprobeNotFound
    case sourceMissing
    case stabilizationTimeout
    case processLaunchFailed
    case compressionFailed
    case invalidOutput
    case cleanupFailed
}
```

Exact design may differ.

Errors exposed to users should be understandable.

Errors written to logs should preserve technical context.

Never silently swallow an error.

---

# Launch at Login

Use:

```swift
SMAppService.mainApp
```

Do not create a new LaunchAgent-based architecture.

Support:

```text
register
unregister
status
```

The UI should accurately reflect actual launch-at-login status.

Handle registration errors.

---

# Existing Legacy Installation

A developer machine may already contain:

```text
~/.local/scripts/compress-screen-recording.sh

~/Library/LaunchAgents/local.screen-recording-compressor.plist

~/.local/logs/compress-screen-recording.log
```

Do NOT modify or delete these automatically.

Do NOT unload the old LaunchAgent automatically.

Migration remains an explicit user action.

Document migration in README.

---

# Configuration

Centralize application defaults.

For example:

```swift
struct AppConfiguration {
    let watchDirectory: URL
    let stabilizationInterval: Duration
    let stabilizationChecks: Int
    let stabilizationTimeout: Duration
}

struct CompressionConfiguration {
    let videoQuality: Int
    let audioBitrate: String
    let codec: VideoCodec
}
```

Do not treat this exact API as mandatory.

The principle is:

**Configuration belongs in configuration types, not scattered literals.**

---

# Swift Style

Prefer simple, readable Swift.

Use:

```swift
let sourceURL = job.sourceURL
let outputURL = filenameGenerator.outputURL(for: job)

let result = try await compressionService.compress(
    source: sourceURL,
    destination: outputURL
)
```

over deeply nested expressions.

Prefer intermediate variables when they improve readability.

Avoid clever one-liners.

---

# Force Unwrapping

Avoid:

```swift
value!
```

Prefer:

```swift
guard let value else {
    throw ...
}
```

Force unwrap only when the invariant is genuinely guaranteed and obvious.

If the reason is non-obvious, document it.

---

# Type Safety

Prefer meaningful domain types over unstructured dictionaries.

Good:

```swift
struct CompressionProgress {
    let fractionCompleted: Double?
    let processedDuration: Duration?
    let speed: Double?
}
```

Avoid passing `[String: Any]` through application layers.

---

# Protocols

Use protocols where they improve:

- testing
- dependency injection
- separation between OS/process APIs and business logic

Do not create protocols for every trivial struct.

Avoid architecture ceremony without practical value.

---

# Comments

Comments should explain **why**, not repeat **what** the code does.

Bad:

```swift
// Set progress
progress = value
```

Good:

```swift
// ffmpeg can occasionally report a timestamp slightly beyond the
// source duration, so clamp the UI value to 100%.
progress = min(value, 1)
```

---

# Tests

Business logic should be independently testable.

At minimum maintain tests for:

## FileNameGenerator

Test:

- normal generation
- first collision
- repeated collision
- extension handling

## FFmpegProgressParser

Test:

- `out_time_us`
- `out_time_ms`
- `out_time`
- `speed`
- `progress=continue`
- `progress=end`
- malformed values
- unknown values

## Compression Ratio

Example:

```text
10 MB → 2.5 MB = 75% saved
```

Handle edge cases such as zero-byte source safely.

## Stabilization

Do not make tests literally sleep for 30 seconds.

Abstract time/file metadata sufficiently for fast deterministic tests.

---

# Testing Philosophy

Do not write tests merely to increase coverage.

Prioritize tests around code that could cause:

- data loss
- overwrites
- incorrect cleanup
- duplicate processing
- incorrect progress
- filename collisions

Data-safety logic deserves particularly strong tests.

---

# Git

The repository must contain:

```text
.git/
.gitignore
```

Never commit:

```text
.DS_Store
DerivedData/
xcuserdata/
*.xcuserstate
.build/
.swiftpm/
logs
temporary compression output
credentials
```

Before completing significant work, check:

```bash
git status
```

Do not commit unrelated local files.

---

# Commits

Prefer Conventional Commits.

Examples:

```text
feat: add native folder watcher

feat: add ffmpeg compression progress

fix: preserve source when output verification fails

fix: prevent duplicate filesystem events from queuing jobs

refactor: extract filename generation

test: add compression progress parser coverage

docs: document launch at login setup
```

Commits should represent coherent changes.

Do not use meaningless messages such as:

```text
update
changes
fix stuff
```

---

# Build

The project must remain buildable from Xcode.

Also maintain CLI build support where practical:

```bash
./scripts/build.sh
```

Before considering a substantial implementation complete:

```text
build
↓
test
↓
fix
↓
build again
```

Do not claim that something builds unless it was actually built in the current environment.

If build verification is impossible because of environment limitations, explicitly report that.

---

# Scripts

Shell scripts must begin with:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

Quote variables:

```bash
"$VARIABLE"
```

Avoid dangerous patterns such as:

```bash
rm -rf $VARIABLE
```

especially when variables could be empty.

Never create scripts capable of accidentally deleting arbitrary user directories.

---

# Dependencies

Prefer zero third-party Swift dependencies.

Before introducing one, ask:

1. Can Foundation/AppKit/SwiftUI already do this?
2. Is the dependency actively maintained?
3. Does it materially simplify complex functionality?
4. Is adding supply-chain/build complexity justified?

For small functionality, implement it locally.

`ffmpeg`/`ffprobe` are expected external runtime dependencies.

---

# Performance

Do not optimize prematurely.

However:

- never block the main thread
- avoid repeated full-directory scans
- debounce/coalesce duplicate filesystem events where useful
- avoid loading video contents into memory
- stream process output
- keep recent history bounded
- keep logs bounded

Videos should always be processed as files/streams, never loaded entirely into RAM.

---

# Security

Never pass filenames through shell interpolation.

Use:

```swift
Process.arguments
```

Treat filesystem paths as URLs.

Do not execute arbitrary user-provided command strings.

Do not automatically install packages.

Do not request broader permissions than necessary.

---

# macOS UX

Follow standard macOS conventions.

Use:

```swift
NSWorkspace.shared.open(...)
```

for opening folders/files where appropriate.

Use:

```swift
FileManager.default.trashItem(...)
```

for Trash.

Use:

```swift
SMAppService
```

for launch at login.

Use SF Symbols instead of custom icons where appropriate.

Prefer native controls over custom recreations.

---

# Scope Control

Do not expand V1 unnecessarily.

Current required functionality:

- menu-bar application
- startup/login support
- watch `~/Screenshots`
- detect `.mov`
- stabilization
- serial queue
- HEVC compression
- real ffmpeg progress
- verification
- safe source cleanup
- recent jobs
- errors
- logs
- open Screenshots folder
- view logs
- quit

Future functionality may include:

- settings window
- custom directories
- codec selection
- quality controls
- pause monitoring
- keep-original option
- notifications
- persistent history
- drag and drop
- compression statistics
- batch processing
- automatic updates
- signed/notarized distribution

Do not implement future features merely because they are listed here.

Keep the architecture ready for them.

---

# When Modifying Existing Code

Before making a change:

1. Understand the existing architecture.
2. Find the responsible component.
3. Avoid duplicating existing functionality.
4. Preserve data-safety guarantees.
5. Consider concurrency implications.
6. Consider filesystem race conditions.
7. Update/add tests when behavior changes.

Do not rewrite large working sections unless the rewrite has a concrete benefit.

Prefer targeted changes.

---

# Debugging

When a bug occurs, find the root cause rather than hiding symptoms.

Useful areas to inspect:

```text
~/Library/Logs/ScreenCompressor/
```

and:

```text
ffmpeg stderr
ffmpeg exit status
filesystem events
job state transitions
stabilization state
```

Never respond to a race condition by adding arbitrary sleeps unless the sleep represents a legitimate external-state requirement such as file stabilization.

---

# Agent Workflow

When implementing a task:

```text
1. Inspect relevant existing files.
2. Understand current behavior.
3. Plan the smallest coherent change.
4. Implement.
5. Add/update tests.
6. Build.
7. Run tests.
8. Fix issues.
9. Review data-safety implications.
10. Check git diff.
11. Check git status.
```

Do not stop after writing code if build/test tools are available.

---

# Definition of Done

A task is not complete merely because code was generated.

For implementation work, completion generally means:

```text
code implemented
+
compiles
+
relevant tests pass
+
no obvious regression
+
data-safety guarantees preserved
+
git diff reviewed
```

Report any step that could not be verified.

---

# Critical Invariant

Every contributor and coding agent working on this repository must preserve this invariant:

> A compression failure must never cause the loss of the original screen recording.

When there is a trade-off between aggressive cleanup and preserving user data:

**Preserve the user data.**
