#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
swift build -c release
binary_directory="$(swift build -c release --show-bin-path)"
app_directory="$project_root/dist/ScreenCompressor.app"
mkdir -p "$app_directory/Contents/MacOS"
cp "$binary_directory/ScreenCompressor" "$app_directory/Contents/MacOS/ScreenCompressor"
cp "$project_root/Resources/Info.plist" "$app_directory/Contents/Info.plist"
codesign --force --sign - "$app_directory"
printf 'Built %s\n' "$app_directory"
