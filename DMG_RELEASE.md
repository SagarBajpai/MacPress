# MacPress DMG Release

This project currently distributes ad-hoc signed, non-notarized DMGs. A release does not require Apple Developer Program membership, Developer ID certificates, or notarization credentials.

The canonical public command is:

```bash
gh auth login
./scripts/public_dmg.sh 0.1.0
```

It builds the DMG, updates the checksum and release references, publishes the GitHub Release, and updates `SagarBajpai/homebrew-macpress`. Use the manual steps below only when debugging or intentionally avoiding publication.

## Before the first release

1. Create or confirm the public GitHub repository:

   ```text
   https://github.com/SagarBajpai/MacPress
   ```

2. Confirm the repository contains the tag-triggered workflow at:

   ```text
   .github/workflows/release.yml
   ```

3. Create a separate custom Homebrew tap repository when ready, normally:

   ```text
   SagarBajpai/homebrew-macpress
   ```

   Copy `Casks/macpress.rb` into that repository’s `Casks/` directory after replacing the release checksum.

## Prepare a release

Update the version consistently in:

- `Resources/Info.plist` (`CFBundleShortVersionString`)
- `ScreenCompressor.xcodeproj/project.pbxproj` (`MARKETING_VERSION`)
- `Casks/macpress.rb` (`version`)

Run the local checks:

```bash
swift test
./scripts/build.sh
./scripts/create-dmg.sh \
  dist/MacPress.app \
  dist/MacPress-0.1.0-arm64.dmg
shasum -a 256 dist/MacPress-0.1.0-arm64.dmg
```

The DMG script refuses to overwrite an existing file. Use a new versioned output path or move an old local artifact out of `dist/` before rebuilding.

Update `Casks/macpress.rb` with the new version, release URL, and SHA-256 checksum. Do not update the cask until the final DMG checksum is known.

## Commit and trigger GitHub Actions

Review the complete diff and commit the release changes:

```bash
git status
git diff --check
git add .
git commit -m "release: MacPress v0.1.0"
git push origin main
```

Create and push the matching tag:

```bash
git tag -a v0.1.0 -m "MacPress v0.1.0"
git push origin v0.1.0
```

Pushing a tag matching `v*.*.*` starts `.github/workflows/release.yml`. The workflow:

1. checks out the tagged source
2. runs `swift test`
3. runs `scripts/release.sh`
4. builds the ad-hoc signed `MacPress.app`
5. creates `MacPress-0.1.0-arm64.dmg`
6. calculates the DMG SHA-256 checksum
7. creates the GitHub Release and uploads the DMG

No Apple or GitHub secrets are required by the current workflow.

## Monitor and verify

Using GitHub CLI:

```bash
gh run list --workflow Release
gh run watch
gh release view v0.1.0
gh release download v0.1.0
```

Verify the downloaded artifact locally:

```bash
shasum -a 256 MacPress-0.1.0-arm64.dmg
```

The checksum must match the value printed by the workflow and the cask.

## Update the custom Homebrew tap

After the GitHub Release exists:

1. Copy/update `Casks/macpress.rb` in `SagarBajpai/homebrew-macpress`.
2. Set the final release version and checksum.
3. Commit and push the tap change.
4. Test installation:

   ```bash
   brew untap SagarBajpai/macpress 2>/dev/null || true
   brew tap SagarBajpai/macpress
   brew install --cask macpress
   ```

The cask is a custom tap, not an official Homebrew Cask. Do not claim official Homebrew availability until it is accepted into the official repository.

## First launch warning

The DMG is currently not notarized. macOS Gatekeeper may block the first launch. Users should use the per-app **Open Anyway** option under **System Settings → Privacy & Security**, or Control-click the app in Finder and choose **Open**. Do not disable Gatekeeper globally.

## Release ownership and permissions

The repository being public does not allow every GitHub user to publish releases. Only the repository owner, collaborators with write/maintain/admin permission, or authorized GitHub Actions identities can push to the protected release branch, push tags, or create releases. Anyone can fork the repository and create releases in their own fork.

Do not push a tag until the version, DMG, checksum, README, and cask are ready.
