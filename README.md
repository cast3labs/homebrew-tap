# evanscastonguay/homebrew-tap

Homebrew casks for [Omac](https://github.com/evanscastonguay/omac), a tiling
window manager for macOS that works with Omarchy's keybindings: one app, nothing
else to install. Apple silicon, macOS 14 or later.

## Install

```bash
brew install --cask evanscastonguay/tap/omac
```

Use the full name. Homebrew 7 trusts a tap's cask when you name it this way;
`brew tap` followed by `brew install --cask omac` is refused.

The cask puts `Omac.app` in `~/Applications` and `omac` on your `PATH`. It does
not start Omac. Start it, then allow it in System Settings > Privacy & Security
> Accessibility:

```bash
open ~/Applications/Omac.app
omac status
```

`omac status` should show `accessibility` and `tap` both `true`. To start Omac
when you log in, run `omac login on`.

Omac is signed with its Developer ID and, since 1.4.8, notarized by Apple, so
Gatekeeper opens it and the cask leaves Homebrew's quarantine flag alone. The
first time you open it, macOS asks once whether to open an app downloaded from
the internet — click **Open**.

## Update

```bash
brew upgrade --cask evanscastonguay/tap/omac
omac quit; while pgrep -x -U "$USER" Omac >/dev/null; do sleep 0.2; done; open ~/Applications/Omac.app
```

The old version keeps running until you restart it: the second line quits it,
waits until it has exited, and opens the new one.

Every way to install, update, uninstall and switch (curl, this tap, the download), side by side:
[the install matrix](https://github.com/evanscastonguay/omac#every-way-side-by-side).

Homebrew replaces the app but neither stops the running copy nor starts the
new one, so restart Omac yourself.

## Uninstall

```bash
omac login off
brew uninstall --cask --zap evanscastonguay/tap/omac
```

Homebrew's uninstall cannot reach the running app to turn launch at login off
for you, so the first line does it while Omac still runs; if it does not print
"launch at login: off", remove Omac in System Settings > General > Login Items.
`--zap` also removes `~/.config/omac` (your `omac.toml`), `~/.local/state/omac`,
`~/.local/share/omac` (the theme media Omac downloaded), and Omac's preferences
and caches in `~/Library`; leave it out to keep them. If you used a theme, run
`omac theme off` first: it puts your own wallpaper back.

## Coming from the curl installer

The one-line installer also uses `~/Applications/Omac.app`. To hand that copy
to Homebrew, upgrade it to the version this cask ships, then:

```bash
brew install --cask --adopt evanscastonguay/tap/omac
```

`--adopt` refuses a copy of a different version. Afterwards, remove the
installer's link: `rm ~/.local/bin/omac`.

## What CI checks

On every pull request and every push to `main`, on GitHub-hosted macOS 26,
macOS 15 and macOS 14 runners with the latest Homebrew
(`.github/workflows/tests.yml`; Homebrew warns that macOS 14 is unsupported,
but the cask installs and every check below runs there too):

- `brew style` and `brew audit --cask --strict --online` pass, and `brew
  livecheck` finds the latest release;
- the cask's `sha256` equals the release's own `Omac-arm64.zip.sha256`;
- after `brew install`, Gatekeeper accepts the app as notarized
  (`source=Notarized Developer ID`, the ticket stapled), and its
  signature satisfies `ci/expected-dr.txt`, the designated requirement macOS ties
  the Accessibility permission to;
- the install does not start Omac or turn on launch at login; `open` starts it,
  and `omac version` and `omac spec-path` answer;
- `brew uninstall --cask --zap` stops Omac without an Automation prompt and
  leaves nothing behind (`ci/check-omac.sh`).

These are pre-merge checks: `brew install` itself does not compare the
signature against `ci/expected-dr.txt`. `ci/check-omac.sh` refuses to run
unless `GITHUB_ACTIONS` or `CI` is `true`: it stops Omac and deletes
`~/.config/omac`, so never run it on your own Mac.

Once a day, `.github/workflows/livecheck.yml` opens an issue if the cask has
fallen behind the latest Omac release.

Omac is an independent, unofficial project. It is not affiliated with or
endorsed by Omarchy, its creators, 37signals LLC or the Omacom Foundation.
Omarchy and the Omarchy trademark belong to 37signals LLC and the creators of Omarchy.
From 1.4.8, Omac is free to use under its licence terms, [EULA.fr.md](https://github.com/evanscastonguay/omac/blob/main/EULA.fr.md) (français) / [EULA.md](https://github.com/evanscastonguay/omac/blob/main/EULA.md); versions 1.4.5–1.4.7 stay MIT.
