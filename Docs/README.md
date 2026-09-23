# Documentation index

This documentation describes the current native macOS implementation. Read `AGENTS.md` first, then this index and only the documents relevant to your task.

| If you are working on… | Read |
| --- | --- |
| Overall architecture or lifecycle | [ARCHITECTURE.md](../ARCHITECTURE.md), [data-flow.md](data-flow.md) |
| Menu-bar UI, recent jobs, errors, or launch at login | [product.md](product.md), [data-flow.md](data-flow.md) |
| Watcher, queue, stabilization, cleanup, or safety | [data-flow.md](data-flow.md), [testing.md](testing.md) |
| Presets, advanced settings, FFmpeg flags, or media probing | [compression.md](compression.md), [data-flow.md](data-flow.md) |
| Build, bundled binaries, signing, DMG, notarization, or licensing | [distribution.md](distribution.md) |
| Tests, benchmarks, or verification | [testing.md](testing.md), [distribution.md](distribution.md) |

## Evidence convention

Statements in these documents describe verified current code unless marked **inferred** or **unknown**. Paths point to implementation boundaries rather than every function. Optional benchmarks are not evidence of universal compression ratios; results depend on the recording.
