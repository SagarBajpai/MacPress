#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
swift build -c release
binary_directory="$(swift build -c release --show-bin-path)"
lipo "$binary_directory/ScreenCompressor" -verify_arch arm64
app_directory="$project_root/dist/MacPress.app"
rm -rf "$app_directory"
mkdir -p "$app_directory/Contents/MacOS"
cp "$binary_directory/ScreenCompressor" "$app_directory/Contents/MacOS/MacPress"
cp "$project_root/Resources/Info.plist" "$app_directory/Contents/Info.plist"
identity="${CODESIGN_IDENTITY:--}"
"$project_root/scripts/copy-ffmpeg-resources.sh" "$app_directory" "$identity"
signing_options=(--force --sign "$identity" --options runtime)
if [[ "$identity" != "-" ]]; then signing_options+=(--timestamp); fi
codesign "${signing_options[@]}" "$app_directory"
"$project_root/scripts/verify-ffmpeg-bundle.sh" "$app_directory"
codesign --verify --deep --strict --verbose=2 "$app_directory"
printf 'Built %s\n' "$app_directory"
