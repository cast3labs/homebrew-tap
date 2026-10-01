#!/bin/bash
# Install the omac cask from this tap on a clean GitHub-hosted runner and check
# what a user gets: the release's own checksum, no quarantine left, Omac's own
# signature, an app that launches, a working `omac` command, and an uninstall
# that leaves nothing behind.
#
# Usage: ci/check-omac.sh [cask]        (default: cast3labs/tap/omac)
#
# Runs only on a throwaway runner: it installs, launches, kills and zaps Omac.
# It refuses to start unless GITHUB_ACTIONS=true or CI=true (exit 2).
# Every check prints "ok: ..." or "FAIL: ...". Exit 1 if any check failed.
set -uo pipefail

if [ "${GITHUB_ACTIONS:-}" != true ] && [ "${CI:-}" != true ]; then
  cat >&2 <<'EOF'
check-omac.sh: refusing to run: neither GITHUB_ACTIONS nor CI is "true".
It is meant for a throwaway CI runner. It stops any running Omac, deletes
~/.config/omac (your omac.toml) and ~/.local/state/omac, and uninstalls Omac
with --zap. Running it on your own Mac would lose your config and your
window manager.
EOF
  exit 2
fi

cask="${1:-cast3labs/tap/omac}"
root="$(cd "$(dirname "$0")/.." && pwd)"
app="$HOME/Applications/Omac.app"
prefix="$(brew --prefix)"
cli="$prefix/bin/omac"
sock="$HOME/.local/state/omac/omac.sock"
tmp="${RUNNER_TEMP:-/tmp}/check-omac"
mkdir -p "$tmp"
failed=0

ok() { printf 'ok: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; printf '::error::%s\n' "$*"; failed=1; }
group() { printf '::group::%s\n' "$*"; }
endgroup() { printf '::endgroup::\n'; }
# The base system has no coreutils `timeout`; SIGALRM ends the command (rc 142).
lim() { local s="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }

wait_until() {   # wait_until <seconds> <command...>: poll every half second
  local n=$(($1 * 2)); shift
  while [ "$n" -gt 0 ]; do
    "$@" && return 0
    sleep 0.5; n=$((n - 1))
  done
  "$@"
}
omac_running() { pgrep -x Omac >/dev/null; }
omac_gone() { ! pgrep -x Omac >/dev/null; }
socket_present() { [ -S "$sock" ]; }
# Print a path with the home folder as "~" (bash versions differ on ${x/#$HOME/~}).
tl() { case "$1" in "$HOME"*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

if [ "$(uname -m)" != arm64 ]; then
  echo "This check needs an Apple silicon runner (the cask is arm64 only)." >&2
  exit 2
fi

# ── The cask and the release it points at ────────────────────────────────────
group "The cask and its release"
info="$(brew info --cask --json=v2 "$cask")" || { echo "brew info failed for $cask" >&2; exit 1; }
version="$(printf '%s' "$info" | jq -r '.casks[0].version')"
sha="$(printf '%s' "$info" | jq -r '.casks[0].sha256')"
echo "cask $cask: version $version, sha256 $sha"
sumurl="https://github.com/cast3labs/omac/releases/download/v$version/Omac-arm64.zip.sha256"
published="$(curl -fsSL --retry 3 "$sumurl" | awk '{ print $1 }')"
if [ -n "$published" ] && [ "$published" = "$sha" ]; then
  ok "sha256 matches the release's Omac-arm64.zip.sha256"
else
  fail "sha256 $sha does not match the release's Omac-arm64.zip.sha256 (${published:-unreadable})"
fi
endgroup

group "Gatekeeper"
gk="$(spctl --status 2>&1)"
echo "spctl --status: $gk"
if [ "$gk" != "assessments enabled" ]; then
  sudo spctl --global-enable 2>&1 || sudo spctl --master-enable 2>&1
  echo "spctl --status now: $(spctl --status 2>&1)"
fi
endgroup

# ── Install, the way the README says ─────────────────────────────────────────
group "brew install --cask $cask"
pkill -x Omac 2>/dev/null
brew install --cask "$cask" 2>&1 | tee "$tmp/install.log"
rc=${PIPESTATUS[0]}
endgroup
if [ "$rc" != 0 ]; then
  fail "brew install --cask $cask exited $rc"
  exit 1
fi
ok "brew install --cask $cask"
if omac_running; then fail "the install launched Omac (it should only say how to start it)"; else ok "the install did not launch Omac"; fi

group "What was installed"
if [ -d "$app" ] && [ ! -L "$app" ]; then ok "the app is at ~/Applications/Omac.app"; else fail "no app at ~/Applications/Omac.app"; fi
[ -d /Applications/Omac.app ] && fail "a copy is in /Applications too"
installed="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>&1)"
if [ "$installed" = "$version" ]; then ok "the app is version $version"; else fail "the app is version $installed, the cask says $version"; fi
if [ -L "$cli" ] && [ -x "$cli" ]; then
  ok "omac is on PATH: $(readlink "$cli" | sed "s|^$prefix|\$(brew --prefix)|")"
else
  fail "no working omac link at $cli"
fi
endgroup

group "Notarization and signature"
# Since 1.4.8 the app is notarized and stapled: Gatekeeper accepts a quarantined
# copy on its own, so the cask leaves Homebrew's quarantine flag alone (the
# first open asks once; the user clicks Open). Assert the ticket, not the flag.
if spctl -a -vvv -t exec "$app" 2>&1 | grep -q 'source=Notarized Developer ID'; then
  ok "spctl: source=Notarized Developer ID"
else
  fail "spctl does not accept the app as notarized: $(spctl -a -vvv -t exec "$app" 2>&1 | tr '\n' ' ')"
fi
if xcrun stapler validate "$app" >/dev/null 2>&1; then ok "stapler validate: the ticket is stapled"; else fail "stapler validate failed"; fi
codesign -d -r- "$app" 2>/dev/null > "$tmp/dr.txt"
if diff "$tmp/dr.txt" "$root/ci/expected-dr.txt"; then
  ok "designated requirement matches ci/expected-dr.txt"
else
  fail "designated requirement differs from ci/expected-dr.txt"
fi
if codesign --verify --deep --strict "$app"; then ok "codesign --verify --deep --strict"; else fail "codesign --verify --deep --strict"; fi
# N13: nothing shipped in the tap may say Omac is not notarized any more.
if grep -niE 'not notarized|open anyway|unnotarized|could not verify|cannot verify' "$root/Casks/omac.rb" "$root/README.md"; then
  fail "a 'not notarized' phrase survives in the cask or the README"
else
  ok "no 'not notarized' phrase in the cask or the README"
fi
echo "spctl --assess: $(spctl --assess -vv --type execute "$app" 2>&1 | tr '\n' ' ')"
endgroup

# ── Launch it, as a user would, then use the command ─────────────────────────
group "Launch"
rm -rf "$HOME/.config/omac" "$HOME/.local/state/omac"
# Measured 2026-09-29 on 1.4.8 (run 36569288345, macOS 14/15/26): with the ticket
# stapled, Gatekeeper still shows its one-time "downloaded from the internet"
# confirmation on the first open of a quarantined copy, and a runner has no one
# to click Open, so `open` waits until it times out (142). A user clicks Open
# once; here the flag is cleared instead, only after the assertions above
# proved the copy notarized, so the launch measures Omac and not the dialog.
before="$(xattr -p com.apple.quarantine "$app" 2>/dev/null || echo none)"
echo "quarantine flag before the launch: $before (CI clears it; a user clicks Open once)"
xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
lim 60 open "$app"; rc=$?
if [ "$rc" = 0 ]; then ok "open ~/Applications/Omac.app"; else fail "open exited $rc (142: still waiting on Gatekeeper after 60 s)"; fi
wait_until 20 socket_present >/dev/null
pid="$(pgrep -x Omac | head -1)"
# A pid alone proves nothing: Gatekeeper keeps a blocked launch as a stopped
# process. Omac creates its CLI socket as soon as it runs.
if [ -n "$pid" ] && socket_present; then
  ok "Omac is running (pid $pid, $(ps -o stat=,etime= -p "$pid" | tr -s ' ')) with its socket"
else
  fail "Omac is not running after open (pid ${pid:-none}, socket $(socket_present && echo present || echo absent))"
fi
endgroup

group "The omac command"
out="$(lim 30 "$cli" version 2>&1)"; rc=$?
echo "omac version: $out"
if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q "$version"; then ok "omac version"; else fail "omac version exited $rc"; fi
out="$(lim 30 "$cli" spec-path 2>&1)"; rc=$?
echo "omac spec-path: $(printf '%s' "$out" | sed "s|$HOME|~|g")"
if [ "$rc" = 0 ]; then ok "omac spec-path"; else fail "omac spec-path exited $rc"; fi
# The install must not turn on launch at login: the caveats say how to.
if lim 60 sudo sfltool dumpbtm > "$tmp/btm.txt" 2>/dev/null && [ -s "$tmp/btm.txt" ]; then
  btm="$(grep -cE 'com\.(cast3labs|evanscastonguay)\.omac' "$tmp/btm.txt")"
  if [ "$btm" = 0 ]; then ok "no login item"; else fail "a login item exists ($btm lines in sfltool dumpbtm)"; fi
else
  fail "sfltool dumpbtm printed nothing; cannot tell whether a login item exists"
fi
endgroup

# ── Uninstall while Omac runs, then look for anything left ───────────────────
group "brew uninstall --cask --zap $cask"
brew uninstall --cask --zap "$cask" 2>&1 | tee "$tmp/uninstall.log"
rc=${PIPESTATUS[0]}
endgroup
if [ "$rc" = 0 ]; then ok "brew uninstall --cask --zap"; else fail "brew uninstall --cask --zap exited $rc"; fi
if grep -q "Signalling 'TERM'" "$tmp/uninstall.log"; then ok "the uninstall sent TERM"; else fail "the uninstall did not signal Omac"; fi
if grep -q "Quitting application" "$tmp/uninstall.log"; then fail "the uninstall quit Omac with an Apple Event"; fi
if wait_until 10 omac_gone; then ok "Omac stopped"; else fail "Omac still runs after the uninstall"; fi

left=""
for p in "$app" "$cli" "$prefix/Caskroom/omac" \
  "$HOME/.config/omac" "$HOME/.local/state/omac" \
  "$HOME/Library/Caches/com.cast3labs.omac" "$HOME/Library/Caches/com.evanscastonguay.omac" \
  "$HOME/Library/HTTPStorages/com.cast3labs.omac" "$HOME/Library/HTTPStorages/com.evanscastonguay.omac" \
  "$HOME/Library/Preferences/com.cast3labs.omac.plist" "$HOME/Library/Preferences/com.evanscastonguay.omac.plist"; do
  if [ -e "$p" ] || [ -L "$p" ]; then left="$left $(tl "$p")"; fi
done
if [ -z "$left" ]; then ok "nothing left behind"; else fail "left behind:$left"; fi

if [ "$failed" = 0 ]; then echo "All checks passed for $cask $version."; fi
exit "$failed"
