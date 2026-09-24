#!/usr/bin/env bash
set -euo pipefail

app="${1:?Pass the MacPress.app path}"
dmg="${2:-}"

[[ -d "$app" ]] || { echo "App not found: $app" >&2; exit 1; }
codesign --verify --deep --strict --verbose=2 "$app"
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify-ffmpeg-bundle.sh" "$app"

if [[ -n "$dmg" ]]; then
    [[ -f "$dmg" ]] || { echo "DMG not found: $dmg" >&2; exit 1; }
    shasum -a 256 "$dmg"
fi
