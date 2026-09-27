# Spike F4, variant V2: installs to ~/Applications, no quarantine step.
cask "omac" do
  version "1.4.7"
  sha256 "a064aeee7f13f0a23207b119a05032c1cd0100f915ceb6ce797e0386ede1d92e"

  url "https://github.com/evanscastonguay/omac/releases/download/v#{version}/Omac-arm64.zip"
  name "Omac"
  desc "Keyboard-driven tiling window manager"
  homepage "https://github.com/evanscastonguay/omac"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Omac-#{version}-arm64/Omac.app", target: "~/Applications/Omac.app"

  zap trash: [
    "~/.config/omac",
    "~/.local/state/omac",
  ]
end
