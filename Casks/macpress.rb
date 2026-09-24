cask "macpress" do
  version "0.1.0"
  sha256 "REPLACE_WITH_RELEASE_SHA256"

  url "https://github.com/YOUR_GITHUB_OWNER/MacPress/releases/download/v#{version}/MacPress-#{version}-arm64.dmg"
  name "MacPress"
  desc "Automatically compress macOS screen recordings"
  homepage "https://github.com/YOUR_GITHUB_OWNER/MacPress"

  depends_on macos: ">= :sonoma"

  app "MacPress.app"
end
