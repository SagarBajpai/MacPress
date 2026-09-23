#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$project_root/scripts/build.sh"
destination="$HOME/Applications/ScreenCompressor.app"
mkdir -p "$HOME/Applications"
ditto "$project_root/dist/ScreenCompressor.app" "$destination"
printf 'Installed %s\n' "$destination"
