#!/bin/bash
# Spike F4 (throwaway, never merged): install one cask variant from a local tap
# on a GitHub-hosted runner and measure it. Every fact is printed as one line:
#
#   ROW|<macOS version>|<variant>|<key>|<value>
#
# Usage: spike/probe.sh v1|v2|v3|v4|adopt|quit|tilde|preflight
#   v1..v4  the four variants in spike/v1..v4
#   adopt   the curl one-liner first, then `brew install --adopt` with V4
#   quit    V4 plus `uninstall quit:` (spike/extra/v4-quit), uninstalled while Omac runs
#   tilde   V3 with a literal "~" in the step's args (spike/extra/v3-tilde)
#   preflight  V4 plus `omac login off` as an uninstall step and `uninstall signal:`
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
  preflight) cask=extra/v4-preflight; app="$HOME/Applications/Omac.app" ;;
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

# ── Homebrew 7 tap trust: a short name before the tap is trusted ─────────────
if [ "$variant" = v4 ]; then
  group "brew install --cask omac (short name, tap not yet trusted)"
  lim 300 brew install --cask omac 2>&1 | tee "$tmp/short.log"; rc=${PIPESTATUS[0]}
  row short_name_install_rc "$rc"
  row short_name_install_msg "$(grep -iE 'trust|error|no cask' "$tmp/short.log" | head -3)"
  if [ "$rc" = 0 ]; then pkill -x Omac 2>/dev/null; brew uninstall --cask omac >/dev/null 2>&1; fi
  row trust_file "$(cat "$HOME/.homebrew/trust.json" 2>/dev/null || ls "${HOMEBREW_USER_CONFIG_HOME:-$HOME/.config/homebrew}" 2>&1 | head -3)"
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
case "$variant" in v4|adopt|quit|preflight) cli="$(brew --prefix)/bin/omac" ;; *) cli="$app/Contents/Helpers/omac" ;; esac
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
# 142 = still waiting after 60 s (SIGALRM): `open` blocks on a Gatekeeper dialog.
t0=$(date +%s); lim 60 open "$app"; rc=$?; t1=$(date +%s)
row open_rc "$rc"
row open_seconds "$((t1 - t0))"
pid="$(wait_for_omac 15 || true)"
sleep 3
row pgrep_Omac "$(pgrep -x Omac | head -1 || true)"
if [ -z "$(pgrep -x Omac)" ]; then
  # Best effort: the text of the Gatekeeper dialog, if UI scripting is allowed here.
  row gatekeeper_dialog "$(lim 20 osascript -e 'tell application "System Events" to tell process "CoreServicesUIAgent" to get value of every static text of every window' 2>&1 | head -c 400)"
fi
[ -z "$(pgrep -x Omac)" ] && row syspolicyd_log "$(lim 90 /usr/bin/log show --last 3m --style compact --predicate 'process == "syspolicyd"' 2>/dev/null | grep -iE 'omac' | tail -3)"
row cli_path "$(tl "$cli" | sed "s|^$(brew --prefix)|HOMEBREW_PREFIX|")"
out="$(lim 30 "$cli" spec-path 2>&1)"; rc=$?
row cli_spec_path_rc "$rc"
row cli_spec_path_out "$(printf '%s' "$out" | sed "s|$HOME|~|g")"
endgroup

# ── Uninstall and zap ────────────────────────────────────────────────────────
row zap_dirs_before "$(for d in "$HOME/.config/omac" "$HOME/.local/state/omac"; do [ -e "$d" ] && printf '%s ' "$(tl "$d")"; done)"
if [ "$variant" = quit ]; then
  tccdb() {   # $1 = user|system
    local db="$HOME/Library/Application Support/com.apple.TCC/TCC.db" pre=""
    [ "$1" = system ] && { db="/Library/Application Support/com.apple.TCC/TCC.db"; pre="sudo"; }
    $pre sqlite3 "$db" "select client||'>'||ifnull(indirect_object_identifier,'')||'='||auth_value||'/'||auth_reason from access where service='kTCCServiceAppleEvents'" 2>&1 | tr '\n' ' '
  }
  tcc_start() { sudo /usr/bin/log stream --level debug --style compact --predicate 'subsystem == "com.apple.TCC"' > "$tmp/tcc-$1.log" 2>&1 & sleep 3; }
  tcc_stop() {
    sleep 2; sudo pkill -f "log stream --level debug" 2>/dev/null; sleep 1
    echo "--- TCC AppleEvents lines ($1) ---"
    grep -E 'AppleEvents|AUTHREQ_RESULT|PROMPT' "$tmp/tcc-$1.log" | cut -c1-420 | head -40
    row "tcc_prompting_lines_$1" "$(grep -cE 'AUTHREQ_PROMPTING|promptWithUser|Prompting' "$tmp/tcc-$1.log")"
    row "tcc_appleevents_results_$1" "$(grep -A1 -E 'service=kTCCServiceAppleEvents' "$tmp/tcc-$1.log" | grep -oE 'authValue=[0-9]+, authReason=[0-9]+' | sort | uniq -c | tr '\n' ' ')"
  }
  # brew's quit (via `uninstall quit:`), then the same Apple Event sent raw.
  quit_round() {   # $1 = label
    local label="$1" t0 t1 rc out
    [ -d "$app" ] || brew install --cask "$token" >/dev/null 2>&1
    pgrep -x Omac >/dev/null || { lim 60 open "$app"; wait_for_omac 15 >/dev/null; sleep 2; }
    row "running_before_brew_quit_$label" "$(pgrep -x Omac | head -1 || echo none)"
    tcc_start "brew-$label"
    t0=$(date +%s)
    lim 300 brew uninstall --cask --zap "$token" 2>&1 | tee "$tmp/uninstall-$label.log"; rc=${PIPESTATUS[0]}
    t1=$(date +%s)
    tcc_stop "brew-$label"
    row "brew_uninstall_rc_$label" "$rc"
    row "brew_uninstall_seconds_$label" "$((t1 - t0))"
    row "brew_quit_lines_$label" "$(grep -iE 'quit|GUI|Automation' "$tmp/uninstall-$label.log" | head -4)"
    sleep 1
    row "running_after_brew_quit_$label" "$(pgrep -x Omac | head -1 || echo none)"

    # The raw Apple Event, timed: an error means "denied", a long wait means a
    # consent prompt that nobody can answer on a runner.
    pkill -x Omac 2>/dev/null; sleep 1
    brew install --cask "$token" >/dev/null 2>&1
    lim 60 open "$app"; wait_for_omac 15 >/dev/null; sleep 2
    tcc_start "raw-$label"
    t0=$(date +%s)
    out="$(lim 120 osascript -l JavaScript -e "Application('$bid').quit()" 2>&1)"; rc=$?
    t1=$(date +%s)
    tcc_stop "raw-$label"
    row "raw_quit_rc_$label" "$rc"
    row "raw_quit_seconds_$label" "$((t1 - t0))"
    row "raw_quit_out_$label" "$out"
    sleep 1
    row "running_after_raw_quit_$label" "$(pgrep -x Omac | head -1 || echo none)"
  }

  group "uninstall quit: with the runner's own TCC grants"
  row tcc_user_appleevents "$(tccdb user)"
  row tcc_system_appleevents "$(tccdb system)"
  quit_round runner
  endgroup

  # A user's Mac has none of the runner's pre-granted Automation entries.
  # Clear them, and ask again.
  group "uninstall quit: after tccutil reset AppleEvents"
  tccutil reset AppleEvents; row tccutil_reset_rc "$?"
  row tcc_user_appleevents_after_reset "$(tccdb user)"
  row tcc_system_appleevents_after_reset "$(tccdb system)"
  quit_round reset
  endgroup

  pkill -x Omac 2>/dev/null; sleep 1
  brew uninstall --cask --zap "$token" >/dev/null 2>&1; row cleanup_uninstall_rc "$?"
elif [ "$variant" = preflight ]; then
  group "uninstall_preflight_steps (omac login off) and uninstall signal:, Omac running"
  pgrep -x Omac >/dev/null || { lim 60 open "$app"; wait_for_omac 15 >/dev/null; sleep 3; }
  row login_on_outside_brew "$(lim 30 "$cli" login on 2>&1)"
  row login_query_outside_brew "$(lim 30 "$cli" login 2>&1)"
  row running_before_uninstall "$(pgrep -x Omac | head -1 || echo none)"
  t0=$(date +%s)
  lim 300 brew uninstall --cask --zap "$token" 2>&1 | tee "$tmp/uninstall.log"; rc=${PIPESTATUS[0]}
  t1=$(date +%s)
  row uninstall_zap_rc "$rc"
  row uninstall_seconds "$((t1 - t0))"
  row login_off_step_output "$(grep -iE 'launch at login|omac:|error|refused|socket|not running|Operation' "$tmp/uninstall.log" | head -4)"
  row signal_lines "$(grep -iE 'signal|TERM' "$tmp/uninstall.log" | head -3)"
  sleep 1
  row running_after_uninstall "$(pgrep -x Omac | head -1 || echo none)"
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
