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
macOS ties the Accessibility permission to. Today the tap's CI only checks that
this file is present and names Omac's team. Once the cask lands, CI will also
download each release the cask points at, check its checksum, and compare its
signature against this file before the cask can be merged. It is a pre-merge
check: `brew install` itself does not run it.

Omac is an independent, unofficial project. It is not affiliated with or
endorsed by Omarchy or its authors. MIT License.
