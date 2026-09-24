#!/usr/bin/env bash
set -euo pipefail

app_directory="${1:?Pass the .app path}"
output_dmg="${2:?Pass the output .dmg path}"
[[ -d "$app_directory" ]] || { echo "App not found: $app_directory" >&2; exit 1; }
[[ ! -e "$output_dmg" ]] || { echo "Refusing to overwrite $output_dmg" >&2; exit 1; }

staging="$(mktemp -d "${TMPDIR:-/tmp}/ScreenCompressorDMG.XXXXXX")"
trap 'rm -r -- "$staging"' EXIT
ditto "$app_directory" "$staging/MacPress.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname 'MacPress' -srcfolder "$staging" -format UDZO "$output_dmg"
printf 'Created %s\n' "$output_dmg"
