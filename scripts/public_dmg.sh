#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-}"
if [[ -z "$version" ]]; then
    read -r -p "Release version [$(<"$project_root/VERSION")]: " version
    version="${version:-$(<"$project_root/VERSION")}" 
fi
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Release version must look like 0.1.0" >&2; exit 1; }
command -v gh >/dev/null || { echo "GitHub CLI (gh) is required." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Run gh auth login first." >&2; exit 1; }

cd "$project_root"
[[ -z "$(git status --short)" ]] || { echo "Working tree must be clean before a public release." >&2; git status --short; exit 1; }

printf '%s\n' "$version" > VERSION
perl -0pi -e "s/<key>CFBundleShortVersionString<\\/key><string>[^<]+<\\/string>/<key>CFBundleShortVersionString<\\/key><string>$version<\\/string>/" Resources/Info.plist
perl -0pi -e "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $version;/g" ScreenCompressor.xcodeproj/project.pbxproj
perl -0pi -e "s/version \"[^\"]+\"/version \"$version\"/" Casks/macpress.rb
perl -0pi -e "s/MacPress-[0-9]+\\.[0-9]+\\.[0-9]+-arm64\\.dmg/MacPress-$version-arm64.dmg/g; s/v[0-9]+\\.[0-9]+\\.[0-9]+/v$version/g" README.md DEVELOPMENT.md DMG_RELEASE.md

"$project_root/scripts/release.sh"
dmg="$project_root/dist/MacPress-$version-arm64.dmg"
checksum="$(shasum -a 256 "$dmg" | awk '{print $1}')"
perl -0pi -e "s/sha256 \"[^\"]+\"/sha256 \"$checksum\"/" Casks/macpress.rb

git add VERSION Resources/Info.plist ScreenCompressor.xcodeproj/project.pbxproj Casks/macpress.rb README.md DEVELOPMENT.md DMG_RELEASE.md
git commit -m "release: MacPress v$version"
git tag -a "v$version" -m "MacPress v$version"
git push origin HEAD
git push origin "v$version"
gh release create "v$version" "$dmg" --title "MacPress v$version" --generate-notes --notes "Ad-hoc signed, arm64 DMG. macOS may require Open Anyway on first launch. SHA-256: $checksum"

tap_dir="$(mktemp -d "${TMPDIR:-/tmp}/homebrew-macpress.XXXXXX")"
trap 'rm -rf "$tap_dir"' EXIT
git clone git@github.com:SagarBajpai/homebrew-macpress.git "$tap_dir/tap"
mkdir -p "$tap_dir/tap/Casks"
cp Casks/macpress.rb "$tap_dir/tap/Casks/macpress.rb"
git -C "$tap_dir/tap" add Casks/macpress.rb
if ! git -C "$tap_dir/tap" diff --cached --quiet; then
    git -C "$tap_dir/tap" commit -m "feat: update MacPress v$version cask"
    git -C "$tap_dir/tap" push origin HEAD
fi

printf 'Published MacPress v%s\nDMG: %s\nSHA-256: %s\n' "$version" "$dmg" "$checksum"
