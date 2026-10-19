#!/bin/bash
# MBA precheck for Orca automations「dv广告 · 26 EverOS 广告会话采集 MBA」and「vllm · 27 EverOS 会话采集 MBA」.
# Usage: collect-mba-repo.sh deepvision-ads|vllm-omni
# Copy of collect-mba-deepvision-site.sh (FDV-68, rules A+E+H+K) for another repo; only the repo,
# the collector (collect_repo_sessions.py --repo) and the ssh control socket name differ.
# DRY_RUN=1 only prints the kept/excluded table (no staging, no push).
# Writes local jsonl + redacted transcripts, pushes transcripts to box first, then the jsonl.
# Push (FDV-68 01:20): each transcript is gzip'ed and split into 4 MB chunks; chunks go to
# box:$REMOTE/mba.resume/, which survives failed runs, and chunks already there with the right
# sha256 are skipped, so a dropped DERP link resumes instead of starting over. box then joins,
# checks both sha256s, gunzips into mba.incoming and swaps it into mba/; the list goes last.
# Exits 1 (no model) on success; any other failure exits non-1 so it shows in precheckResult
# (4 = time budget used up, rerun to resume).
set -euo pipefail
REPO=${1:-}
case "$REPO" in
  deepvision-ads) CTL_TAG=ads;;
  vllm-omni) CTL_TAG=vllm;;
  *) echo "usage: $0 deepvision-ads|vllm-omni" >&2; exit 2;;
esac
export TZ=Asia/Singapore
D=${D:-$(date -v-1d +%F)}   # previous SGT day; runs 00:01 SGT
ROOT="${EVEROS_INGEST_ROOT:-$HOME/.orca-state/bin/everos-ingest}"
[ -f "$ROOT/collect_repo_sessions.py" ] || ROOT="$(cd "$(dirname "$0")" && pwd)"
LOCAL=$HOME/.orca-state/everos-ingest/$REPO/$D
REMOTE=/var/lib/everos-ingest/$REPO/$D
# prefer /usr/local/bin/orca
export ORCA_BIN=${ORCA_BIN:-/usr/local/bin/orca}
if [ "${DRY_RUN:-0}" = 1 ]; then
  MACHINE=mba python3 "$ROOT/collect_repo_sessions.py" --repo "$REPO" --date "$D" --dry-run
  exit 1
fi
mkdir -p "$LOCAL"
export MACHINE=mba
python3 "$ROOT/collect_repo_sessions.py" --repo "$REPO" --date "$D" --out "$LOCAL/sessions-mba.jsonl" \
  --stage-dir "$LOCAL/mba" --remote-dir "$REMOTE/mba"
# Tailscale to box often goes through a DERP relay; a single connect can time out.
# Open one multiplexed connection with retries, then every ssh/scp below reuses it.
# keep this short: macOS caps unix socket paths at 104 bytes and ssh appends a 17-byte temp suffix;
# "$HOME/.ssh/everos-ingest-dvsite-ctl-%C" was 105 on the MBA and every mux connect failed (FDV-68 2026-10-17)
CTL="$HOME/.ssh/evi-$CTL_TAG-%C"
SSH_OPTS=(-o ConnectTimeout=20 -o BatchMode=yes -o ControlMaster=auto -o "ControlPath=$CTL" -o ControlPersist=120)
connected=0
# up to ~5 minutes of retries (precheck timeout is 600s, Orca max); 2026-10-16 saw 10:16-10:18 outages
for attempt in 1 2 3 4 5 6 7 8; do
  if ssh "${SSH_OPTS[@]}" box true; then connected=1; break; fi
  echo "ssh to box failed (attempt $attempt)" >&2
  sleep 20
done
[ "$connected" = 1 ] || { echo "cannot reach box over ssh; nothing pushed" >&2; exit 2; }
START=0   # bash SECONDS counts from script start, so the budget covers collect + connect + push
BUDGET=${PUSH_BUDGET:-540}   # seconds of the 600 s precheck limit; the rest is margin
CHUNK=${PUSH_CHUNK:-4m}
over_budget() { [ $((SECONDS - START)) -ge "$BUDGET" ]; }
# retry a push step 3 times, 20s apart; exit 3 if all fail (exit 1 means success here)
retry3() {
  local i
  for i in 1 2 3; do
    "$@" && return 0
    echo "push step failed (attempt $i/3): $1" >&2
    [ "$i" -lt 3 ] && sleep "${RETRY_SLEEP:-20}"
  done
  echo "push step failed 3 times; giving up (chunks already on box are kept for the next run)" >&2
  exit 3
}
RES="$REMOTE/mba.resume"
# 1) local: gzip -n (no name/mtime, so the same transcript gives the same .gz) and split
PUSH="$LOCAL/push"
rm -rf "$PUSH"; mkdir -m 700 "$PUSH"
: > "$PUSH/MANIFEST"; : > "$PUSH/CHUNKS"
raw_total=0; gz_total=0
for f in "$LOCAL/mba/"*.jsonl; do
  [ -e "$f" ] || continue
  sid=$(basename "$f" .jsonl)
  raw=$(shasum -a 256 "$f" | cut -d' ' -f1)
  gzip -n -c "$f" > "$PUSH/$sid.jsonl.gz"
  gz=$(shasum -a 256 "$PUSH/$sid.jsonl.gz" | cut -d' ' -f1)
  dir="$sid.${gz:0:16}"
  mkdir "$PUSH/$dir"
  split -b "$CHUNK" -a 3 "$PUSH/$sid.jsonl.gz" "$PUSH/$dir/part-"
  n=$(ls "$PUSH/$dir" | wc -l | tr -d ' ')
  rs=$(stat -f %z "$f"); gs=$(stat -f %z "$PUSH/$sid.jsonl.gz")
  raw_total=$((raw_total + rs)); gz_total=$((gz_total + gs))
  echo "$sid $raw $gz $dir $n" >> "$PUSH/MANIFEST"
  for c in "$PUSH/$dir"/part-*; do
    echo "$dir/$(basename "$c") $(shasum -a 256 "$c" | cut -d' ' -f1)" >> "$PUSH/CHUNKS"
  done
  echo "staged $sid raw=$rs gz=$gs chunks=$n raw_sha=${raw:0:12} gz_sha=${gz:0:12}"
  rm "$PUSH/$sid.jsonl.gz"
done
echo "staged total raw=$raw_total gz=$gz_total chunks=$(wc -l < "$PUSH/CHUNKS" | tr -d ' ') in $((SECONDS - START))s"
# 2)+3) list what box has (sha256 per chunk; stale chunk dirs dropped), upload what is missing or
# wrong, then list again. scp can exit 0 over a stalled DERP link without the data landing
# (2026-10-17 01:36), so only box's own sha256 listing counts as "on box".
dirs=$(awk '{print $4}' "$PUSH/MANIFEST" | tr '\n' ' ')
total=$(wc -l < "$PUSH/CHUNKS" | tr -d ' ')
pass=0
while :; do
  pass=$((pass + 1))
  retry3 ssh -n "${SSH_OPTS[@]}" box "mkdir -p '$REMOTE' && mkdir -p -m 700 '$RES' && cd '$RES' && for d in */; do d=\${d%/}; [ -d \"\$d\" ] || continue; case ' $dirs ' in *\" \$d \"*) ;; *) rm -rf \"\$d\"; echo \"pruned stale \$d\" >&2;; esac; done; for d in $dirs; do mkdir -p -m 700 \"\$d\"; done; find . -type f -name 'part-*' -exec sha256sum {} + | sed 's#  \./# #' | awk '{print \$2\" \"\$1}'" > "$PUSH/REMOTE_CHUNKS"
  ok=$(grep -cxFf "$PUSH/REMOTE_CHUNKS" "$PUSH/CHUNKS" || true)
  echo "verify pass $pass: box has $ok of $total chunks with the right sha256"
  [ "$ok" -eq "$total" ] && break
  [ "$pass" -ge 4 ] && { echo "chunks still missing after $pass passes; kept for the next run" >&2; exit 3; }
  # upload missing or wrong chunks, one by one, stopping cleanly when the time budget is used up
  sent=0; skipped=0
  while read -r rel sha; do
    if grep -qxF "$rel $sha" "$PUSH/REMOTE_CHUNKS"; then skipped=$((skipped + 1)); echo "skip $rel (already on box, sha ok)"; continue; fi
    if over_budget; then
      echo "time budget ${BUDGET}s used up: sent=$sent skipped=$skipped, rest left for the next run" >&2
      ssh -n "${SSH_OPTS[@]}" -O exit box 2>/dev/null || true
      exit 4
    fi
    retry3 scp "${SSH_OPTS[@]}" -q "$PUSH/$rel" "box:$RES/$rel" < /dev/null
    sent=$((sent + 1))
    echo "sent $rel ($((SECONDS - START))s)"
  done < "$PUSH/CHUNKS"
  echo "pass $pass: sent=$sent skipped(already on box, sha ok)=$skipped"
done
# 4) box: join, check gz sha, gunzip, check raw sha, 600; all good -> swap into mba/, clear resume dir
retry3 scp "${SSH_OPTS[@]}" -q "$PUSH/MANIFEST" "box:$RES/MANIFEST"
ssh "${SSH_OPTS[@]}" box "bash -s -- '$REMOTE'" <<'EOS' || { echo "assemble on box failed; chunks kept for the next run" >&2; exit 5; }
set -eu
REMOTE=$1; RES=$REMOTE/mba.resume; INC=$REMOTE/mba.incoming
rm -rf "$INC"; mkdir -m 700 "$INC"
while read -r sid raw gz dir n; do
  have=$(ls "$RES/$dir" | wc -l)
  [ "$have" -eq "$n" ] || { echo "box: $sid has $have of $n chunks" >&2; exit 5; }
  cat "$RES/$dir"/part-* > "$INC/$sid.jsonl.gz"
  g=$(sha256sum < "$INC/$sid.jsonl.gz" | cut -d' ' -f1)
  [ "$g" = "$gz" ] || { echo "box: $sid gz sha mismatch" >&2; rm -rf "$RES/$dir"; exit 5; }
  gunzip -c "$INC/$sid.jsonl.gz" > "$INC/$sid.jsonl"; rm "$INC/$sid.jsonl.gz"
  r=$(sha256sum < "$INC/$sid.jsonl" | cut -d' ' -f1)
  [ "$r" = "$raw" ] || { echo "box: $sid raw sha mismatch" >&2; exit 5; }
  chmod 600 "$INC/$sid.jsonl"
  echo "box: $sid ok gz_sha=${g:0:12} raw_sha=${r:0:12}"
done < "$RES/MANIFEST"
rm -rf "$REMOTE/mba" && mv "$INC" "$REMOTE/mba" && rm -rf "$RES"
echo "box: swapped into mba/, resume dir cleared"
EOS
# 5) lists last, so the night review never sees paths that are not there yet
retry3 scp "${SSH_OPTS[@]}" -q "$LOCAL/sessions-mba.excluded.jsonl" "box:$REMOTE/sessions-mba.excluded.jsonl"
retry3 scp "${SSH_OPTS[@]}" -q "$LOCAL/sessions-mba.jsonl" "box:$REMOTE/sessions-mba.jsonl"
rm -rf "$PUSH"
n_tx=$(ls "$LOCAL/mba/"*.jsonl 2>/dev/null | wc -l | tr -d ' ')
wc -l "$LOCAL/sessions-mba.jsonl" | awk -v t="$n_tx" -v s="$((SECONDS - START))" '{print "mba lines="$1" transcripts="t" pushed in "s"s"}'
ssh "${SSH_OPTS[@]}" -O exit box 2>/dev/null || true
exit 1
