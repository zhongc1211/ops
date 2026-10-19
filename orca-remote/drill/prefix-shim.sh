#!/bin/bash
# prefix-shim.sh BASE_WATCHDOG > OUT: make the pre-fix watchdog.sh runnable in the drill container.
# Only hard-coded paths, URLs, the session name and two timing constants become env overrides with the SAME production
# defaults and the same names the fixed script uses. No logic line changes; run-drill.sh saves the diff as evidence.
# Fails if any substitution did not apply (so a changed base cannot silently run with production paths).
set -euo pipefail
src=$1; out=$(mktemp)
sed -e 's|^LOG=/workspace/ops/orca-remote/watchdog.log; R=/workspace/ops/orca-remote/orca-remote$|LOG=${WATCHDOG_LOG:-/workspace/ops/orca-remote/watchdog.log}; R=${ORCA_REMOTE_BIN:-/workspace/ops/orca-remote/orca-remote}|' \
    -e 's|^INT=45; GAP=$((INT\*3)); MINGAP=90;|INT=${WATCHDOG_INT:-45}; GAP=$((INT*3)); MINGAP=${WATCHDOG_MINGAP:-90};|' \
    -e 's|^PUB=https://orca-bot.deepvision.sg/; PBODY=/tmp/orca-remote-watchdog.public-body$|PUB=${WATCHDOG_PUBLIC_URL:-https://orca-bot.deepvision.sg/}; PBODY=${WATCHDOG_PBODY:-/tmp/orca-remote-watchdog.public-body}|' \
    -e 's|^CF_MATCH="cloudflared tunnel --config /home/box/.cloudflared/config.yml"$|CF_MATCH=${WATCHDOG_CF_MATCH:-"cloudflared tunnel --config /home/box/.cloudflared/config.yml"}|' \
    -e 's|pkill -f "cloudflared tunnel --config /home/box/.cloudflared/config.yml"|pkill -f "$CF_MATCH"|' \
    -e 's|http://127.0.0.1:6768/|${WATCHDOG_LOCAL_URL:-http://127.0.0.1:6768/}|g' \
    -e 's|-m 15 https://orca-bot.deepvision.sg/)"|-m 15 $PUB)"|' \
    -e 's|/proc/uptime|${WATCHDOG_UPTIME_FILE:-/proc/uptime}|g' \
    -e 's|exec 9>/tmp/orca-remote-watchdog.lock|exec 9>${WATCHDOG_LOCK:-/tmp/orca-remote-watchdog.lock}|' \
    -e 's|tmux has-session -t orca-remote|tmux has-session -t ${WATCHDOG_SESSION:-orca-remote}|' "$src" >"$out"
for want in WATCHDOG_LOG ORCA_REMOTE_BIN WATCHDOG_INT WATCHDOG_MINGAP WATCHDOG_PUBLIC_URL WATCHDOG_PBODY WATCHDOG_CF_MATCH \
            WATCHDOG_LOCAL_URL WATCHDOG_UPTIME_FILE WATCHDOG_LOCK WATCHDOG_SESSION 'pkill -f "$CF_MATCH"' '-m 15 $PUB)'; do
  grep -qF -- "$want" "$out" || { echo "prefix-shim: substitution for '$want' did not apply" >&2; exit 1; }
done
if grep -nE '/workspace/ops/orca-remote/watchdog.log;|127\.0\.0\.1:6768/\)|-m 15 https://' "$out" | grep -v -- ':-' >&2; then
  echo "prefix-shim: hard-coded production target left" >&2; exit 1; fi
cat "$out"; rm -f "$out"
