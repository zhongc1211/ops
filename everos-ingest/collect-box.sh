#!/bin/bash
# Box precheck for Orca automation「ops · EverOS 心月会话采集 box」.
# Writes /var/lib/everos-ingest/xinyue/$D/sessions-box.jsonl then exits 1
# so the model is never started.
set -euo pipefail
ROOT=/workspace/ops/everos-ingest
# also accept ops worktree copy
[ -x "$ROOT/collect_xinyue_sessions.py" ] || ROOT="$(cd "$(dirname "$0")" && pwd)"
export TZ=Asia/Singapore
D=${D:-$(date +%F)}
OUT=/var/lib/everos-ingest/xinyue/$D
mkdir -p "$OUT"
# keep sshd up for iMac push
"$ROOT/ensure-sshd.sh" || true
export MACHINE=box
python3 "$ROOT/collect_xinyue_sessions.py" --date "$D" --out "$OUT/sessions-box.jsonl"
# touch empty imac placeholder ONLY if missing and we want? No — absence is meaningful.
wc -l "$OUT/sessions-box.jsonl" | awk '{print "box lines="$1}'
exit 1
