#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
identity="${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to your Developer ID Application certificate name}"
profile="${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$project_root/Resources/Info.plist")"
dmg="$project_root/dist/ScreenCompressor-$version-arm64.dmg"

[[ ! -e "$dmg" ]] || { echo "Refusing to overwrite $dmg" >&2; exit 1; }
security find-identity -v -p codesigning | grep -Fq "$identity" || {
    echo "Developer ID signing identity not available in this keychain: $identity" >&2
    exit 1
}

cd "$project_root"
CODESIGN_IDENTITY="$identity" "$project_root/scripts/build.sh"
app="$project_root/dist/ScreenCompressor.app"
SCREEN_COMPRESSOR_INTEGRATION_TESTS=1 SCREEN_COMPRESSOR_TEST_APP="$app" swift test
codesign --verify --deep --strict --verbose=2 "$app"
"$project_root/scripts/create-dmg.sh" "$app" "$dmg"
codesign --force --sign "$identity" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
printf 'Notarized release: %s\n' "$dmg"
