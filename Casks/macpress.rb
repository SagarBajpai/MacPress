cask "macpress" do
  version "0.1.0"
  sha256 "625f13bd10ad2c6fcf1c942a5a088f0ac785c578b3a4f54146482f245864b3d7"

  url "https://github.com/SagarBajpai/MacPress/releases/latest/download/MacPress-arm64.dmg"
  name "MacPress"
  desc "Automatically compress macOS screen recordings"
  homepage "https://github.com/SagarBajpai/MacPress"

  depends_on macos: ">= :sonoma"

  app "MacPress.app"
end
