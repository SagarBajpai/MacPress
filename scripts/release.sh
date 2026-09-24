#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$project_root/Resources/Info.plist")"
dmg="$project_root/dist/MacPress-$version-arm64.dmg"

[[ ! -e "$dmg" ]] || { echo "Refusing to overwrite $dmg" >&2; exit 1; }

cd "$project_root"
CODESIGN_IDENTITY="-" "$project_root/scripts/build.sh"
app="$project_root/dist/MacPress.app"
SCREEN_COMPRESSOR_INTEGRATION_TESTS=1 SCREEN_COMPRESSOR_TEST_APP="$app" swift test
"$project_root/scripts/create-dmg.sh" "$app" "$dmg"
shasum -a 256 "$dmg"
printf 'Ad-hoc release: %s\n' "$dmg"
