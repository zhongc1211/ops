#!/bin/bash
# iMac precheck for Orca automation「ops · EverOS deepvision官网会话采集 iMac」(FDV-68, rules A+E+H+K).
# DRY_RUN=1 only prints the kept/excluded table (no staging, no push).
# Writes local jsonl + redacted transcripts, pushes transcripts to box first, then the jsonl.
# Push (FDV-68 01:20): each transcript is gzip'ed and split into 4 MB chunks; chunks go to
# box:$REMOTE/imac.resume/, which survives failed runs, and chunks already there with the right
# sha256 are skipped, so a dropped DERP link resumes instead of starting over. box then joins,
# checks both sha256s, gunzips into imac.incoming and swaps it into imac/; the list goes last.
# Exits 1 (no model) on success; any other failure exits non-1 so it shows in precheckResult
# (4 = time budget used up, rerun to resume).
# Catch-up (PER-67, 2026-10-20): box froze 10-19 17:54 to 10-20 10:22 and every push that night
# exited 2; nothing pushed those days later. Now a successful push writes the list's sha256 to
# $LOCAL/.pushed, and every run then checks the CATCHUP_DAYS (3) days before D: a day whose local
# list is missing on box, or has another sha256 there, is pushed again from the local copy (no
# re-collect) by this script with PUSH_ONLY=1 D=<day>. CATCHUP_ONLY=1 skips collecting and checks
# D itself too (for a low-frequency catch-up automation). 6 = catch-up incomplete, next run retries.
# EVEROS_LOCAL_BASE / EVEROS_REMOTE_BASE / EVEROS_BOX only exist for the E2E (catchup-e2e/).
set -euo pipefail
export TZ=Asia/Singapore
D=${D:-$(date -v-1d +%F)}   # previous SGT day; runs 00:01 SGT
ROOT="${EVEROS_INGEST_ROOT:-$HOME/.orca-state/bin/everos-ingest}"
[ -x "$ROOT/collect_deepvision_site_sessions.py" ] || ROOT="$(cd "$(dirname "$0")" && pwd)"
LBASE=${EVEROS_LOCAL_BASE:-$HOME/.orca-state/everos-ingest}/deepvision-site
RBASE=${EVEROS_REMOTE_BASE:-/var/lib/everos-ingest}/deepvision-site
BOX=${EVEROS_BOX:-box}
LOCAL=$LBASE/$D
REMOTE=$RBASE/$D
# prefer /usr/local/bin/orca
export ORCA_BIN=${ORCA_BIN:-/usr/local/bin/orca}
if [ "${DRY_RUN:-0}" = 1 ]; then
  MACHINE=imac python3 "$ROOT/collect_deepvision_site_sessions.py" --date "$D" --dry-run
  exit 1
fi
PUSH_ONLY=${PUSH_ONLY:-0}; CATCHUP_ONLY=${CATCHUP_ONLY:-0}
if [ "$PUSH_ONLY" = 1 ]; then
  [ -f "$LOCAL/sessions-imac.jsonl" ] || { echo "PUSH_ONLY: no local list $LOCAL/sessions-imac.jsonl" >&2; exit 2; }
elif [ "$CATCHUP_ONLY" != 1 ]; then
  mkdir -p "$LOCAL"
  export MACHINE=imac
  python3 "$ROOT/collect_deepvision_site_sessions.py" --date "$D" --out "$LOCAL/sessions-imac.jsonl" \
    --stage-dir "$LOCAL/imac" --remote-dir "$REMOTE/imac"
fi
# Tailscale to box often goes through a DERP relay; a single connect can time out.
# Open one multiplexed connection with retries, then every ssh/scp below reuses it.
# keep this short: macOS caps unix socket paths at 104 bytes and ssh appends a 17-byte temp suffix;
# "$HOME/.ssh/everos-ingest-dvsite-ctl-%C" was 105 on the iMac and every mux connect failed (FDV-68 2026-10-17)
CTL="$HOME/.ssh/evi-dvsite-%C"
SSH_OPTS=(-o ConnectTimeout=20 -o BatchMode=yes -o ControlMaster=auto -o "ControlPath=$CTL" -o ControlPersist=120)
connected=0
# up to ~5 minutes of retries (precheck timeout is 600s, Orca max); 2026-10-16 saw 10:16-10:18 outages
for attempt in 1 2 3 4 5 6 7 8; do
  if ssh "${SSH_OPTS[@]}" "$BOX" true; then connected=1; break; fi
  echo "ssh to box failed (attempt $attempt)" >&2
  sleep 20
done
[ "$connected" = 1 ] || { echo "cannot reach box over ssh; nothing pushed" >&2; exit 2; }
START=0   # bash SECONDS counts from script start, so the budget covers collect + connect + push
BUDGET=${PUSH_BUDGET:-540}   # seconds of the 600 s precheck limit; the rest is margin
CHUNK=${PUSH_CHUNK:-4m}
over_budget() { [ $((SECONDS - START)) -ge "$BUDGET" ]; }
# catch-up: push again, from the local copy, recent days whose list box does not have (same sha256).
# box's own sha256 decides; a day box already has only gets its .pushed marker (re)written.
catch_up() {   # $1 = first day before D to check (0 = D itself)
  local i day days="" want have rc
  for i in $(seq "$1" "${CATCHUP_DAYS:-3}"); do
    day=$(date -j -v-"${i}"d -f %F "$D" +%F)
    [ -f "$LBASE/$day/sessions-imac.jsonl" ] && days="$days $day"
  done
  [ -n "$days" ] || { echo "catch-up: no local lists in the last ${CATCHUP_DAYS:-3} days"; return 0; }
  have=$(ssh -n "${SSH_OPTS[@]}" "$BOX" "for d in $days; do f='$RBASE'/\$d/sessions-imac.jsonl; [ -f \"\$f\" ] && echo \"\$d \$(sha256sum < \"\$f\" | cut -d' ' -f1)\"; done; true") \
    || { echo "catch-up: cannot list box; left for the next run" >&2; return 1; }
  for day in $days; do
    want=$(shasum -a 256 < "$LBASE/$day/sessions-imac.jsonl" | cut -d' ' -f1)
    if echo "$have" | grep -qxF "$day $want"; then
      echo "$want" > "$LBASE/$day/.pushed"
      echo "catch-up $day: on box, sha ok"
      continue
    fi
    [ $((BUDGET - SECONDS)) -ge 60 ] || { echo "catch-up $day: time budget used up; left for the next run" >&2; return 1; }
    echo "catch-up $day: box $(echo "$have" | awk -v d="$day" '$1 == d {print "sha=" substr($2, 1, 12)}' | grep . || echo missing), local sha=${want:0:12}; pushing the local copy"
    rc=0
    PUSH_ONLY=1 CATCHUP_ONLY=0 D=$day PUSH_BUDGET=$((BUDGET - SECONDS)) bash "$0" || rc=$?
    [ "$rc" = 1 ] || { echo "catch-up $day: push exited $rc; left for the next run" >&2; return 1; }
    echo "catch-up $day: pushed"
  done
}
if [ "$CATCHUP_ONLY" = 1 ]; then
  rc=0; catch_up 0 || rc=6
  ssh -n "${SSH_OPTS[@]}" -O exit "$BOX" 2>/dev/null || true
  [ "$rc" = 0 ] || exit 6
  exit 1
fi
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
RES="$REMOTE/imac.resume"
# 1) local: gzip -n (no name/mtime, so the same transcript gives the same .gz) and split
PUSH="$LOCAL/push"
rm -rf "$PUSH"; mkdir -m 700 "$PUSH"
: > "$PUSH/MANIFEST"; : > "$PUSH/CHUNKS"
raw_total=0; gz_total=0
for f in "$LOCAL/imac/"*.jsonl; do
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
  retry3 ssh -n "${SSH_OPTS[@]}" "$BOX" "mkdir -p '$REMOTE' && mkdir -p -m 700 '$RES' && cd '$RES' && for d in */; do d=\${d%/}; [ -d \"\$d\" ] || continue; case ' $dirs ' in *\" \$d \"*) ;; *) rm -rf \"\$d\"; echo \"pruned stale \$d\" >&2;; esac; done; for d in $dirs; do mkdir -p -m 700 \"\$d\"; done; find . -type f -name 'part-*' -exec sha256sum {} + | sed 's#  \./# #' | awk '{print \$2\" \"\$1}'" > "$PUSH/REMOTE_CHUNKS"
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
      ssh -n "${SSH_OPTS[@]}" -O exit "$BOX" 2>/dev/null || true
      exit 4
    fi
    retry3 scp "${SSH_OPTS[@]}" -q "$PUSH/$rel" "$BOX:$RES/$rel" < /dev/null
    sent=$((sent + 1))
    echo "sent $rel ($((SECONDS - START))s)"
  done < "$PUSH/CHUNKS"
  echo "pass $pass: sent=$sent skipped(already on box, sha ok)=$skipped"
done
# 4) box: join, check gz sha, gunzip, check raw sha, 600; all good -> swap into imac/, clear resume dir
retry3 scp "${SSH_OPTS[@]}" -q "$PUSH/MANIFEST" "$BOX:$RES/MANIFEST"
ssh "${SSH_OPTS[@]}" "$BOX" "bash -s -- '$REMOTE'" <<'EOS' || { echo "assemble on box failed; chunks kept for the next run" >&2; exit 5; }
set -eu
REMOTE=$1; RES=$REMOTE/imac.resume; INC=$REMOTE/imac.incoming
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
rm -rf "$REMOTE/imac" && mv "$INC" "$REMOTE/imac" && rm -rf "$RES"
echo "box: swapped into imac/, resume dir cleared"
EOS
# 5) lists last, so the night review never sees paths that are not there yet
retry3 scp "${SSH_OPTS[@]}" -q "$LOCAL/sessions-imac.excluded.jsonl" "$BOX:$REMOTE/sessions-imac.excluded.jsonl"
retry3 scp "${SSH_OPTS[@]}" -q "$LOCAL/sessions-imac.jsonl" "$BOX:$REMOTE/sessions-imac.jsonl"
rm -rf "$PUSH"
shasum -a 256 < "$LOCAL/sessions-imac.jsonl" | cut -d' ' -f1 > "$LOCAL/.pushed"
n_tx=$(ls "$LOCAL/imac/"*.jsonl 2>/dev/null | wc -l | tr -d ' ')
wc -l "$LOCAL/sessions-imac.jsonl" | awk -v t="$n_tx" -v s="$((SECONDS - START))" '{print "imac lines="$1" transcripts="t" pushed in "s"s"}'
# the catch-up parent keeps the shared ssh connection open for its next day
[ "$PUSH_ONLY" = 1 ] && exit 1
rc=0; catch_up 1 || rc=6
ssh "${SSH_OPTS[@]}" -O exit "$BOX" 2>/dev/null || true
[ "$rc" = 0 ] || exit 6
exit 1
