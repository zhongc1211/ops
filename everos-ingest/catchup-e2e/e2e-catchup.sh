#!/bin/bash
# E2E for the push catch-up (PER-67, 2026-10-20); the checks are the ones in FAILURE-MODES.md.
# Usage: e2e-catchup.sh OUT xinyue|deepvision-site|deepvision-ads|vllm-omni new|old [OLD_REV]
# Runs the real MBA precheck script (real collector on this Mac's sessions, real ssh to box) with
# the local base in OUT and the box base under /tmp/everos-catchup-e2e/ (never ~/.orca-state/everos-ingest
# or /var/lib/everos-ingest). "new" = the script in this worktree; "old" = the script at OLD_REV
# (default origin/main) with only its two base paths and the ssh host replaced (old-patch.diff).
# Writes OUT/<target>-<mode>/{run*.log,results.tsv}; one results line per check.
set -uo pipefail
OUT=$1 TARGET=$2 MODE=$3 OLD_REV=${4:-origin/main}
HERE=$(cd "$(dirname "$0")" && pwd); ING=$(dirname "$HERE")
D0=${E2E_D0:-2026-10-18}   # first push fails (box unreachable)
D1=${E2E_D1:-2026-10-19}   # next day's run; must catch D0 up
DM2=$(date -j -v-2d -f %F "$D1" +%F)   # local dir without a list (collector died)
DM4=$(date -j -v-4d -f %F "$D1" +%F)   # local list older than CATCHUP_DAYS=3
case "$TARGET" in
  xinyue) S=collect-mba.sh; ARGS=();;
  deepvision-site) S=collect-mba-deepvision-site.sh; ARGS=();;
  deepvision-ads|vllm-omni) S=collect-mba-repo.sh; ARGS=("$TARGET");;
  *) echo "usage: $0 OUT xinyue|deepvision-site|deepvision-ads|vllm-omni new|old [OLD_REV]" >&2; exit 2;;
esac
W=$OUT/$TARGET-$MODE
LB=$W/local
RB=/tmp/everos-catchup-e2e/$(basename "$OUT")/$TARGET-$MODE
L=$LB/$TARGET; R=$RB/$TARGET
rm -rf "$W"; mkdir -p "$LB"
if [ "$MODE" = old ]; then
  git -C "$ING" show "$OLD_REV:everos-ingest/$S" > "$W/orig.sh"
  sed -e 's#^LOCAL=$HOME/.orca-state/everos-ingest/#LOCAL=$EVEROS_LOCAL_BASE/#' \
      -e 's#^REMOTE=/var/lib/everos-ingest/#REMOTE=$EVEROS_REMOTE_BASE/#' \
      -e 's# box true;# "${EVEROS_BOX:-box}" true;#' -e 's#-O exit box#-O exit "${EVEROS_BOX:-box}"#' \
      -e 's#"${SSH_OPTS\[@\]}" box "#"${SSH_OPTS[@]}" "${EVEROS_BOX:-box}" "#' -e 's#"box:\$#"${EVEROS_BOX:-box}:$#' \
      "$W/orig.sh" > "$W/script.sh"
  diff "$W/orig.sh" "$W/script.sh" > "$W/old-patch.diff"
  echo "old = $(git -C "$ING" rev-parse "$OLD_REV"):everos-ingest/$S" > "$W/script.txt"
  SCRIPT=$W/script.sh
else
  SCRIPT=$ING/$S
  echo "new = $(git -C "$ING" rev-parse HEAD) $SCRIPT (worktree clean: $(git -C "$ING" status --porcelain -- "$S" | wc -l | tr -d ' ') changes)" > "$W/script.txt"
fi
export EVEROS_INGEST_ROOT=$ING EVEROS_LOCAL_BASE=$LB EVEROS_REMOTE_BASE=$RB
ssh -o BatchMode=yes box "rm -rf '$RB' && mkdir -p '$RB'"

: > "$W/results.tsv"
check() {   # check NAME CONDITION-RESULT(0/1) DETAIL
  local r=FAIL; [ "$2" = 0 ] && r=PASS
  printf '%s\t%s\t%s\t%s\t%s\n' "$TARGET" "$MODE" "$r" "$1" "$3" | tee -a "$W/results.tsv"
}
run() {   # run N VAR=VALUE...  -> sets RC, log in run$N.log
  local n=$1; shift
  echo "== run $n: $* ($(date '+%F %T'))" > "$W/run$n.log"
  env "$@" bash "$SCRIPT" ${ARGS[@]+"${ARGS[@]}"} >> "$W/run$n.log" 2>&1
  RC=$?
  echo "== exit $RC ($(date '+%F %T'))" >> "$W/run$n.log"
}
lsha() { [ -f "$L/$1/sessions-mba.jsonl" ] && shasum -a 256 < "$L/$1/sessions-mba.jsonl" | cut -d' ' -f1; }
# content of the day's collected files (list, excluded list, transcripts); .pushed and push/ left out
ltree() { (cd "$L/$1" 2>/dev/null && find . -type f ! -name .pushed ! -path './push/*' | sort | xargs shasum -a 256 | shasum -a 256 | cut -c1-16); }
marker() { cat "$L/$1/.pushed" 2>/dev/null; }
rsha() { ssh -o BatchMode=yes box "sha256sum < '$R/$1/sessions-mba.jsonl' 2>/dev/null | cut -d' ' -f1"; }
rmtime() { ssh -o BatchMode=yes box "stat -c %Y '$R/$1/sessions-mba.jsonl' 2>/dev/null"; }
eq() { [ -n "$1" ] && [ "$1" = "$2" ]; echo $?; }
has() { grep -qF "$2" "$W/run$1.log"; echo $?; }
hasnt() { grep -qF "$2" "$W/run$1.log" && echo 1 || echo 0; }

# run 1: D0, box unreachable (F1, F13)
run 1 D="$D0" EVEROS_BOX=box-e2e-unreachable.invalid
check "run1 exit 2 (box unreachable)" "$(eq "$RC" 2)" "exit=$RC"
check "run1 local D0 list collected" "$([ -n "$(lsha "$D0")" ]; echo $?)" "sha=$(lsha "$D0" | cut -c1-12)"
check "run1 no .pushed for D0 (F1)" "$([ -z "$(marker "$D0")" ]; echo $?)" "marker=$(marker "$D0")"
check "run1 no catch-up attempted (F13)" "$(hasnt 1 'catch-up')" ""
T0=$(ltree "$D0")
# F7 / F8 fixtures: D1-2 has a dir but no list; D1-4 has a full copy of D0 (older than 3 days)
mkdir -p "$L/$DM2"
cp -Rp "$L/$D0" "$L/$DM4"; rm -f "$L/$DM4/.pushed"

# run 2: D1, box reachable -> D1 pushed, D0 caught up from the local copy (F2, F3, F7, F8, F9)
run 2 D="$D1"
check "run2 exit 1" "$(eq "$RC" 1)" "exit=$RC"
check "run2 box D1 list = local" "$(eq "$(rsha "$D1")" "$(lsha "$D1")")" "box=$(rsha "$D1" | cut -c1-12) local=$(lsha "$D1" | cut -c1-12)"
check "run2 box D0 list = local (F3)" "$(eq "$(rsha "$D0")" "$(lsha "$D0")")" "box=$(rsha "$D0" | cut -c1-12) local=$(lsha "$D0" | cut -c1-12)"
check "run2 .pushed D0 = local sha" "$(eq "$(marker "$D0")" "$(lsha "$D0")")" "marker=$(marker "$D0" | cut -c1-12)"
check "run2 .pushed D1 = local sha" "$(eq "$(marker "$D1")" "$(lsha "$D1")")" "marker=$(marker "$D1" | cut -c1-12)"
check "run2 D0 local files unchanged, not re-collected (F2)" "$(eq "$(ltree "$D0")" "$T0")" "before=$T0 after=$(ltree "$D0")"
check "run2 D0 pushed exactly once (F9)" "$([ "$(grep -c "catch-up $D0: pushed" "$W/run2.log")" = 1 ]; echo $?)" "count=$(grep -c "catch-up $D0: pushed" "$W/run2.log")"
check "run2 dir without list ($DM2) skipped (F7)" "$(hasnt 2 "catch-up $DM2")" ""
check "run2 day older than 3 days ($DM4) not pushed (F8)" "$([ -z "$(rsha "$DM4")" ] && [ "$(hasnt 2 "catch-up $DM4")" = 0 ]; echo $?)" "box=$(rsha "$DM4" | cut -c1-12)"
M0=$(rmtime "$D0")
sleep 2

# run 3: D1 again -> D0 already on box, not pushed again (F4)
run 3 D="$D1"
check "run3 exit 1" "$(eq "$RC" 1)" "exit=$RC"
check "run3 D0 not pushed again (F4)" "$(hasnt 3 "catch-up $D0: pushed")" ""
check "run3 box D0 mtime unchanged (F4)" "$(eq "$(rmtime "$D0")" "$M0")" "before=$M0 after=$(rmtime "$D0")"
check "run3 box D0 still = local" "$(eq "$(rsha "$D0")" "$(lsha "$D0")")" ""

if [ "$MODE" = old ]; then
  check "old: D0 never reached box (regression)" "$([ -z "$(rsha "$D0")" ]; echo $?)" "box=$(rsha "$D0" | cut -c1-12)"
  exit 0
fi
check "run3 log says D0 on box, sha ok" "$(has 3 "catch-up $D0: on box, sha ok")" ""

# run 4: box loses the D0 list while the local marker stays -> pushed again (F5)
ssh -o BatchMode=yes box "rm -f '$R/$D0/sessions-mba.jsonl'"
run 4 D="$D1"
check "run4 exit 1" "$(eq "$RC" 1)" "exit=$RC"
check "run4 D0 pushed again after box lost it (F5)" "$(has 4 "catch-up $D0: pushed")" ""
check "run4 box D0 list = local (F5)" "$(eq "$(rsha "$D0")" "$(lsha "$D0")")" ""

# run 5: CATCHUP_ONLY=1; local D0 marker gone (box has it), box D1 list gone (F6, F14)
rm -f "$L/$D0/.pushed"
ssh -o BatchMode=yes box "rm -f '$R/$D1/sessions-mba.jsonl'"
T1=$(ltree "$D1"); M0=$(rmtime "$D0")
run 5 D="$D1" CATCHUP_ONLY=1
check "run5 exit 1" "$(eq "$RC" 1)" "exit=$RC"
check "run5 D0 marker rewritten without pushing (F6)" "$(eq "$(marker "$D0")" "$(lsha "$D0")")" "marker=$(marker "$D0" | cut -c1-12)"
check "run5 D0 not pushed (F6)" "$([ "$(has 5 "catch-up $D0: pushed")" = 1 ] && [ "$(rmtime "$D0")" = "$M0" ]; echo $?)" "mtime before=$M0 after=$(rmtime "$D0")"
check "run5 CATCHUP_ONLY pushed D itself (F14)" "$(eq "$(rsha "$D1")" "$(lsha "$D1")")" "box=$(rsha "$D1" | cut -c1-12)"
check "run5 CATCHUP_ONLY did not collect (F14)" "$(eq "$(ltree "$D1")" "$T1")" "before=$T1 after=$(ltree "$D1")"
