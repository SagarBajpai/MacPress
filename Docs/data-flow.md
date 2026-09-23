# Processing and safety data flow

## Intake to output

```text
filesystem event
  → FolderWatcher callback
  → JobQueue.scan()
  → canonicalized .mov in pending/seen
  → FileStabilizationService.waitUntilStable()
  → settings snapshot
  → CompressionService.compress()
  → ffprobe source facts
  → FFmpegArgumentBuilder
  → ProcessRunner / ffmpeg
  → partial output verification
  → FileNameGenerator final output
  → FileCleanupService.trashSource()
  → CompressionResult / MenuBarViewModel
```

`FolderWatcher` uses a native `DispatchSource` vnode watcher and debounce. It requests a scan rather than passing an assumed file directly to the encoder. Startup also scans the directory, so files created before launch are eligible.

`JobQueue` is an actor. `seen` prevents duplicate filesystem events in one session; `pending` preserves serial work. The worker drains one file at a time. `BatchProgressTracker` keeps the batch denominator stable, counts failures as completed slots, and reports progress back to the main-actor view model.

## Stabilization

`FileStabilizationService` checks size repeatedly, requiring unchanged non-zero size for the configured number of checks. The default interval is two seconds, three checks, and a 30-second timeout. It uses async sleep and checks cancellation.

## Compression safety

`CompressionService` captures source size and identity before encoding. FFmpeg writes a UUID-named hidden `.processing.mp4`, never a user-visible destination. On any error it removes only that partial path and rethrows while leaving the source untouched.

Verification requires a non-empty output. If FFprobe is available, it also requires parseable media, positive duration, and the requested codec. The final destination is chosen after verification with `FileNameGenerator`, preserving existing files. Only after final output exists and source identity has not changed does `FileCleanupService` move the source to Trash.

## Event/UI state

`JobEvent` carries queued, stabilizing, processing, completed, failed, batch, and monitoring-error events. The view model translates these into current file, progress, recent results, error, and menu-bar icon state. Technical errors are logged; the primary menu shows concise user-facing text.

## Failure paths

FFmpeg missing, source missing, stabilization timeout, process failure, cancellation, FFprobe failure, invalid output, source mutation, collision, or Trash failure must not lose the source. A Trash failure leaves the verified final output and the source in place, which is safer than retrying destructive cleanup implicitly.
