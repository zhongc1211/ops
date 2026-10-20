#!/bin/bash
# Runs e2e-catchup.sh for the four MBA targets, new and old, and checks the real dirs are untouched (F15).
# Usage: run-all.sh OUT [OLD_REV] [seq|par]    (OUT must not exist yet; run on the MBA)
# seq (default): one target after another, like the real schedule (21:50 / 00:01 / 00:02 / 00:16).
# par: the four targets at once (four pushes share the link; today's push can use the whole budget).
# new and old of one target always run one after the other: they share the ssh control socket.
# Writes OUT/{run-info.txt,results.tsv,real-dirs-*.txt}.
set -uo pipefail
OUT=$1 OLD_REV=${2:-origin/main} ORDER=${3:-seq}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir "$OUT" || exit 2
snap() {
  { echo "## MBA ~/.orca-state/everos-ingest"
    (cd "$HOME/.orca-state/everos-ingest" && find . -exec stat -f '%m %z %N' {} + | sort -k3)
    echo "## box /var/lib/everos-ingest"
    ssh -o BatchMode=yes box "cd /var/lib/everos-ingest && find . -printf '%T@ %s %p\n' | sort -k3"
  } > "$OUT/real-dirs-$1.txt" 2>&1
}
{ echo "host: $(hostname) $(uname -mrs) $(sw_vers -productVersion 2>/dev/null)"
  echo "bash: $BASH_VERSION; $(ssh -V 2>&1)"
  echo "commit (new): $(git -C "$HERE" rev-parse HEAD)"
  echo "old: $(git -C "$HERE" rev-parse "$OLD_REV") ($OLD_REV)"
  echo "order: $ORDER"
  echo "start: $(date '+%F %T %Z')"; } > "$OUT/run-info.txt"
snap before
for t in xinyue deepvision-site deepvision-ads vllm-omni; do
  ( "$HERE/e2e-catchup.sh" "$OUT" "$t" new
    "$HERE/e2e-catchup.sh" "$OUT" "$t" old "$OLD_REV" ) > "$OUT/$t.out" 2>&1 &
  [ "$ORDER" = par ] || wait
done
wait
snap after
cat "$OUT"/*-new/results.tsv "$OUT"/*-old/results.tsv > "$OUT/results.tsv"
if diff "$OUT/real-dirs-before.txt" "$OUT/real-dirs-after.txt" > "$OUT/real-dirs.diff"; then
  printf 'all\t-\tPASS\treal dirs unchanged (F15)\t\n' >> "$OUT/results.tsv"
else
  printf 'all\t-\tFAIL\treal dirs unchanged (F15)\tsee real-dirs.diff\n' >> "$OUT/results.tsv"
fi
# box side: list what the E2E left under /tmp, then remove it (it holds real, redacted transcripts)
ssh -o BatchMode=yes box "cd /tmp/everos-catchup-e2e/$(basename "$OUT") && find . -type f -printf '%T@ %s %p\n' | sort -k3; cd / && rm -rf /tmp/everos-catchup-e2e/$(basename "$OUT")" > "$OUT/box-tmp-final.txt" 2>&1
echo "end: $(date '+%F %T %Z')" >> "$OUT/run-info.txt"
awk -F'\t' '{n[$2" "$3]++} END {for (k in n) print k, n[k]}' "$OUT/results.tsv" | sort
