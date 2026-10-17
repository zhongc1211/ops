#!/bin/bash
# orca-remote watchdog (rev 2026-10-14: every external step has a timeout; slow steps and the stage before a gap are logged). Loop every 45s. Single instance via flock.
# - public 530/502 while local 200 -> restart immediately (stale tunnel)
# - resume-from-pause detected (wall gap > 3x interval) -> restart immediately
# - other unhealthy states -> restart after 2 strikes
# - min 90s between restarts (anti-storm)
LOG=/workspace/ops/orca-remote/watchdog.log; R=/workspace/ops/orca-remote/orca-remote
# DISPLAY is pinned to the orca-bot desktop :4 (never inherited): 10-17 12:40 a caller passed a missing :3 and orca-bot served 502.
export DISPLAY=:4 PATH=/home/box/.local/bin:/usr/local/bin:/usr/bin:/bin
INT=45; GAP=$((INT*3)); MINGAP=90
stage=init; stage_t=$(date +%s)
# st NAME: remember what the loop is doing (explains a later gap) and log the previous step if it took >30s
st(){ d=$(( $(date +%s)-stage_t )); case $stage in sleep|restart-wait) ;; *) [ $d -gt 30 ] && log "slow step '$stage' took ${d}s";; esac; stage=$1; stage_t=$(date +%s); }
log(){ echo "[$(date '+%F %T %Z')] $*" >>$LOG; }
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
exec 9>/tmp/orca-remote-watchdog.lock; flock -n 9 || exit 0
last_restart=0; last_loop=$(date +%s); last_up=$(cut -d. -f1 /proc/uptime); f=0
restart(){ now=$(date +%s)
  if [ $((now-last_restart)) -lt $MINGAP ]; then log "restart wanted ($1) but backoff ($((now-last_restart))s<${MINGAP}s)"; return; fi
  log "-> restart: $1"; st restart; timeout 180 $R restart >>$LOG 2>&1 9>&-; [ $? = 124 ] && log "restart TIMED OUT after 180s"; st restart-wait; last_restart=$(date +%s); f=0; sleep 20 9>&-
  log "post-restart local=$(curl -s -o /dev/null -w '%{http_code}' -m 10 http://127.0.0.1:6768/) public=$(curl -s -o /dev/null -w '%{http_code}' -m 15 https://orca-bot.deepvision.sg/)"; }
log "watchdog started pid $$ (interval ${INT}s, resume gap ${GAP}s, min restart gap ${MINGAP}s)"
while true; do
  now=$(date +%s); upn=$(cut -d. -f1 /proc/uptime); gap=$((now-last_loop)); upd=$((upn-last_up)); last_loop=$now
  if [ $gap -gt $GAP ]; then log "resume from pause detected (gap ${gap}s)"; log "last stage before gap: '$stage' (set $((now-stage_t))s ago); guest clock advanced ${upd}s while wall clock advanced ${gap}s ($([ $upd -lt $((gap/2)) ] && echo 'guest clock STOPPED = VM paused/suspended' || echo 'guest clock ran = loop stalled inside the guest'))"; restart "resume"; last_loop=$(date +%s); last_up=$(cut -d. -f1 /proc/uptime); fi
  st curl-local; l=$(curl -s -o /dev/null -w '%{http_code}' -m 10 http://127.0.0.1:6768/)
  st curl-public; p=$(curl -s -o /dev/null -w '%{http_code}' -m 15 https://orca-bot.deepvision.sg/)
  st repair-check; if repair_app; then restart "app re-extracted"; last_loop=$(date +%s); last_up=$(cut -d. -f1 /proc/uptime); sleep $INT 9>&-; continue; fi
  st tmux-has-session; timeout 20 tmux has-session -t orca-remote 2>/dev/null; trc=$?
  if [ $trc = 124 ]; then log "tmux has-session TIMED OUT after 20s (local=$l public=$p) - not starting a second session"
  elif [ $trc != 0 ]; then log "tmux session missing (local=$l public=$p) -> start"; st start; timeout 180 $R start >>$LOG 2>&1 9>&-; [ $? = 124 ] && log "start TIMED OUT after 180s"; st restart-wait; last_restart=$(date +%s); sleep 20 9>&-
  elif [ "$l" = 200 ] && { [ "$p" = 530 ] || [ "$p" = 502 ]; }; then log "stale tunnel local=$l public=$p"; restart "stale tunnel"
  elif [ "$l" = 000 ] || [ "$p" != 200 ]; then
    f=$((f+1)); log "unhealthy local=$l public=$p (strike $f)"
    [ $f -ge 2 ] && restart "unhealthy x2"
  else f=0; fi
  [ $(stat -c%s $LOG) -gt 1000000 ] && mv $LOG $LOG.old
  st sleep; last_loop=$(date +%s); last_up=$(cut -d. -f1 /proc/uptime); sleep $INT 9>&-
done
