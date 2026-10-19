#!/bin/bash
# orca-remote watchdog (rev 2026-10-19). Loop every 45s. Single instance via flock. Every external step has a timeout.
# rev 2026-10-17b: a VM pause/resume is NOT a failure. Before this rev every resume restarted Orca (294 of 358 restarts
#   10-10..10-17, 291 of them came back 200 = Orca was fine). Now a resume only opens a grace window; restarts need real failures.
# - resume-from-pause detected (wall gap > 3x interval) -> log only, start ${GRACE}s grace (failures in grace are not counted)
# - after any restart/start -> same grace (orca-ide serve can take ~60-75s to come up)
# - public 530/502 while local 200 (stale tunnel) -> after 2 consecutive strikes restart ONLY cloudflared (Orca untouched)
# - other unhealthy states -> full restart after 2 consecutive strikes outside grace
# - min 90s between restarts (anti-storm; rev 2026-10-19: MINGAP, doubling up to MAXGAP)
# rev 2026-10-18: after a resume the tunnel is usually what breaks (10-18 01:00..04:25 SGT, 5x local 200 / public 530 = CF 1033,
#   each fixed by restarting cloudflared alone). So inside the resume grace, the first local 200 + public 530 restarts ONLY
#   cloudflared right away (no strikes), then rechecks public for up to 60s and needs 3 consecutive 200s. If that fails the
#   grace ends and the normal strike logic above takes over.
# rev 2026-10-19: the 10-19 outages (10:00, 11:57, 13:10, 14:05 SGT) were the whole guest freezing 8-29 min in memory thrash
#   (16G, no swap; guest clock kept running), not VM pauses (only 13:55 was one). cloudflared re-registered by itself 1-12s
#   after each freeze; the watchdog made recovery worse (ops reports/orca-bot-tunnel-1019). Changes:
# - a freeze is detected in every phase, not only in sleep: sleep overran by > STALL_SLACK, or the probes took longer than their
#   curl timeouts + STALL_SLACK (13:22 sat 1142s inside curl-local and only logged a slow step). Probes from a frozen loop are dropped.
# - guest clock STOPPED (VM pause) -> as before: resume grace + cloudflared-only fast path. Guest clock RAN (freeze inside the
#   guest) -> no fast path (13:49 killed a cloudflared that would have healed); ${STALL_GRACE}s grace, strikes cleared.
# - strikes are consecutive only if the previous one is <= STRIKE_WIN s old (13:02 strike 1 + 13:22 strike 2 across a freeze
#   killed cloudflared 1s after it re-registered).
# - cloudflared is never killed while tunnel.log has a "Registered tunnel connection" from the last CF_FRESH s (after a VM
#   pause the fast path then retries next loop, while the resume grace lasts).
# - full Orca restart is deferred while memory PSI "full avg10" > PSI_MAX % (restarting into thrash only adds load; 11:55:59
#   restarted an Orca that was back by itself at 11:56:45), at most DEFER_MAX s; a freeze starts the deferral over. Gap between
#   restarts doubles MINGAP..MAXGAP, back to MINGAP once a restart is MAXGAP old.
# - state file $STATE (state=ok|unhealthy|stalled|paused|deferred|restarting, since=epoch, ...) for whoever decides to wake
#   someone (stuck-check / orca-bot-guard do not read it yet).
# WATCHDOG_* env vars below are for the scratch drill (orca-remote/drill); defaults are production.
LOG=${WATCHDOG_LOG:-/workspace/ops/orca-remote/watchdog.log}; R=${ORCA_REMOTE_BIN:-/workspace/ops/orca-remote/orca-remote}
STATE=${WATCHDOG_STATE:-/workspace/ops/orca-remote/watchdog.state}; TLOG=${WATCHDOG_TUNNEL_LOG:-/home/box/.local/state/orca-remote/tunnel.log}
UPF=${WATCHDOG_UPTIME_FILE:-/proc/uptime}; PSIF=${WATCHDOG_PSI_MEM:-/proc/pressure/memory}; SESSION=${WATCHDOG_SESSION:-orca-remote}
# DISPLAY is pinned to the orca-bot desktop :4 (never inherited): 10-17 12:40 a caller passed a missing :3 and orca-bot served 502.
export DISPLAY=:4 PATH=/home/box/.local/bin:/usr/local/bin:/usr/bin:/bin
INT=${WATCHDOG_INT:-45}; MINGAP=${WATCHDOG_MINGAP:-90}; MAXGAP=${WATCHDOG_MAXGAP:-900}; GRACE=${WATCHDOG_GRACE:-120}
STALL_SLACK=${WATCHDOG_STALL_SLACK:-30}; STALL_GRACE=${WATCHDOG_STALL_GRACE:-180}; STRIKE_WIN=$((2*INT+STALL_SLACK))
T_LOCAL=10; T_PUB=15; CF_FRESH=${WATCHDOG_CF_FRESH:-60}; PSI_MAX=${WATCHDOG_PSI_MAX:-10}; DEFER_MAX=${WATCHDOG_DEFER_MAX:-300}
grace_until=0; ts=0; resumed=0; last_strike=0; defer_since=0; rgap=$MINGAP; last_stall=0; wst=init; wsince=$(date +%s); wdet=""
LOCAL=${WATCHDOG_LOCAL_URL:-http://127.0.0.1:6768/}
PUB=${WATCHDOG_PUBLIC_URL:-https://orca-bot.deepvision.sg/}; PBODY=${WATCHDOG_PBODY:-/tmp/orca-remote-watchdog.public-body}
CF_MATCH=${WATCHDOG_CF_MATCH:-"cloudflared tunnel --config /home/box/.cloudflared/config.yml"}
stage=init; stage_t=$(date +%s)
# st NAME: remember what the loop is doing (explains a later gap) and log the previous step if it took >30s
st(){ d=$(( $(date +%s)-stage_t )); case $stage in sleep|restart-wait) ;; *) [ $d -gt 30 ] && log "slow step '$stage' took ${d}s";; esac; stage=$1; stage_t=$(date +%s); }
log(){ echo "[$(date '+%F %T %Z')] $*" >>$LOG; }
up(){ cut -d. -f1 "$UPF"; }
# setst STATE DETAIL / wstate: state file for wake logic; since = when the state last changed. Written atomically.
setst(){ [ "$1" = "$wst" ] || { wst=$1; wsince=$(date +%s); }; wdet=$2; }
wstate(){ printf 'state=%s\nsince=%s\nupdated=%s\nupdated_at=%s\ndetail=%s\nlocal=%s\npublic=%s\nlast_stall=%s\nlast_restart=%s\npid=%s\n' \
  "$wst" "$wsince" "$(date +%s)" "$(date '+%F %T %Z')" "$wdet" "${l:-}" "${p:-}" "$last_stall" "$last_restart" $$ >"$STATE.tmp" && mv -f "$STATE.tmp" "$STATE"; }
# App self-repair: if Orca app files are missing, re-extract the saved .deb (override APP/DEB for tests)
APP=${ORCA_APP_DIR:-/workspace/ops/orca-app/Orca}; DEB=${ORCA_DEB:-/workspace/ops/orca-app/orca-ide_1.4.224_amd64.deb}
app_ok(){ [ -f "$APP/resources/app.asar.unpacked/out/cli/index.js" ] && [ -x "$APP/resources/bin/orca-ide" ] && [ -f "$APP/chrome-sandbox" ]; }
repair_app(){ app_ok && return 1
  log "Orca app files missing under $APP -> re-extract $DEB"
  [ -f "$DEB" ] || { log "repair FAILED: installer $DEB missing"; return 2; }
  t=$(mktemp -d "$(dirname "$APP")/.reextract.XXXX") || return 2
  if timeout 120 dpkg-deb -x "$DEB" "$t" && [ -d "$t/opt/Orca" ]; then
    [ -e "$APP" ] && mv "$APP" "$APP.broken-$(date +%Y%m%d%H%M%S)"
    mv "$t/opt/Orca" "$APP"; rm -rf "$t"
    timeout 10 sudo -n chown root "$APP/chrome-sandbox" && timeout 10 sudo -n chmod 4755 "$APP/chrome-sandbox" || log "warn: chrome-sandbox perms not set"
    app_ok && { log "repair ok"; return 0; }
  fi
  rm -rf "$t"; log "repair FAILED"; return 2; }
[ -n "${WATCHDOG_REPAIR_ONLY:-}" ] && { repair_app; exit $?; }
exec 9>${WATCHDOG_LOCK:-/tmp/orca-remote-watchdog.lock}; flock -n 9 || exit 0
last_restart=0; last_loop=$(date +%s); last_up=$(up); f=0
# froze WALL0 UP0 LIMIT PHASE EXPECTED: did more than LIMIT wall seconds pass since (WALL0, UP0)? If so classify by the guest
# clock, open the matching grace, clear strikes, return 0. EXPECTED = seconds the phase should take (INT for sleep). The guest
# clock missed more than half of the overrun = VM paused (a 40s pause in a 45s sleep counts too); else the guest froze.
froze(){ local n u wd ud; n=$(date +%s); u=$(up); wd=$((n-$1)); ud=$((u-$2)); [ $wd -le $3 ] && return 1
  if [ $(( 2*(wd-ud) )) -gt $((wd-$5)) ]; then
    log "resume from pause detected ($4 took ${wd}s, guest clock advanced ${ud}s = VM paused/suspended); grace ${GRACE}s, stale tunnel -> cloudflared-only at once"
    grace_until=$((n+GRACE)); resumed=1; setst paused "guest clock stopped $((wd-ud))s of ${wd}s"
  else
    log "guest freeze detected ($4 took ${wd}s, guest clock advanced ${ud}s = box frozen inside the guest, e.g. memory thrash); grace ${STALL_GRACE}s, cloudflared left to re-register, no strikes"
    grace_until=$((n+STALL_GRACE)); resumed=0; last_stall=$n; setst stalled "frozen ${wd}s in $4"
  fi
  f=0; ts=0; defer_since=0; wstate; return 0; }
# cf_fresh: print how many seconds ago cloudflared last logged "Registered tunnel connection", if within CF_FRESH
cf_fresh(){ local t a; t=$(tail -n 300 "$TLOG" 2>/dev/null | grep 'Registered tunnel connection' | tail -n 1 | sed -n 's/.*"time":"\([^"]*\)".*/\1/p')
  [ -n "$t" ] && t=$(date -d "$t" +%s 2>/dev/null) && a=$(( $(date +%s)-t )) && [ $a -le $CF_FRESH ] && echo $a; }
# tunnel_fix WHY: restart ONLY cloudflared (the tmux tunnel-loop respawns it after 5s; Orca serve and tmux untouched), then recheck
# public every 3s for up to 60s; ok = 3 consecutive 200s. KILL if TERM is ignored (a stopped/hung cloudflared never handles TERM).
# Returns 2 without killing when cloudflared re-registered within CF_FRESH s (it is reconnecting by itself).
tunnel_fix(){ local a old i t0 ok c; a=$(cf_fresh); if [ -n "$a" ]; then log "cloudflared re-registered ${a}s ago -> not killing it ($1); recheck next loop"; return 2; fi
  log "-> tunnel-only restart: $1 (cloudflared; Orca untouched)"; st tunnel-restart
  # after a VM pause the state stays "paused" (the reason the tunnel is down); otherwise "restarting". Written now: the fix takes up to 65s
  if [ "$wst" = paused ]; then wdet="$wdet; restarting cloudflared"; else setst restarting "cloudflared: $1"; fi; wstate
  old=$(pgrep -f "$CF_MATCH"); [ -n "$old" ] && kill $old 2>/dev/null
  for i in 1 2 3 4 5; do kill -0 $old 2>/dev/null || break; sleep 1 9>&-; done
  kill -0 $old 2>/dev/null && { log "cloudflared $old ignored TERM -> KILL"; kill -KILL $old 2>/dev/null; }
  st tunnel-verify; t0=$(date +%s); ok=0; c=000
  while [ $(( $(date +%s)-t0 )) -lt 60 ]; do sleep 3 9>&-; c=$(curl -s -o /dev/null -w '%{http_code}' -m 10 $PUB); [ "$c" = 200 ] && ok=$((ok+1)) || ok=0; [ $ok -ge 3 ] && break; done
  if [ $ok -ge 3 ]; then log "tunnel-only restart verified: public 200 x3, $(( $(date +%s)-t0 ))s after kill"; return 0; fi
  log "tunnel-only restart NOT verified within 60s (last public=$c)"; return 1; }
psi_full(){ sed -n 's/^full avg10=\([0-9]*\).*/\1/p' "$PSIF" 2>/dev/null; }
restart(){ now=$(date +%s)
  if [ $((now-last_restart)) -lt $rgap ]; then log "restart wanted ($1) but backoff ($((now-last_restart))s<${rgap}s)"; setst unhealthy "restart backoff"; return; fi
  psv=$(psi_full)
  if [ "${psv:-0}" -gt "$PSI_MAX" ]; then [ $defer_since = 0 ] && defer_since=$now
    if [ $((now-defer_since)) -lt $DEFER_MAX ]; then log "restart wanted ($1) but memory pressure full avg10=${psv}% > ${PSI_MAX}% (box thrashing, a restart adds load) -> deferred $((now-defer_since))s of max ${DEFER_MAX}s"; setst deferred "memory pressure ${psv}%"; return; fi
    log "memory pressure still ${psv}% after ${DEFER_MAX}s of deferral -> restarting anyway"; fi
  defer_since=0; prev=$last_restart
  log "-> restart: $1"; st restart; setst restarting "orca: $1"; wstate; timeout 180 $R restart >>$LOG 2>&1 9>&-; [ $? = 124 ] && log "restart TIMED OUT after 180s"; st restart-wait; last_restart=$(date +%s); f=0; ts=0; resumed=0; grace_until=$((last_restart+GRACE))
  if [ $prev -gt 0 ] && [ $((last_restart-prev)) -lt $MAXGAP ]; then rgap=$((rgap*2)); [ $rgap -gt $MAXGAP ] && rgap=$MAXGAP; log "next restart allowed after ${rgap}s"; else rgap=$MINGAP; fi
  sleep 20 9>&-
  log "post-restart local=$(curl -s -o /dev/null -w '%{http_code}' -m 10 $LOCAL) public=$(curl -s -o /dev/null -w '%{http_code}' -m 15 $PUB)"; }
log "watchdog started pid $$ (interval ${INT}s, freeze slack ${STALL_SLACK}s, freeze grace ${STALL_GRACE}s, resume grace ${GRACE}s, restart gap ${MINGAP}..${MAXGAP}s, defer while PSI full > ${PSI_MAX}% for max ${DEFER_MAX}s)"
setst ok "started"; wstate
while true; do
  froze $last_loop $last_up $((INT+STALL_SLACK)) "sleep" $INT
  t0=$(date +%s); u0=$(up)
  st curl-local; l=$(curl -s -o /dev/null -w '%{http_code}' -m $T_LOCAL $LOCAL)
  st curl-public; p=$(curl -s -o $PBODY -w '%{http_code}' -m $T_PUB $PUB)
  # probes are capped at T_LOCAL+T_PUB s; taking longer means the box froze under them -> their results describe the freeze, drop them
  if froze $t0 $u0 $((T_LOCAL+T_PUB+STALL_SLACK)) "probes (local=$l public=$p)" 0; then st sleep; wstate; last_loop=$(date +%s); last_up=$(up); sleep $INT 9>&-; continue; fi
  now=$(date +%s); [ $now -ge $grace_until ] && resumed=0
  # strikes count as consecutive only if the previous strike is recent (a strike before a freeze must not pair with one after it)
  [ $((now-last_strike)) -gt $STRIKE_WIN ] && { f=0; ts=0; }
  st repair-check; if repair_app; then restart "app re-extracted"; wstate; last_loop=$(date +%s); last_up=$(up); sleep $INT 9>&-; continue; fi
  st tmux-has-session; timeout 20 tmux has-session -t $SESSION 2>/dev/null; trc=$?
  if [ $trc = 124 ]; then log "tmux has-session TIMED OUT after 20s (local=$l public=$p) - not starting a second session"
  elif [ $trc != 0 ]; then log "tmux session missing (local=$l public=$p) -> start"; st start; setst restarting "tmux session missing"; timeout 180 $R start >>$LOG 2>&1 9>&-; [ $? = 124 ] && log "start TIMED OUT after 180s"; st restart-wait; last_restart=$(date +%s); grace_until=$((last_restart+GRACE)); sleep 20 9>&-
  elif [ $resumed = 1 ] && [ "$l" = 200 ] && [ "$p" = 530 ]; then
    log "stale tunnel after resume local=$l public=$p$(grep -qs 1033 $PBODY && echo ' (CF 1033)') -> immediate fix, no strikes"
    tunnel_fix "resume + local 200 + public 530"; case $? in 0) resumed=0; f=0; ts=0;; 2) ts=0;; *) resumed=0; grace_until=0; ts=1; last_strike=$(date +%s); log "resume fast-path failed -> normal strike logic (stale strike 1)";; esac
  elif [ $now -lt $grace_until ] && { [ "$l" = 000 ] || [ "$p" != 200 ]; }; then log "unhealthy local=$l public=$p during grace ($((grace_until-now))s left) - not counted"
  elif [ "$l" = 200 ] && { [ "$p" = 530 ] || [ "$p" = 502 ]; }; then
    ts=$((ts+1)); f=0; last_strike=$now; log "stale tunnel local=$l public=$p (strike $ts)"; setst unhealthy "stale tunnel strike $ts"
    if [ $ts -ge 2 ]; then tunnel_fix "stale tunnel x2"; ts=0; fi
  elif [ "$l" = 000 ] || [ "$p" != 200 ]; then
    f=$((f+1)); ts=0; last_strike=$now; log "unhealthy local=$l public=$p (strike $f)"; setst unhealthy "strike $f local=$l public=$p"
    [ $f -ge 2 ] && restart "unhealthy x2"
  else f=0; ts=0; defer_since=0; setst ok ""
    [ $last_restart -gt 0 ] && [ $rgap -gt $MINGAP ] && [ $((now-last_restart)) -ge $MAXGAP ] && { rgap=$MINGAP; log "healthy ${MAXGAP}s after last restart -> restart gap back to ${MINGAP}s"; }
  fi
  [ $(stat -c%s $LOG) -gt 1000000 ] && mv $LOG $LOG.old
  st sleep; wstate; last_loop=$(date +%s); last_up=$(up); sleep $INT 9>&-
done
