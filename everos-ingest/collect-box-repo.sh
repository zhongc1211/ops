#!/bin/bash
# Box precheck for Orca automations「dv广告 · 26 EverOS 广告会话采集 box」and「vllm · 27 EverOS 会话采集 box」.
# Usage: collect-box-repo.sh deepvision-ads|vllm-omni
# Same as collect-box-deepvision-site.sh for another repo: collects the previous SGT day into
# /var/lib/everos-ingest/<repo>/$D/sessions-box.jsonl, then exits 1 so the model never starts.
# Exit 4 = collector error, 2 = bad argument. DRY_RUN=1 only prints the table (writes nothing).
set -euo pipefail
REPO=${1:-}
case "$REPO" in deepvision-ads|vllm-omni) ;; *) echo "usage: $0 deepvision-ads|vllm-omni" >&2; exit 2;; esac
ROOT="$(cd "$(dirname "$0")" && pwd)"
export TZ=Asia/Singapore
D=${D:-$(date -d yesterday +%F)}
export MACHINE=box
if [ "${DRY_RUN:-0}" = 1 ]; then
  python3 "$ROOT/collect_repo_sessions.py" --repo "$REPO" --date "$D" --dry-run
  exit 1
fi
OUT=/var/lib/everos-ingest/$REPO/$D
mkdir -p "$OUT"
"$ROOT/ensure-sshd.sh" || true   # keep sshd up for the iMac push
python3 "$ROOT/collect_repo_sessions.py" --repo "$REPO" --date "$D" --out "$OUT/sessions-box.jsonl"
wc -l "$OUT/sessions-box.jsonl" | awk '{print "box lines="$1}'
exit 1
