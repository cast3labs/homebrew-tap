cask "omac" do
  version "1.4.8"
  sha256 "0870b106644494925c4e947e00c0c07f5f8401a397a3cebb3a3d226cc87dfef9"

  url "https://github.com/evanscastonguay/omac/releases/download/v#{version}/Omac-arm64.zip"
  name "Omac"
  desc "Keyboard-driven tiling window manager"
  homepage "https://github.com/evanscastonguay/omac"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Omac updates itself through Sparkle, once the user opts in. A plain
  # `brew upgrade` still upgrades it when the installed app is older than this
  # cask (Homebrew's default for auto_updates casks).
  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  # ~/Applications, like the curl installer: the Accessibility grant belongs to
  # this one copy, and nothing needs an administrator password.
  app "Omac-#{version}-arm64/Omac.app", target: "~/Applications/Omac.app"
  binary "Omac-#{version}-arm64/Omac.app/Contents/Helpers/omac"

  # A signal, not `quit:`: quitting sends an Apple Event, which asks the user
  # for Automation access on first use.
  uninstall signal: [["TERM", "com.evanscastonguay.omac"]]

  zap trash: [
    "~/.config/omac",
    "~/.local/share/omac",
    "~/.local/state/omac",
    "~/Library/Caches/com.evanscastonguay.omac",
    "~/Library/HTTPStorages/com.evanscastonguay.omac",
    "~/Library/Preferences/com.evanscastonguay.omac.plist",
  ]

  caveats <<~EOS
    Omac is installed but not started. Start it with:
      open ~/Applications/Omac.app
    then allow it in System Settings > Privacy & Security > Accessibility.
    No hotkey works until you do. Check with: omac status

    To start Omac when you log in:
      omac login on

    After `brew upgrade`, the old version keeps running. Restart it with:
      omac quit; while pgrep -x -U "$USER" Omac >/dev/null; do sleep 0.2; done; open ~/Applications/Omac.app

    Before uninstalling, turn that off:
      omac login off
    Homebrew's uninstall cannot reach the running app to do it for you.
  EOS
end
