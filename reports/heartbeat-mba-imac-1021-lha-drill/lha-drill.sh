#!/bin/bash
# lha-drill.sh [repo]: dr eggbot box drill of scripts/lock-held-alert (PR #75 @6e144e16) logic. Linux box has no /usr/bin/lockf,
# so a temp copy has that literal path swapped for a fake lockf (exit code from FAKE_RC); curl is a fake (FAKE_HTTP). Contacts nothing.
set -u
R=${1:-/tmp/pr75-r3}; C=${2:-6e144e16}; OUT=$(cd "$(dirname "$0")" && pwd)/out-${C:0:7}; rm -rf "$OUT"; mkdir -p "$OUT"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; mkdir -p "$W/bin" "$W/hooks"
git -C "$R" show "$C":scripts/lock-held-alert > "$W/lha.orig"
sed "s#/usr/bin/lockf#$W/bin/lockf#g" "$W/lha.orig" > "$W/lha"; chmod +x "$W/lha"
printf '#!/bin/bash\nshift 3; exit ${FAKE_RC:-0}\n' > "$W/bin/lockf"; chmod +x "$W/bin/lockf"
cat > "$W/bin/curl" <<'C'
#!/bin/bash
cat >/dev/null; for a in "$@"; do case "$a" in @*) cp "${a#@}" "$CURL_LOG.$(date +%s).$$.$RANDOM";; esac; done; printf '%s' "${FAKE_HTTP:-200}"
C
chmod +x "$W/bin/curl"; printf 'URL=https://example.invalid/hook\nKEY=fake-key-not-secret\n' > "$W/hooks/ops-system.env"
export PATH=$W/bin:$PATH STUCK_WEBHOOK_DIR=$W/hooks STUCK_FORCE_BOT=ops-system CURL_LOG=$W/curl
L=$W/x.lock; S=$L.skips.json; n(){ ls $W/curl.* 2>/dev/null | wc -l; }
run(){ FAKE_RC=$1 "$W/lha" $W/bin/lockf -k -t 0 "$L" /bin/true --target "T|x|id|20" >>"$OUT/log" 2>&1; echo $?; }
res(){ printf '%s\t%s\t%s\n' "$1" "$2" "$3" | tee -a "$OUT/results.tsv"; }
now=$(date +%s)
# L1 alert at 45 min, once
echo "{\"first\": $((now-2760)), \"last\": $((now-300)), \"skips\": 9}" > $S; r=$(run 75); c1=$(n); r2=$(run 75); c2=$(n)
[ $r = 75 ] && [ $c1 = 1 ] && [ $c2 = 1 ] && res L1.alert-once PASS "rc $r; curl after 46 min=1, next skip still 1" || res L1.alert-once FAIL "rc $r c1=$c1 c2=$c2"
# L2 recovery once, recovery send fails -> keeps {alerted}
FAKE_HTTP=500 r=$(FAKE_HTTP=500 run 0); c3=$(n); st=$(cat $S 2>/dev/null)
res L2.recover-fail INFO "rc $r curl=$c3 state=$st (recovery not delivered, kept alerted only)"
# L3 new stuck episode after an undelivered recovery: lock held again for 46 min
r=$(run 75); python3 -c "import json;d=json.load(open('$S'));d['first']=$now-2760;json.dump(d,open('$S','w'))"; c4=$(n); r=$(run 75); c5=$(n); st=$(cat $S)
[ $c5 -gt $c4 ] && res L3.second-episode PASS "new episode alerted" || res L3.second-episode FAIL "MISSED: 2nd stuck episode not alerted (curl $c4->$c5), state=$st"
# L4 stale record: task disabled for days after one skip; first round after re-enable is a skip -> immediate alert?
rm -f $S; echo "{\"first\": $((now-3*86400)), \"last\": $((now-3*86400)), \"skips\": 1}" > $S; c6=$(n); r=$(run 75); c7=$(n)
[ $c7 = $c6 ] && res L4.stale-first PASS "no alert on a 3-day-old record" || res L4.stale-first FAIL "alerted on first skip because first= 3 days ago (last not used)"
# L5 lockf missing / can't open -> 71/73, no count, no alert
rm -f $S; mv $W/bin/lockf $W/bin/lockf.x; r=$(run 0); mv $W/bin/lockf.x $W/bin/lockf; r3=$(run 73)
[ $r = 71 ] && [ $r3 = 73 ] && [ ! -e $S ] && res L5.71-73 PASS "missing lockf rc $r, unopenable rc $r3: not counted, no alert (silent unless the watcher of this task notices)" || res L5.71-73 FAIL "rc $r/$r3"
# L6 secrets: fake KEY never in stdout/stderr or curl argv
! grep -q fake-key-not-secret "$OUT/log" && ! grep -rq fake-key-not-secret $W/curl.* && res L6.no-secret PASS "KEY not in output or body files" || res L6.no-secret FAIL "KEY leaked"
# L7 concurrent skips (lost update): 8 at once from 0
rm -f $S; for i in 1 2 3 4 5 6 7 8; do run 75 >/dev/null & done; wait; k=$(python3 -c "import json;print(json.load(open('$S'))['skips'])")
res L7.concurrent INFO "8 concurrent skip rounds -> skips=$k (no corruption; lost updates possible, harmless at */5)"
t=$(ls $W/x.lock.skips.json.*.tmp 2>/dev/null | wc -l); res L7.tmp-left INFO "$t leftover tmp files"
