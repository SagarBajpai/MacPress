cask "macpress" do
  version "0.2.0"
  sha256 "60d75ec79ead85af8a72aca4fdf7f264ae6eddef5e185b21d8052630a0efb710"

  url "https://github.com/SagarBajpai/MacPress/releases/latest/download/MacPress-arm64.dmg"
  name "MacPress"
  desc "Automatically compress macOS screen recordings"
  homepage "https://github.com/SagarBajpai/MacPress"

  depends_on macos: :sonoma

  app "MacPress.app"
end
