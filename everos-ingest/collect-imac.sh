#!/bin/bash
# iMac precheck for Orca automation「ops · EverOS 心月会话采集 iMac」.
# Writes local jsonl + redacted transcripts, pushes transcripts to box first, then the jsonl.
# Exits 1 (no model) on success; any other failure exits non-1 so it shows in precheckResult.
set -euo pipefail
export TZ=Asia/Singapore
D=${D:-$(date +%F)}
ROOT="${EVEROS_INGEST_ROOT:-$HOME/.orca-state/bin/everos-ingest}"
[ -x "$ROOT/collect_xinyue_sessions.py" ] || ROOT="$(cd "$(dirname "$0")" && pwd)"
LOCAL=$HOME/.orca-state/everos-ingest/xinyue/$D
REMOTE=/var/lib/everos-ingest/xinyue/$D
mkdir -p "$LOCAL"
export MACHINE=imac
# prefer /usr/local/bin/orca
export ORCA_BIN=${ORCA_BIN:-/usr/local/bin/orca}
python3 "$ROOT/collect_xinyue_sessions.py" --date "$D" --out "$LOCAL/sessions-imac.jsonl" \
  --stage-dir "$LOCAL/imac" --remote-dir "$REMOTE/imac"
# Tailscale to box often goes through a DERP relay; a single connect can time out.
# Open one multiplexed connection with retries, then every ssh/scp below reuses it.
CTL="$HOME/.ssh/everos-ingest-ctl-%C"
SSH_OPTS=(-o ConnectTimeout=20 -o BatchMode=yes -o ControlMaster=auto -o "ControlPath=$CTL" -o ControlPersist=120)
connected=0
# up to ~5 minutes of retries (precheck timeout is 600s, Orca max); 2026-10-16 saw 10:16-10:18 outages
for attempt in 1 2 3 4 5 6 7 8; do
  if ssh "${SSH_OPTS[@]}" box true; then connected=1; break; fi
  echo "ssh to box failed (attempt $attempt)" >&2
  sleep 20
done
[ "$connected" = 1 ] || { echo "cannot reach box over ssh; nothing pushed" >&2; exit 2; }
# retry a push step 3 times, 60s apart; exit 3 if all fail (exit 1 means success here)
retry3() {
  local i
  for i in 1 2 3; do
    "$@" && return 0
    echo "push step failed (attempt $i/3): $1" >&2
    [ "$i" -lt 3 ] && sleep "${RETRY_SLEEP:-60}"
  done
  echo "push step failed 3 times; giving up" >&2
  exit 3
}
# 1) transcripts: upload to a temp dir, then swap in (no stale or half-copied files on box)
retry3 ssh "${SSH_OPTS[@]}" box "mkdir -p '$REMOTE' && rm -rf '$REMOTE/imac.incoming' && mkdir -m 700 '$REMOTE/imac.incoming'"
if ls "$LOCAL/imac/"*.jsonl >/dev/null 2>&1; then
  retry3 scp "${SSH_OPTS[@]}" -q -p "$LOCAL/imac/"*.jsonl "box:$REMOTE/imac.incoming/"
fi
retry3 ssh "${SSH_OPTS[@]}" box "chmod 600 '$REMOTE/imac.incoming/'* 2>/dev/null; rm -rf '$REMOTE/imac' && mv '$REMOTE/imac.incoming' '$REMOTE/imac'"
# 2) manifest last, so the night review never sees paths that are not there yet
retry3 scp "${SSH_OPTS[@]}" -q "$LOCAL/sessions-imac.excluded.jsonl" "box:$REMOTE/sessions-imac.excluded.jsonl"
retry3 scp "${SSH_OPTS[@]}" -q "$LOCAL/sessions-imac.jsonl" "box:$REMOTE/sessions-imac.jsonl"
n_tx=$(ls "$LOCAL/imac/"*.jsonl 2>/dev/null | wc -l | tr -d ' ')
wc -l "$LOCAL/sessions-imac.jsonl" | awk -v t="$n_tx" '{print "imac lines="$1" transcripts="t" pushed"}'
ssh "${SSH_OPTS[@]}" -O exit box 2>/dev/null || true
exit 1
