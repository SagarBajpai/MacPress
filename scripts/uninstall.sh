#!/usr/bin/env bash
set -euo pipefail

bundle_id="com.sagarbajpai.ScreenCompressor"
paths=(
    "$HOME/Applications/MacPress.app"
    "/Applications/MacPress.app"
    "$HOME/Library/Logs/ScreenCompressor"
)

echo "This removes MacPress.app, MacPress preferences, and MacPress logs."
echo "It does not remove recordings, the watched folder, or legacy LaunchAgents."
read -r -p "Continue? [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }

osascript -e 'tell application "MacPress" to quit' >/dev/null 2>&1 || true

for path in "${paths[@]}"; do
    if [[ -e "$path" ]]; then
        rm -rf -- "$path"
        printf 'Removed %s\n' "$path"
    fi
done

defaults delete "$bundle_id" >/dev/null 2>&1 || true
echo "Removed MacPress preferences."
echo "MacPress uninstall complete."
