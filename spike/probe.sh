#!/bin/bash
# Spike F4 (throwaway, never merged): install one cask variant from a local tap
# on a GitHub-hosted runner and measure it. Every fact is printed as one line:
#
#   ROW|<macOS version>|<variant>|<key>|<value>
#
# Usage: spike/probe.sh v1|v2|v3|v4|adopt|quit|tilde
#   v1..v4  the four variants in spike/v1..v4
#   adopt   the curl one-liner first, then `brew install --adopt` with V4
#   quit    V4 plus `uninstall quit:` (spike/extra/v4-quit), uninstalled while Omac runs
#   tilde   V3 with a literal "~" in the step's args (spike/extra/v3-tilde)
set -u

variant="${1:?variant}"
root="$(cd "$(dirname "$0")/.." && pwd)"
tap="omacspike/local"
token="$tap/omac"
bid="com.evanscastonguay.omac"
os="$(sw_vers -productVersion)"
tmp="${RUNNER_TEMP:-/tmp}/f4"
mkdir -p "$tmp"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1

row() { printf 'ROW|%s|%s|%s|%s\n' "$os" "$variant" "$1" "$(printf '%s' "$2" | tr '\n|' ' /')"; }
group() { printf '::group::%s\n' "$*"; }
endgroup() { printf '::endgroup::\n'; }
# The base system has no coreutils `timeout`; SIGALRM ends the command (rc 142).
lim() { local s="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }

# Files in the bundle that carry com.apple.quarantine (symlinks not followed).
qcount() {
  [ -e "$1" ] || { echo "missing"; return; }
  local n=0 t=0 f
  while IFS= read -r -d '' f; do
    t=$((t + 1))
    xattr -s -p com.apple.quarantine "$f" >/dev/null 2>&1 && n=$((n + 1))
  done < <(find "$1" -print0)
  echo "$n of $t"
}

# Print a path with the home folder as "~" (bash versions differ on ${x/#$HOME/~}).
tl() { case "$1" in "$HOME"*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

wait_for_omac() {   # up to $1 seconds; prints the pid or nothing
  local i=0 pid=""
  while [ $i -lt $(($1 * 2)) ]; do
    pid=$(pgrep -x Omac | head -1) && { echo "$pid"; return 0; }
    sleep 0.5; i=$((i + 1))
  done
  return 1
}

case "$variant" in
  v1)    cask=v1;             app="/Applications/Omac.app" ;;
  v2|v3) cask=$variant;       app="$HOME/Applications/Omac.app" ;;
  v4)    cask=v4;             app="$HOME/Applications/Omac.app" ;;
  adopt) cask=v4;             app="$HOME/Applications/Omac.app" ;;
  quit)  cask=extra/v4-quit;  app="$HOME/Applications/Omac.app" ;;
  tilde) cask=extra/v3-tilde; app="$HOME/Applications/Omac.app" ;;
  *) echo "unknown variant $variant" >&2; exit 2 ;;
esac

# ── Homebrew, Gatekeeper, the local tap ─────────────────────────────────────
group "Homebrew and Gatekeeper"
row runner "$(uname -m) macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
row brew_preinstalled "$(brew --version | head -1)"
brew update 2>&1 | tail -3
row brew_version "$(brew --version | head -1)"
row console_user "$(who | awk '$2 == "console" { print $1 }' | tr '\n' ' ')"
gk="$(spctl --status 2>&1)"
row gatekeeper_before "$gk"
if [ "$gk" != "assessments enabled" ]; then
  sudo spctl --global-enable 2>&1 || sudo spctl --master-enable 2>&1
  row gatekeeper_after "$(spctl --status 2>&1)"
fi
endgroup

group "Local tap"
brew tap-new --no-git "$tap" >/dev/null
tapdir="$(brew --repository "$tap")"
mkdir -p "$tapdir/Casks"
cp "$root/spike/$cask/omac.rb" "$tapdir/Casks/omac.rb"
row cask_file "spike/$cask/omac.rb"
endgroup

# ── Style and audit ──────────────────────────────────────────────────────────
group "brew style"
brew style --cask "$token"; rc=$?
row style_rc "$rc"
endgroup
group "brew audit --cask --strict --online"
brew audit --cask --strict --online "$token"; rc=$?
row audit_rc "$rc"
endgroup
if [ "$variant" = v4 ]; then
  # Information for Phase 6 only: the official tap runs this signing audit.
  group "brew audit --cask --signing (information only)"
  brew audit --cask --signing "$token" 2>&1 | tee "$tmp/signing.log"; rc=${PIPESTATUS[0]}
  row audit_signing_rc "$rc"
  row audit_signing_msg "$(grep -iE 'error|gatekeeper|notar|signature' "$tmp/signing.log" | head -3)"
  endgroup
fi

# ── The curl one-liner first, for --adopt ────────────────────────────────────
if [ "$variant" = adopt ]; then
  group "curl one-liner (v1.4.7)"
  curl -fsSL https://raw.githubusercontent.com/evanscastonguay/omac/main/install.sh | bash -s -- v1.4.7
  row curl_install_rc "${PIPESTATUS[1]}"
  row curl_app_quarantined "$(qcount "$app")"
  row curl_cli_link "$(readlink "$HOME/.local/bin/omac" 2>/dev/null || echo none)"
  row curl_running_pid "$(pgrep -x Omac | head -1 || true)"
  endgroup
fi

# ── Install ──────────────────────────────────────────────────────────────────
group "brew install"
flags=""
[ "$variant" = adopt ] && flags="--adopt"
brew install --cask $flags "$token" 2>&1 | tee "$tmp/install.log"; rc=${PIPESTATUS[0]}
row install_rc "$rc"
row install_adopt_line "$(grep -E 'Adopting|different from' "$tmp/install.log" | head -2)"
row install_error "$(grep -E '^Error|xattr: ' "$tmp/install.log" | head -3)"
endgroup

if [ "$variant" = tilde ]; then
  row app_exists_after_failed_install "$([ -e "$app" ] && echo yes || echo no)"
  row caskroom_after_failed_install "$(ls "$(brew --prefix)/Caskroom" 2>/dev/null | tr '\n' ' ')"
  brew uninstall --cask --force "$token" >/dev/null 2>&1 || true
  exit 0
fi
[ "$rc" = 0 ] || { row verdict "install failed"; exit 0; }

# ── Quarantine, signature, launch, CLI ───────────────────────────────────────
group "Quarantine and signature"
case "$variant" in v4|adopt|quit) cli="$(brew --prefix)/bin/omac" ;; *) cli="$app/Contents/Helpers/omac" ;; esac
row app_path "$(tl "$app")"
row app_version "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>&1)"
row quarantined_files "$(qcount "$app")"
row xattr_r_p_lines "$(xattr -r -p com.apple.quarantine "$app" 2>/dev/null | wc -l | tr -d ' ')"
row top_quarantine_value "$(xattr -p com.apple.quarantine "$app" 2>/dev/null || echo none)"
codesign -d -r- "$app" 2>/dev/null > "$tmp/dr.txt"
diff "$tmp/dr.txt" "$root/ci/expected-dr.txt"; rc=$?
row dr_diff_rc "$rc"
row dr_diff_lines "$(diff "$tmp/dr.txt" "$root/ci/expected-dr.txt" | wc -l | tr -d ' ')"
codesign --verify --deep --strict "$app"; row codesign_verify_rc "$?"
row spctl_assess "$(spctl --assess -vv --type execute "$app" 2>&1 | tr '\n' ' ')"
if [ -L "$(brew --prefix)/bin/omac" ]; then
  row binary_link "$(readlink "$(brew --prefix)/bin/omac" | sed "s|$(brew --prefix)|HOMEBREW_PREFIX|")"
fi
endgroup

group "Launch and CLI"
pkill -x Omac 2>/dev/null; sleep 1
open "$app"; row open_rc "$?"
pid="$(wait_for_omac 15 || true)"
sleep 3
row pgrep_Omac "$(pgrep -x Omac | head -1 || true)"
[ -z "$(pgrep -x Omac)" ] && row syspolicyd_log "$(/usr/bin/log show --last 2m --style compact --predicate 'process == "syspolicyd"' 2>/dev/null | grep -iE 'omac' | tail -3)"
row cli_path "$(tl "$cli" | sed "s|^$(brew --prefix)|HOMEBREW_PREFIX|")"
out="$(lim 30 "$cli" spec-path 2>&1)"; rc=$?
row cli_spec_path_rc "$rc"
row cli_spec_path_out "$(printf '%s' "$out" | sed "s|$HOME|~|g")"
endgroup

# ── Uninstall and zap ────────────────────────────────────────────────────────
row zap_dirs_before "$(for d in "$HOME/.config/omac" "$HOME/.local/state/omac"; do [ -e "$d" ] && printf '%s ' "$(tl "$d")"; done)"
if [ "$variant" = quit ]; then
  group "uninstall quit: with Omac running"
  row tcc_user_appleevents_before "$(sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" "select client||'>'||indirect_object_identifier||'='||auth_value from access where service='kTCCServiceAppleEvents'" 2>&1 | tr '\n' ' ')"
  row running_before_uninstall "$(pgrep -x Omac | head -1 || echo none)"
  sudo /usr/bin/log stream --level debug --style compact --predicate 'subsystem == "com.apple.TCC"' > "$tmp/tcc.log" 2>&1 &
  sleep 3
  t0=$(date +%s)
  lim 300 brew uninstall --cask --zap "$token" 2>&1 | tee "$tmp/uninstall.log"; rc=${PIPESTATUS[0]}
  t1=$(date +%s)
  sleep 2
  sudo pkill -f "log stream --level debug" 2>/dev/null
  row uninstall_zap_rc "$rc"
  row uninstall_seconds "$((t1 - t0))"
  row uninstall_quit_lines "$(grep -iE 'quit|GUI|Automation' "$tmp/uninstall.log" | head -4)"
  row running_after_uninstall "$(pgrep -x Omac | head -1 || echo none)"
  row tcc_appleevents_log "$(grep -E 'kTCCServiceAppleEvents|AUTHREQ_RESULT|AUTHREQ_PROMPTING|PROMPT' "$tmp/tcc.log" | grep -viE 'systemevents' | head -8)"
  row tcc_log_lines "$(wc -l < "$tmp/tcc.log" | tr -d ' ')"
  endgroup

  # The raw Apple Event Homebrew sends, timed on its own: an error means
  # "denied", a long wait means a consent prompt nobody can answer.
  group "raw JXA quit, timed"
  brew install --cask "$token" >/dev/null 2>&1
  open "$app"; wait_for_omac 15 >/dev/null
  sleep 2
  t0=$(date +%s)
  out="$(lim 120 osascript -l JavaScript -e "Application('$bid').quit()" 2>&1)"; rc=$?
  t1=$(date +%s)
  row raw_quit_rc "$rc"
  row raw_quit_seconds "$((t1 - t0))"
  row raw_quit_out "$out"
  sleep 2
  row running_after_raw_quit "$(pgrep -x Omac | head -1 || echo none)"
  pkill -x Omac 2>/dev/null; sleep 1
  brew uninstall --cask --zap "$token" >/dev/null 2>&1; row cleanup_uninstall_rc "$?"
  endgroup
else
  group "brew uninstall --cask --zap"
  pkill -x Omac 2>/dev/null; sleep 1
  t0=$(date +%s)
  brew uninstall --cask --zap "$token" 2>&1 | tee "$tmp/uninstall.log"; rc=${PIPESTATUS[0]}
  t1=$(date +%s)
  row uninstall_zap_rc "$rc"
  row uninstall_seconds "$((t1 - t0))"
  endgroup
fi

left=""
for p in "$app" "$(brew --prefix)/bin/omac" "$HOME/.config/omac" "$HOME/.local/state/omac" "$(brew --prefix)/Caskroom/omac"; do
  { [ -e "$p" ] || [ -L "$p" ]; } && left="$left $(tl "$p")"
done
row left_behind "${left:-nothing}"
if [ "$variant" = adopt ]; then
  row curl_cli_link_after "$( [ -L "$HOME/.local/bin/omac" ] && echo "still there, dangling=$([ -e "$HOME/.local/bin/omac" ] && echo no || echo yes)" || echo gone)"
fi
exit 0
