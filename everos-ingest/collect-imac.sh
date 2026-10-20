#!/bin/bash
# iMac precheck for Orca automation「ops · EverOS 心月会话采集 iMac」.
# Writes local jsonl + redacted transcripts, pushes transcripts to box first, then the jsonl.
# Exits 1 (no model) on success; any other failure exits non-1 so it shows in precheckResult.
# Catch-up (PER-67, 2026-10-20): box froze 10-19 17:54 to 10-20 10:22 and every push that night
# exited 2; nothing pushed those days later. Now a successful push writes the list's sha256 to
# $LOCAL/.pushed, and every run then checks the CATCHUP_DAYS (3) days before D: a day whose local
# list is missing on box, or has another sha256 there, is pushed again from the local copy (no
# re-collect) by this script with PUSH_ONLY=1 D=<day>. CATCHUP_ONLY=1 skips collecting and checks
# D itself too (for a low-frequency catch-up automation). 6 = catch-up incomplete, next run retries.
# EVEROS_LOCAL_BASE / EVEROS_REMOTE_BASE / EVEROS_BOX only exist for the E2E (catchup-e2e/).
set -euo pipefail
export TZ=Asia/Singapore
D=${D:-$(date +%F)}
ROOT="${EVEROS_INGEST_ROOT:-$HOME/.orca-state/bin/everos-ingest}"
[ -x "$ROOT/collect_xinyue_sessions.py" ] || ROOT="$(cd "$(dirname "$0")" && pwd)"
LBASE=${EVEROS_LOCAL_BASE:-$HOME/.orca-state/everos-ingest}/xinyue
RBASE=${EVEROS_REMOTE_BASE:-/var/lib/everos-ingest}/xinyue
BOX=${EVEROS_BOX:-box}
LOCAL=$LBASE/$D
REMOTE=$RBASE/$D
PUSH_ONLY=${PUSH_ONLY:-0}; CATCHUP_ONLY=${CATCHUP_ONLY:-0}
if [ "$PUSH_ONLY" = 1 ]; then
  [ -f "$LOCAL/sessions-imac.jsonl" ] || { echo "PUSH_ONLY: no local list $LOCAL/sessions-imac.jsonl" >&2; exit 2; }
elif [ "$CATCHUP_ONLY" != 1 ]; then
  mkdir -p "$LOCAL"
  export MACHINE=imac
  # prefer /usr/local/bin/orca
  export ORCA_BIN=${ORCA_BIN:-/usr/local/bin/orca}
  python3 "$ROOT/collect_xinyue_sessions.py" --date "$D" --out "$LOCAL/sessions-imac.jsonl" \
    --stage-dir "$LOCAL/imac" --remote-dir "$REMOTE/imac"
fi
# Tailscale to box often goes through a DERP relay; a single connect can time out.
# Open one multiplexed connection with retries, then every ssh/scp below reuses it.
CTL="$HOME/.ssh/everos-ingest-ctl-%C"
SSH_OPTS=(-o ConnectTimeout=20 -o BatchMode=yes -o ControlMaster=auto -o "ControlPath=$CTL" -o ControlPersist=120)
connected=0
# up to ~5 minutes of retries (precheck timeout is 600s, Orca max); 2026-10-16 saw 10:16-10:18 outages
for attempt in 1 2 3 4 5 6 7 8; do
  if ssh "${SSH_OPTS[@]}" "$BOX" true; then connected=1; break; fi
  echo "ssh to box failed (attempt $attempt)" >&2
  sleep 20
done
[ "$connected" = 1 ] || { echo "cannot reach box over ssh; nothing pushed" >&2; exit 2; }
# catch-up: push again, from the local copy, recent days whose list box does not have (same sha256).
# box's own sha256 decides; a day box already has only gets its .pushed marker (re)written.
# xinyue pushes are not resumable, and in the E2E (2026-10-20) today's 49 MB alone took 6-11 min over DERP. So a day is
# only started if, at today's measured push rate (PUSH_RATE bytes/s; 100 KB/s, the E2E's measured
# 100-123 KB/s, when nothing was pushed yet), its transcripts should be on box by second CATCHUP_BUDGET
# (560 of the 600 s precheck timeout).
PUSH_RATE=${PUSH_RATE:-102400}
catch_up() {   # $1 = first day before D to check (0 = D itself)
  local i day days="" want have rc ts need
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
    need=$(( $(du -sk "$LBASE/$day" | cut -f1) * 1024 / PUSH_RATE + 30 ))
    [ $((SECONDS + need)) -lt "${CATCHUP_BUDGET:-560}" ] \
      || { echo "catch-up $day: needs ~${need}s at ${PUSH_RATE} B/s, only $(( ${CATCHUP_BUDGET:-560} - SECONDS ))s left; left for the next run" >&2; return 1; }
    echo "catch-up $day: box $(echo "$have" | awk -v d="$day" '$1 == d {print "sha=" substr($2, 1, 12)}' | grep . || echo missing), local sha=${want:0:12}; pushing the local copy"
    if echo "$have" | grep -q "^$day "; then
      # box has another list for this day: keep box's list, excluded list and transcripts as
      # <name>.replaced-<box time> before the push overwrites them (cp, not mv: a failed push leaves box's old copy)
      ts=$(ssh -n "${SSH_OPTS[@]}" "$BOX" "cd '$RBASE/$day' && ts=\$(date +%Y%m%d-%H%M%S) && for f in sessions-imac.jsonl sessions-imac.excluded.jsonl imac; do [ ! -e \"\$f\" ] || cp -a \"\$f\" \"\$f.replaced-\$ts\" || exit 1; done; echo \$ts") \
        || { echo "catch-up $day: cannot keep box's other copy; left for the next run" >&2; return 1; }
      echo "catch-up $day: box copy kept as *.replaced-$ts"
    fi
    rc=0
    PUSH_ONLY=1 CATCHUP_ONLY=0 D=$day bash "$0" || rc=$?
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
T_PUSH=$SECONDS
retry3 ssh "${SSH_OPTS[@]}" "$BOX" "mkdir -p '$REMOTE' && rm -rf '$REMOTE/imac.incoming' && mkdir -m 700 '$REMOTE/imac.incoming'"
if ls "$LOCAL/imac/"*.jsonl >/dev/null 2>&1; then
  retry3 scp "${SSH_OPTS[@]}" -q -p "$LOCAL/imac/"*.jsonl "$BOX:$REMOTE/imac.incoming/"
fi
retry3 ssh "${SSH_OPTS[@]}" "$BOX" "chmod 600 '$REMOTE/imac.incoming/'* 2>/dev/null; rm -rf '$REMOTE/imac' && mv '$REMOTE/imac.incoming' '$REMOTE/imac'"
# 2) manifest last, so the night review never sees paths that are not there yet
retry3 scp "${SSH_OPTS[@]}" -q "$LOCAL/sessions-imac.excluded.jsonl" "$BOX:$REMOTE/sessions-imac.excluded.jsonl"
retry3 scp "${SSH_OPTS[@]}" -q "$LOCAL/sessions-imac.jsonl" "$BOX:$REMOTE/sessions-imac.jsonl"
pushed_kb=$(du -sk "$LOCAL" | cut -f1)
[ "$pushed_kb" -lt 1024 ] || PUSH_RATE=$(( pushed_kb * 1024 / (SECONDS - T_PUSH + 1) ))
shasum -a 256 < "$LOCAL/sessions-imac.jsonl" | cut -d' ' -f1 > "$LOCAL/.pushed"
# no transcripts: ls fails, and with pipefail set -e used to end the script here (exit 1) before catch-up
n_tx=$({ ls "$LOCAL/imac/"*.jsonl 2>/dev/null || true; } | wc -l | tr -d ' ')
wc -l "$LOCAL/sessions-imac.jsonl" | awk -v t="$n_tx" '{print "imac lines="$1" transcripts="t" pushed"}'
# the catch-up parent keeps the shared ssh connection open for its next day
[ "$PUSH_ONLY" = 1 ] && exit 1
rc=0; catch_up 1 || rc=6
ssh "${SSH_OPTS[@]}" -O exit "$BOX" 2>/dev/null || true
[ "$rc" = 0 ] || exit 6
exit 1
