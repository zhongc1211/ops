#!/bin/bash
# night-review-gate.sh <role> <project> [...]: prechecks and the closing step of the night reviews moved from box to the MBA
# (PER-79, automations/migration-1020/README.md). project: xinyue | deepvision-site | deepvision-ads | vllm-omni.
# Who runs what (all prechecks are bounded, none starts a model by itself):
#   primary <p>         MBA night review precheck (also the MBA */10 retry task, which only acts until MBA time +25 min). exit 0 = start the review. Skips (exit 1) when the night is already
#                       done on box, MBA is on battery or would sleep with the lid closed (missed, reason=asleep), or
#                       heavy-lock is busy (missed, reason=lock_busy), or tonight's review already started here (< 3 h ago). Otherwise pulls the session lists
#                       (sync-manifests-from-box.sh; a failure is left in SYNC-STATUS for the review to alarm on),
#                       checks gh, starts a self-ending caffeinate and records state=started.
#   watch <p>           iMac watcher, MBA time +30 min, no model (always exit 1). Reads MBA's state over ssh; a missed
#                       night (offline / asleep / lock_busy / stalled / rsync_failed) gets a takeover file on the iMac.
#   backup <p>          iMac backup review precheck (*/10, acts from MBA time +30 to +240 min). exit 0 = the iMac runs the review: takeover file
#                       there (or the watcher's check says missed now), night not done on box, iMac heavy-lock taken.
#                       Lock busy for more than 60 min after the takeover -> one status=stuck to ops-system
#                       (machine=box): ops-system starts the disabled box task by hand.
#   box-watch <p>       box, MBA time +150 min, no model (always exit 1): night not done on box -> one status=stuck to
#                       ops-system (machine=box reason=imac_missed), unless the iMac reports its takeover started < 2 h ago. Covers the iMac
#                       being offline too.
#   finish <p> <D> <machine> <reason>   last step of the review (wrapped in notify-run --bot ops-system): needs
#                       「状态：完成」 in the summary, copies summary + ledger + logs back to box, records state=done,
#                       releases heavy-lock. exit 0 = all done; 3 = no 状态：完成; 4 = copy back failed (lock released).
#   reason <p> <D>      prints why this machine runs the night (ok on the MBA, the takeover reason on the iMac).
#   keepawake           MBA 21:40 task precheck: starts caffeinate -i -t 15000 (to 01:50) in the background, exit 1.
# Wakes go to ops-system only (~/.config/grokbot/webhooks/ops-system.env, read by path; never coding-assistant).
# State: ~/.orca-state/night-review/<p>/<D>.status (key=value lines, last one wins) and <D>.takeover on the iMac.
# Overrides (drills): NR_MBA_HOST (mba), NR_BOX_HOST (box), NR_BOX_DIR (box ~/xinyue-deploy/nightly-review; a local path when
# NR_BOX_HOST=local), NR_IMAC_HOST (imac), NR_DIR (~/xinyue-deploy/nightly-review), NR_NOW (epoch), NR_PMSET_BATT / NR_PMSET_G / NR_IOREG
# (files with pmset -g batt / pmset -g / ioreg output), NR_DISPLAYS (system_profiler SPDisplaysDataType output),
# NR_CAFFEINATE_T (seconds), NR_SYNC (sync script), NR_STATE (this machine's state root), NR_MBA_STATE / NR_IMAC_STATE
# (the state root read over ssh on the MBA / iMac; all three default to ~/.orca-state/night-review).
set -u
role=${1:-}; p=${2:-}
OPS=$(cd "$(dirname "$0")/.." && pwd); S=$OPS/scripts
case "$role" in keepawake) ;; primary|watch|backup|box-watch|finish|reason)
  case "$p" in xinyue|deepvision-site|deepvision-ads|vllm-omni) ;; *) echo "night-review-gate: unknown project '$p'" >&2; exit 2;; esac;;
  *) echo "usage: night-review-gate.sh primary|watch|backup|box-watch <project> | finish <project> <D> <machine> <reason> | reason <project> <D> | keepawake" >&2; exit 2;; esac
export PATH=/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH
now=${NR_NOW:-$(date +%s)}
# xinyue reviews the same day (23:40) -> 6 h back; the others review yesterday (00:30-01:20) -> 13 h back (late runs until 12:xx)
# MBA start time, minutes after 21:00 SGT (no midnight wrap): 23:40 / 00:30 / 00:55 / 01:20 (MIGRATION-BRIEF)
case "$p" in xinyue) at=160;; deepvision-site) at=210;; deepvision-ads) at=235;; *) at=260;; esac
mins=$(python3 -I -c 'import sys,datetime as d; t=d.datetime.fromtimestamp(int(sys.argv[1]),d.timezone(d.timedelta(hours=8))); print((t.hour*60+t.minute-1260)%1440)' "$now")
case "$p" in xinyue) back=6; files="-xinyue.md -xinyue-ledger.jsonl -addflush.json -addflush.out -skills";;
  *) back=13; files="-$p.md -$p-ledger.jsonl -$p-sessions.json -$p-sessions.out -$p-addflush.json -$p-addflush.out -$p-lessons.json -$p-readback.json";; esac
D=${NR_D:-$(REVIEW_NOW=$now bash "$S/review-date.sh" ago $back)}
case "$role" in finish|reason) D=${3:?night-review-gate: $role needs D};; esac
ST=${NR_STATE:-$HOME/.orca-state/night-review}/$p; mkdir -p "$ST"; SF=$ST/$D.status; TF=$ST/$D.takeover
NRD=${NR_DIR:-$HOME/xinyue-deploy/nightly-review}; BOXH=${NR_BOX_HOST:-box}; BOXD=${NR_BOX_DIR:-~/xinyue-deploy/nightly-review}
SSH="ssh -o BatchMode=yes -o ConnectTimeout=15"
# warm the relay path first: the first ssh over a cold DERP path can time out (sync-manifests-from-box.sh)
sshr(){ $SSH "$@"; local rc=$?; [ $rc -eq 255 ] && { sleep 5; $SSH "$@"; rc=$?; }; return $rc; }
summary=$D$(echo "$files" | cut -d' ' -f1)
put(){ echo "$* ts=$now" >> "$SF"; echo "night-review-gate $role $p $D: $*"; }
get(){ sed -nE "s/(^|.* )$1=([^ ]*).*/\2/p" "${2:-$SF}" 2>/dev/null | tail -1; }
done_line='^状态(：|:)[[:space:]]*完成'
box_done(){ if [ "$BOXH" = local ]; then grep -Eq "$done_line" "$BOXD/$summary" 2>/dev/null
  else sshr "$BOXH" "grep -Eq '$done_line' $BOXD/$summary" 2>/dev/null; fi; }
wake_stuck(){ # <machine> <reason> <note>: one status=stuck POST to ops-system; KEY goes to curl on stdin only
  local env=$HOME/.config/grokbot/webhooks/ops-system.env body
  body=$(python3 -I -c 'import json,sys; m,r,n,p,d=sys.argv[1:6]; print(json.dumps({"bot":"ops-system","task":"%s 夜审 %s"%(p,d),"status":"stuck","machine":m,"reason":r,"note":"machine=%s reason=%s %s"%(m,r,n),"source":"night-review-gate"},ensure_ascii=False))' "$1" "$2" "$3" "$p" "$D")
  [ -r "$env" ] || { echo "night-review-gate: no $env, not sent: $body" >&2; return 1; }
  ( set -a; . "$env"; set +a; printf 'Authorization: Bearer %s\n' "$KEY" | curl -fsS -m 30 -o /dev/null -w '%{http_code}' -X POST "$URL" -H @- -H 'Content-Type: application/json' -d "$body" ) \
    && echo " <- ops-system stuck machine=$1 reason=$2"; }
# MBA side of the night as seen from the iMac: prints ok | offline | asleep | lock_busy | stalled | rsync_failed | running
mba_state(){
  local s; s=$(sshr "${NR_MBA_HOST:-mba}" "cat ${NR_MBA_STATE:-~/.orca-state/night-review}/$p/$D.status" 2>/dev/null); local rc=$?
  [ $rc -eq 255 ] && { echo offline; return; }
  [ -n "$s" ] || { echo asleep; return; }                      # reachable but the precheck never ran tonight
  local st r ts; st=$(echo "$s" | tail -1 | sed -n 's/.*state=\([^ ]*\).*/\1/p'); r=$(echo "$s" | tail -1 | sed -n 's/.*reason=\([^ ]*\).*/\1/p')
  ts=$(echo "$s" | tail -1 | sed -n 's/.*ts=\([0-9]*\).*/\1/p')
  case "$st" in
    done) box_done && echo ok || echo rsync_failed;;
    missed) echo "${r:-asleep}";;
    started|checking) [ $(( now - ${ts:-0} )) -gt 3600 ] && echo stalled || echo running;;
    *) echo asleep;;
  esac; }

case "$role" in
primary)
  box_done && { put "state=skipped reason=already_done"; exit 1; }
  t=$(get ts); age=$(( now - ${t:-0} ))                      # a precheck killed by its 900 s timeout leaves 'checking'
  case "$(get state)" in started|done) [ $age -lt 10800 ];; checking) [ $age -lt 1200 ];; *) false;; esac \
    && { echo "night-review-gate primary $p $D: already $(get state) here, skip"; exit 1; }
  [ $mins -lt $at ] || [ $mins -gt $(( at + 25 )) ] && { echo "night-review-gate primary $p $D: outside MBA time .. +25 min, skip"; exit 1; }
  put "state=checking machine=mba"                          # so the iMac watcher can tell 'precheck running' from 'never ran'
  batt=$(cat "${NR_PMSET_BATT:-/dev/null}" 2>/dev/null); [ -n "${NR_PMSET_BATT:-}" ] || batt=$(pmset -g batt 2>/dev/null)
  pm=$(cat "${NR_PMSET_G:-/dev/null}" 2>/dev/null); [ -n "${NR_PMSET_G:-}" ] || pm=$(pmset -g 2>/dev/null)
  io=$(cat "${NR_IOREG:-/dev/null}" 2>/dev/null); [ -n "${NR_IOREG:-}" ] || io=$(ioreg -r -k AppleClamshellState -d 4 2>/dev/null)
  echo "$batt" | grep -q "'Battery Power'" && { put "state=missed machine=mba reason=asleep detail=on_battery"; exit 1; }
  if echo "$io" | grep -q '"AppleClamshellState" = Yes'; then
    # lid closed sleeps unless sleep is disabled or an external display is attached (2026-10-20: SleepDisabled 1 on the MBA)
    if ! echo "$pm" | grep -Eq '^ *SleepDisabled[[:space:]]+1' && \
       { dsp=$(cat "${NR_DISPLAYS:-/dev/null}" 2>/dev/null); [ -n "${NR_DISPLAYS:-}" ] || dsp=$(system_profiler SPDisplaysDataType 2>/dev/null)
         [ "$(echo "$dsp" | grep -c 'Connection Type: Internal')" = "$(echo "$dsp" | grep -c 'Resolution:')" ]; }; then
      put "state=missed machine=mba reason=asleep detail=lid_closed"; exit 1; fi
  fi
  # sync before the lock: it is network-bound, and a precheck killed by its timeout must not leave the lock held
  bash "${NR_SYNC:-$S/sync-manifests-from-box.sh}" "$p" "$D" mba || echo "night-review-gate: manifest sync failed, see ~/everos-ingest/$p/$D/SYNC-STATUS (the review alarms)"
  if ! out=$(bash "$S/heavy-lock.sh" acquire "night-review-$p"); then
    h=$(echo "$out" | sed -n 's/.*held by \([^ ]*\).*/\1/p')
    [ "$h" = "night-review-$p" ] && { echo "night-review-gate primary $p $D: our own lock (another trigger), skip"; exit 1; }
    put "state=missed machine=mba reason=lock_busy detail=$h"; exit 1
  fi
  echo "$out"
  gh_ok=yes; command -v gh >/dev/null && gh auth status >/dev/null 2>&1 || gh_ok=no
  nohup caffeinate -i -t "${NR_CAFFEINATE_T:-3600}" >/dev/null 2>&1 &   # ends by itself; the review adds caffeinate -w for its own pid
  put "state=started machine=mba reason=ok gh=$gh_ok caffeinate=$!"; exit 0;;
watch)
  box_done && { put "state=seen_done"; exit 1; }
  r=$(mba_state)
  case "$r" in ok) put "state=seen_done";; running) put "state=seen_running";;
    *) [ -f "$TF" ] || echo "reason=$r since=$now" > "$TF"; put "state=takeover reason=$r";; esac
  exit 1;;
backup)
  [ $mins -ge $(( at + 30 )) ] && [ $mins -le $(( at + 240 )) ] || exit 1   # before the watcher's time MBA may still be starting
  box_done && exit 1
  if [ ! -f "$TF" ]; then r=$(mba_state); case "$r" in ok|running) exit 1;; esac; echo "reason=$r since=$now" > "$TF"; fi
  [ "$(get state)" = started ] && exit 1                           # this machine already took the night
  r=$(get reason "$TF"); since=$(get since "$TF")
  [ -f "$ST/$D.synced" ] || { bash "${NR_SYNC:-$S/sync-manifests-from-box.sh}" "$p" "$D" imac && touch "$ST/$D.synced"; } \
    || echo "night-review-gate: manifest sync failed (the review alarms)"
  if out=$(bash "$S/heavy-lock.sh" acquire "night-review-$p"); then
    echo "$out"
    nohup caffeinate -i -t "${NR_CAFFEINATE_T:-3600}" >/dev/null 2>&1 &
    put "state=started machine=imac reason=$r"; exit 0
  fi
  if [ $(( now - ${since:-$now} )) -gt 3600 ] && [ -z "$(get escalated)" ]; then
    wake_stuck box lock_busy "MBA missed ($r), iMac heavy-lock busy > 60 min; run the disabled box task by hand (README §回滚)" && put "escalated=box reason=lock_busy"
  fi
  exit 1;;
box-watch)
  BOXH=local; BOXD=${NR_BOX_DIR:-$HOME/xinyue-deploy/nightly-review}
  box_done && exit 1
  [ -n "$(get escalated)" ] && exit 1
  s=$(sshr "${NR_IMAC_HOST:-imac}" "cat ${NR_IMAC_STATE:-~/.orca-state/night-review}/$p/$D.status" 2>/dev/null | grep 'state=started' | tail -1)
  t=$(echo "$s" | sed -n 's/.*ts=\([0-9]*\).*/\1/p')
  [ -n "$t" ] && [ $(( now - t )) -lt 7200 ] && { put "state=seen_imac_running"; exit 1; }
  wake_stuck box imac_missed "neither MBA nor iMac finished by +150 min; run the disabled box task by hand" && put "escalated=box reason=imac_missed"
  exit 1;;
finish)
  m=${4:?machine}; r=${5:?reason}
  grep -Eq "$done_line" "$NRD/$summary" 2>/dev/null || { put "state=failed machine=$m reason=$r detail=no_done_line"; bash "$S/heavy-lock.sh" release "night-review-$p"; exit 3; }
  set --; for f in $files; do [ -e "$NRD/$D$f" ] && set -- "$@" "$D$f"; done
  if [ "$BOXH" = local ]; then mkdir -p "$BOXD" && tar -C "$NRD" -cf - "$@" | tar -xf - -C "$BOXD"; rc=$?
  else tar -C "$NRD" -czf - "$@" | $SSH "$BOXH" "mkdir -p $BOXD && tar -xzf - -C $BOXD"; rc=$?; fi
  [ $rc -eq 0 ] && box_done || { put "state=failed machine=$m reason=$r detail=rsync_failed"; bash "$S/heavy-lock.sh" release "night-review-$p"; exit 4; }
  put "state=done machine=$m reason=$r files=$#"; bash "$S/heavy-lock.sh" release "night-review-$p"
  echo "machine=$m reason=$r: $p $D done, $# file(s) copied to box";;
reason)
  [ -f "$TF" ] && get reason "$TF" || echo ok;;
keepawake)
  nohup caffeinate -i -t "${NR_CAFFEINATE_T:-15000}" >/dev/null 2>&1 &
  echo "keepawake: caffeinate pid $! for ${NR_CAFFEINATE_T:-15000}s"; exit 1;;
esac
