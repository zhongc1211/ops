#!/bin/bash
# Box precheck for Orca automation「ops · EverOS deepvision官网会话采集 box」(FDV-68, rules A+E+H+K).
# Collects the previous SGT day (runs 00:05 SGT) into
# /var/lib/everos-ingest/deepvision-site/$D/sessions-box.jsonl, then exits 1 so the model never starts.
# Exit 4 = collector error. DRY_RUN=1 only prints the table (writes nothing).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
export TZ=Asia/Singapore
D=${D:-$(date -d yesterday +%F)}
export MACHINE=box
if [ "${DRY_RUN:-0}" = 1 ]; then
  python3 "$ROOT/collect_deepvision_site_sessions.py" --date "$D" --dry-run
  exit 1
fi
OUT=/var/lib/everos-ingest/deepvision-site/$D
mkdir -p "$OUT"
"$ROOT/ensure-sshd.sh" || true   # keep sshd up for the iMac push
python3 "$ROOT/collect_deepvision_site_sessions.py" --date "$D" --out "$OUT/sessions-box.jsonl"
wc -l "$OUT/sessions-box.jsonl" | awk '{print "box lines="$1}'
exit 1
