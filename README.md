# evanscastonguay/homebrew-tap

Homebrew casks for [Omac](https://github.com/evanscastonguay/omac), a tiling
window manager for macOS: Omarchy's window keys on your Mac, one app, nothing
else to install.

**Omac is not in this tap yet.** Until it is, install it with one command:

```bash
curl -fsSL https://raw.githubusercontent.com/evanscastonguay/omac/main/install.sh | bash
```

Once the cask lands, this will work:

```bash
brew install --cask evanscastonguay/tap/omac
```

`ci/expected-dr.txt` is the app's designated requirement — the signing identity
macOS ties the Accessibility permission to. The tap's checks compare every
release against it, so a cask can never install an app signed by anyone else.

Omac is an independent, unofficial project. It is not affiliated with or
endorsed by Omarchy or its authors. MIT License.
