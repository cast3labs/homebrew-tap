# Spike F4, extra probe: V3 with the plan's literal "~" target in args.
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

  # Expected to fail: the sandboxed step runs with a temporary HOME and no
  # shell, so this "~" reaches xattr unexpanded.
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "~/Applications/Omac.app"],
        writable_paths: ["~/Applications/Omac.app"],
        must_succeed:   true
  end

  zap trash: [
    "~/.config/omac",
    "~/.local/state/omac",
  ]
end
