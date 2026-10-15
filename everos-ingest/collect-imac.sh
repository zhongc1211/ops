#!/bin/bash
# iMac precheck for Orca automation「ops · EverOS 心月会话采集 iMac」.
# Writes local jsonl, scp to box, exits 1 (no model).
set -euo pipefail
export TZ=Asia/Singapore
D=${D:-$(date +%F)}
ROOT="${EVEROS_INGEST_ROOT:-$HOME/.orca-state/bin/everos-ingest}"
[ -x "$ROOT/collect_xinyue_sessions.py" ] || ROOT="$(cd "$(dirname "$0")" && pwd)"
LOCAL=$HOME/.orca-state/everos-ingest/xinyue/$D
mkdir -p "$LOCAL"
export MACHINE=imac
# prefer /usr/local/bin/orca
export ORCA_BIN=${ORCA_BIN:-/usr/local/bin/orca}
python3 "$ROOT/collect_xinyue_sessions.py" --date "$D" --out "$LOCAL/sessions-imac.jsonl"
# push to box over Tailscale SSH
ssh -o ConnectTimeout=15 -o BatchMode=yes box "mkdir -p /var/lib/everos-ingest/xinyue/$D"
scp -o ConnectTimeout=15 -o BatchMode=yes -q "$LOCAL/sessions-imac.jsonl" "box:/var/lib/everos-ingest/xinyue/$D/sessions-imac.jsonl"
wc -l "$LOCAL/sessions-imac.jsonl" | awk '{print "imac lines="$1" pushed"}'
exit 1
